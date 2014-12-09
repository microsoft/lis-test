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
#######################################################################
#
# Resize_TC_2.3.3.ps1
#
# Description:
#    This is a PowerShell test case script that implements Dynamic
#    Resizing of VHDX test case 2.3.3.  This test case requires the
#    vhdx file of a running VM be increased in size, and then shrunk.
#    The VM should see the new size after the VHDX is increased in
#    size as well as the smaller size when the VHDX is reduced in size.
#
#    All test case scripts that run under ICA or LiSA accept three
#    arguments:
#        vmName    : The name of the VM under test.
#        hvServer  : The name of the HyperV server hosting vmName.
#        testParam : A semicolon separated list of test parameters.
#                    Test parameters are key/value pairs.  An example
#                    string of testParams would look like:
#                    "ipv4=10.200.41.2;sshKey=rhel5_id_rsa.ppk;rootDir=D:\ica\trunk\ica"
#
#    Test Params used by this script
#        ipv4    = IPv4 address of the test VM.
#        sshKey  = The SSH key to use when talking to the VM.
#        NewSize = The size, in MB to grow the VHDX.
#    
#
#
#######################################################################

param ([string] $vmName, [String] $hvServer, [string] $testParams)


#######################################################################
#
# Main script body
#
#######################################################################

$retVal = $False

#
# Check the cmdline arguments
#
"Info : Checking command line arguments"

if (-not $vmName)
{
    "Error: The vmName argument was not specified"
    return $False
}

if (-not $hvServer)
{
    "Error: The hvServer argument was not specified"
    return $False
}

if (-not $testParams)
{
    "Error: No testParams specified"
    return $False
}

#
# Display the test params in the log for debug purposes
#
"Test Params: ${testParams}"

#
# Parse the testParams
#
$sshKey    = $null
$ipv4      = $null
$newSize   = $null
$rootDir   = $null
$tcCovered = "unknown"

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    if ($fields.Length -ne 2)
    {
        continue   # just ignore malformed test params
    }
    
    $value = $fields[1].Trim()

    switch ($fields[0].Trim())
    {
    "SSHKey"    { $sshKey    = $value }
    "ipv4"      { $ipv4      = $value }
    "newSize"   { $newSize   = $value }
    "rootDIR"   { $rootDir   = $value }
    "tcCovered" { $tcCovered = $value }
    default     {}  # unknown param - just ignore it
    }
}

#
# Make sure all required test parameters were found
#
if (-not $ipv4)
{
    "Error: no ipv4 parameter in testParams"
    return $False
}

if (-not $sshKey)
{
    "Error: no sshKey parameter in testParams"
    return $False
}

if (-not $newSize)
{
    "Error: no newSize parameter in testParams"
    return $False
}

"Info : ipv4      = ${ipv4}"
"Info : sshKey    = ${sshKey}"
"Info : newSize   = ${newSize}"
"Info : rootDir   = ${rootDir}"
"Info : tcCovered = ${tcCovered}"

#
# Convert the new vhdx size to a UInt64
#
if ($newSize.EndsWith("MB"))
{
    $num = $newSize.Replace("MB","")
    $newVhdxSize = ([Convert]::ToUInt64($num)) * 1MB
}
elseif ($newSize.EndsWith("GB"))
{
    $num = $newSize.Replace("GB","")
    $newVhdxSize = ([Convert]::ToUInt64($num)) * 1GB
}
elseif ($newSize.EndsWith("TB"))
{
    $num = $newSize.Replace("TB","")
    $newVhdxSize = ([Convert]::ToUInt64($num)) * 1TB
}
else
{
    "Error: Invalid newSize parameter: ${newSize}"
    return $False
}

"Info : newVhdxSize = ${newVhdxSize}"

#
# Make sure the new VHDX size is with in range that we currently allow
#
if ($newVhdxSize -lt 1GB -or $newVhdxSize -gt 128GB)
{
    "Error: newSize is out of range: ${newSize} (${newVhdxSize})"
    return $False
}

#
# Process the rootDir variable.  This is required for LiSA.
#
if ($rootDir)
{
    if (-not (Test-Path $rootDir))
    {
        "Error: rootDir contains an invalid path"
        return $False
    }

    cd $rootDir
    "Info : current directory is ${PWD}"
}

#
# Log the TCs this script covers in summary.log
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers ${tcCovered}" | Out-File $summaryLog

#
# Source the Test Case utilities
#
. .\SetupScripts\TCUtils.ps1
if (-not $?)
{
    "Error: Unable to source the TCUtils.ps1 library"
    return $False
}

#
# Make sure the VM has a SCSI 0 controller, and than
# Lun 0 on the controller has a .vhdx file attached.
#
"Info : Check if VM ${vmName} has a SCSI 0 Lun 0 drive"
$scsi00 = Get-VMHardDiskDrive -VMName $vmName -Controllertype SCSI -ControllerNumber 0 -ControllerLocation 0 -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $scsi00)
{
    "Error: VM ${vmName} does not have a SCSI 0 Lun 0 drive"
    $error[0].Exception.Message
    return $False
}

