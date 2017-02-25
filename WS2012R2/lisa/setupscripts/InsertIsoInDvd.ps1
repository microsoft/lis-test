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
    Mount an ISO file in the VM default DVD drive.

.Description
    Mount a .iso in the default DVD drive.

.Parameter vmName
    Name of the VM with the DVD drive to mount.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParam
    Semicolon separated list of test parameters.

.Example
    .\InsertIsoInDvd.ps1 "testVM" "localhost" "isoFilename=test.iso"
#>

param ([String] $vmName, [String] $hvServer, [String] $testParams)

$retVal = $False
$isoFilename = $null
$vmGeneration = $null

#######################################################################
#
# Main script body
#
#######################################################################

# Check arguments
if (-not $vmName)
{
    "Error: Missing vmName argument"
    return $False
}

if (-not $hvServer)
{
    "Error: Missing hvServer argument"
    return $False
}

if (-not $testParams)
{
    "Error: Missing testParams argument"
    return $False
}

# Source TCUtils.ps1 for common functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
	. .\setupScripts\TCUtils.ps1
	"Info: Sourced TCUtils.ps1"
}
else {
	"Error: Could not find setupScripts\TCUtils.ps1"
	return $false
}

#
# Extract the testParams we are concerned with
#
$params = $testParams.Split(';')
foreach ($p in $params)
{
    if ($p.Trim().Length -eq 0)
    {
        continue
    }

    $tokens = $p.Trim().Split('=')
    
    if ($tokens.Length -ne 2)
    {
	# Just ignore it
	continue
    }
    
    $lValue = $tokens[0].Trim()
    $rValue = $tokens[1].Trim()
    
    if ($lValue -eq "IsoFilename")
    {
        $isoFilename = $rValue
    }
}

#
# Checking the mandatory testParams. New parameters must be validated here.
#
if (-not $isoFilename)
{
    "Error: Test parameters is missing the IsoFilename parameter"
    return $False
}

$error.Clear()

$vmGeneration = Get-VM $vmName -ComputerName $hvServer| select -ExpandProperty Generation -ErrorAction SilentlyContinue
if ($? -eq $False)
{
   $vmGeneration = 1
}

#
# Make sure the DVD drive exists on the VM
#
if ($vmGeneration -eq 1)
{
    $dvd = Get-VMDvdDrive $vmName -ComputerName $hvServer -ControllerLocation 1 -ControllerNumber 1
}
else
{
    $dvd = Get-VMDvdDrive $vmName -ComputerName $hvServer -ControllerLocation 2 -ControllerNumber 0
}
if ($dvd)
{
    Remove-VMDvdDrive $dvd -Confirm:$False
    if($? -ne "True")
    {
        "Error: Cannot remove DVD drive from ${vmName}"
        $error[0].Exception
        return $False
    }
}

#
# Make sure the .iso file exists on the Hyper-V server
#
if (-not ([System.IO.Path]::IsPathRooted($isoFilename)))
{
    $obj = Get-WmiObject -ComputerName $hvServer -Namespace "root\virtualization\v2" -Class "MsVM_VirtualSystemManagementServiceSettingData"
        
    $defaultVhdPath = $obj.DefaultVirtualHardDiskPath
	
    if (-not $defaultVhdPath)
    {
        "Error: Unable to determine VhdDefaultPath on Hyper-V server ${hvServer}"
        $error[0].Exception
        return $False
    }
   
    if (-not $defaultVhdPath.EndsWith("\"))
    {
        $defaultVhdPath += "\"
    }
  
    $isoFilename = $defaultVhdPath + $isoFilename
   
}   

$isoFileInfo = GetRemoteFileInfo $isoFilename $hvServer
if (-not $isoFileInfo)
{
    "Error: The .iso file $isoFilename does not exist on HyperV server ${hvServer}"
    return $False
}

#
# Insert the .iso file into the VMs DVD drive
#
if ($vmGeneration -eq 1)
{
    Add-VMDvdDrive -VMName $vmName -Path $isoFilename -ControllerNumber 1 -ControllerLocation 1 -ComputerName $hvServer -Confirm:$False
}
else
{
    Add-VMDvdDrive -VMName $vmName -Path $isoFilename -ControllerNumber 0 -ControllerLocation 2 -ComputerName $hvServer -Confirm:$False
}
if ($? -ne "True")
{
    "Error: Unable to mount the ISO file!"
    $error[0].Exception
    return $False
}
else
{
    $retVal = $True
}

return $retVal
