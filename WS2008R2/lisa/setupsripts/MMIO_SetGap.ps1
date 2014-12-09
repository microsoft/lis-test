########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved. 
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0  
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################


<#
.Synopsis
    

.Description
    

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>
############################################################################
# MMIO_SetGap.ps1
#
# Description:
# This powershell setup script implements TC 2.3.1 and TC-2.3.3. It verifies 
# setting PCI_hole size in the linux VM for against various VM memory sizes.
# This setup script should be executed with its corresponding Verify_pcihole.sh
# test script. This script also require MMIO_VerifyGapFile.ps1 setup script to be 
# run as a pretest script.
# 
#
# The following is an example of a seting XML tags for this test.
#     <test>
#        <testName>Verify_pcihole-run1</testName>
#	    <pretest>SetupScripts\VerifyGapFile.ps1</pretest>
#	    <setupScript>SetupScripts\SetMmiogap-2.3.1.ps1</setupScript>
#	    <testScript>Verify_pcihole.sh</testScript>
#	    <files>remote-scripts/ica/Verify_pcihole.sh</files>
#       <timeout>600</timeout>
#     </test>  
#
############################################################################

param([string] $vmName, [string] $hvServer, [string] $testParams)

############################################################################
#
# Defining MMIO Gap sizes and VM Memory sizes from the predefined valid set 
# for the test
#
############################################################################
$newGapSize = (3584, 2555, 1238, 943, 745, 386, 2785, 3129, 1468, 128) | Get-Random

$vmMemory = (512, 1024, 3072, 4096, 2048, 0) | Get-Random  # All values are in MB

############################################################################
#
# GetVmSettingData()
#
# Getting all VM's system settings data from the host hyper-v server
#
############################################################################
function GetVmSettingData([String] $name, [String] $server)
{
    $settingData = $null

    if (-not $name)
    {
        return $null
    }

    $vssd = gwmi -n root\virtualization\v2 -class Msvm_VirtualSystemSettingData -ComputerName $server
    if (-not $vssd)
    {
        return $null
    }

    foreach ($vm in $vssd)
    {
        if ($vm.ElementName -ne $name)
        {
            continue
        }

        return $vm
    }

    return $null
}
###########################################################################
#
# SetMMIOGap()
#
# Description:Function to validate and set the MMIO Gap to the linux VM
#
###########################################################################
function SetMMIOGap([INT] $newGapSize)
{

    #
    # Getting the VM settings
    #
    $vssd = GetVmSettingData $vmName $hvServer
    if (-not $vssd)
    {
        return $false
    }
    
    #
    # Create a management object
    #
    $mgmt = gwmi -n root\virtualization\v2 -class Msvm_VirtualSystemManagementService -ComputerName $hvServer
    if(-not $mgmt)
    {
        return $false
    }

    #
    # Setting the new PCI hole size
    #
    $vssd.LowMmioGapSize = $newGapSize

    $sts = $mgmt.ModifySystemSettings($vssd.gettext(1))
    
    if ($sts.ReturnValue -eq 0) 
    {
        return $true
    }

    return $false
}
#######################################################################
#
# Main script body
#
#######################################################################
$retVal = $false

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    switch ($fields[0].Trim())
    {
    "rootdir" { $rootDir = $fields[1].Trim() }
    default   {}  # unknown param - just ignore it
    }
}

#
# Check input arguments
#
if (-not $vmName)
{
    "Error: VM name is null. "
    return $retVal
}

if (-not $hvServer)
{
    "Error: hvServer is null"
    return $retVal
}


#
# Change the working directory to where we need to be
#
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

cd $rootDir

#
# Verifying if the VM is in Off state prior to setting pci_hole size
#
$vm = Get-VM -Name $vmName -ComputerName $hvServer
if ($vm.state -ne "off")
{
    "Error: PCI_hole value can not be set to a running VM."
    exit 20
}

#
# Preparing for setting VM Memory to the value from predefined list
#
"Info: Setting VM Memory to $vmMemory MB"

#
# Assigning 70% of the available memory to the VM when 0MB gets randomly selected as VM Memory
#
if ($vmMemory -eq 0)
{
    "Info: Assigning 70% of the available memory to the VM since 0MB has been randomly selected as VM Memory"
    $freeMem = [Double] (Get-WMIObject Win32_OperatingSystem -ComputerName $hvServer).FreePhysicalMemory
    if (-not $freeMem)
    {
        "Error: Unable to determine free memory"
        return $False
    }

    #
    # Convert from KB to MB, compute 70% of free memory, then make sure our value is 2MB aligned
    #
    $vmMemory = [Long] (($freeMem / 1024.0) * 0.70)
    if ($($vmMemory % 2) -ne 0)
    {
        $vmMemory -= 1
    }
}

#
# Convert from MB to Bytes
#
$vmMemory = $vmMemory * 1024 * 1024
"Info : VM Memory is : $vmMemory"

#
# Setting the memory on the VM
#        
Set-VMMemory $vmName -StartupBytes $vmMemory -MaximumBytes $vmMemory -ComputerName $hvServer -Buffer 20 -DynamicMemoryEnabled 1
if(!$?)
{
    "Error: Setting VM Memory operation failed"
}

#
# Saving the gapsize to a file for verification
#
echo gap=$newGapSize | out-file -encoding ASCII -filePath .\remote-scripts\ica\${vmName}_gapSize.sh

#
# Setting the MMIO hole to the linux VM
#
$results = SetMMIOGap $newGapSize
    
if ("$results" -ne "True")
{
    "Error: Setting gap size to ${gapSize} returned unexpected results"
    "Info : Test Failed"
    $errorsDetected = $True
}
    
$vssd = GetVmSettingData $vmName $hvServer
if (-not $vssd)
{
    "Error: Unable to find settings data for VM '${vmName}'"
    return $false
}

"Info: New gap size = $($vssd.LowMmioGapSize) MB"

#
# Validating results
#
if (-not $errorsDetected)
{
    $retVal = $True
}

return $retval