"Info : Check if the virtual disk file exists"
$vhdPath = $scsi00.Path
if (-not (GetRemoteFileInfo $vhdPath $hvServer))
{
    "Error: The vhdx file (${vhdPath} does not exist on server ${hvServer}"
    return $False
}

"Info : Verify the file is a .vhdx"
if (-not $vhdPath.EndsWith(".vhdx"))
{
    "Error: SCSI 0 Lun 0 virtual disk is not a .vhdx file."
    "       Path = ${vhdPath}"
    return $False
}

#
# Make sure the Linux guest detected the new drive
#
"Info : Check if the Linux guest sees the drive"
$sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "ls -1 /dev/sdb" 2> $null
if (-not $?)
{
    "Error: Unable to examine disk on VM"
    return $False
}

#
# If there is a partition table, do not create a new one
#
"Info : Check if there is a partition table on the drive"
$sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "ls -1 /dev/sdb1" 2> $null
if (-not $?)
{
    "Info : Zero out the partition table area with dd command"
    $sts = SendCommandToVM $ipv4 $sshKey "dd if=/dev/zero of=/dev/sdb bs=1k count=1" 2> $null
    if (-not $?)
    {
        "Error: Unable to remove partition table from disk"
        return $False
    }

    #
    # Create a partition table
    #
    "Info : Run fdisk on /dev/sdb"
    if (-not (SendCommandToVM $ipv4 $sshKey "(echo n;echo p;echo 1;echo ;echo ;echo w) | fdisk /dev/sdb" 2> $null))
    {
        "Error: Unable to create partition table on /dev/sdb"
        return $False
    }
}

#
# Get the original size of the VHDX file
#
$vhdx = Get-VHD -Path $vhdPath -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vhdx)
{
    "Error: Unable to collect metrics on ${vhdPath}"
    $error[0].Exception.Message
    return $False
}

$originalSize = $vhdx.Size

#
# Loop growing and shrinking the VHDX 
#
for ($i=0; $i -lt 10; $i++)
{
    #
    # Grow the VHDX file
    #
    "Info : Resizing the VHDX to ${newSize}"
    Resize-VHD -Path $vhdPath -SizeBytes ($newVhdxSize) -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $?)
    {
       "Error: Unable to grow VHDX file '${vhdPath}"
       $error[0].Exception.Message
       return $False 
    }

    #
    # Verify the VHDX is the correct size
    #
    "Info : Verify vhdx is now ${newVhdxSize} bytes"
    $vhdx = Get-VHD -Path $vhdPath -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $vhdx)
    {
        "Error: Unable to collect information on the VHDX file ${vhdPath}"
        $error[0].Exception.Message
        return $False
    }

    if ($newVhdxSize -ne $vhdx.Size)
    {
        "Error: The VHDX size did not grow to new size of ${newVhdxSize}"
        return $False
    }

    #
    # Verify the guest sess the correct size
    #
    "Info : Check if the guest sees the new space"
    $diskSize = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "fdisk -l | grep Disk | grep /dev/sdb | cut -f 5 -d ' '"
    if (-not $?)
    {
        "Error: Unable to determine disk size from within the guest after growing the VHDX"
        return $False
    }

    if ($diskSize -ne $newVhdxSize)
    {
        "Error: VM ${vmName} sees a disk size of ${diskSize}, not the expected size of ${newSize}"
        return $False
    }

    #
    # Shrink the VHDX file
    # Note - we are shrinking the VHDX to 1GB.  This assumes the setup script
    #        continues to create the VHDX with an initial size of 1GB.
    #
    "Info : Shrink the VHDX to it's original size"
    Resize-VHD -Path $vhdPath -SizeBytes 1GB -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $?)
    {
       "Error: Unable to shrink VHDX file '${vhdPath}"
       $error[0].Exception.Message
       return $False 
    }

    #
    # Verify the VHDX file is the correct size
    #
    $vhdx = Get-VHD -Path $vhdPath -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $vhdx)
    {
        "Error: Unable to collect information on the VHDX file ${vhdPath}"
        $error[0].Exception.Message
        return $False
    }

    if ($vhdx.Size -gt $originalSize)
    {
        "Error: The VHDX was not shrunk back to the original size of ${originalSize}"
        "       current size = $($vhdx.Size)"
        return $False
    }

    #
    # Verify the guest sees the correct size
    #
    "Info : Check if the guest sees the original size"
    $diskSize = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "fdisk -l | grep Disk | grep /dev/sdb | cut -f 5 -d ' '"
    if (-not $?)
    {
        "Error: Unable to determine disk size from within the guest after shrinking the VHDX"
        return $False
    }

    if ($diskSize -ne $originalSize -and $diskSize -ne ($originalSize + 1MB))
    {
        "Error: VM incorrect size if ${diskSize} after shrinking volume.  Expected size is ${originalSize}"
        return $False
    }

    "Info : Iteration ${i} passed"
}

#
# If we made it here, all the checks passed.
#
return $True
