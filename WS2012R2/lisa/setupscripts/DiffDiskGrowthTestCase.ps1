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
    This test script, which runs inside VM it mount the dirve and perform write operation on diff disk. And checks sure parent disk size does not change.

.Description
    ControllerType=Controller Index, Lun or Port, vhd type

   Where
      ControllerType   = The type of disk controller.  IDE or SCSI
      Controller Index = The index of the controller, 0 based.
                         Note: IDE can be 0 - 1, SCSI can be 0 - 3
      Lun or Port      = The IDE port number of SCSI Lun number
      Vhd Type         = Type of VHD to use.
                         Valid VHD types are:
                             Dynamic
                             Fixed
                             Diff (Differencing)
   The following are some examples

   SCSI=0,0,Diff : Add a hard drive on SCSI controller 0, Lun 0, vhd type of Dynamic
   IDE=1,1,Diff  : Add a hard drive on IDE controller 1, IDE port 1, vhd type of Diff
   
   Note: This setup script only adds differencing disks.

    A typical XML definition for this test case would look similar
    to the following:
     <test>
        <testName>VHDx_AddDifferencing_Disk_IDE</testName>
        <testScript>setupscripts\DiffDiskGrowthTestCase.ps1</testScript>
        <setupScript>setupscripts\DiffDiskGrowthSetup.ps1</setupScript>
        <cleanupScript>setupscripts\DiffDiskGrowthCleanup.ps1</cleanupScript>
        <timeout>18000</timeout>
        <testparams>                
                <param>IDE=1,1,Diff</param>      
                <param>ParentVhd=VHDXParentDiff.vhdx</param>
                <param>TC_COUNT=DSK_VHDX-75</param>            
        </testparams>
    </test>

.Parameter vmName
    Name of the VM to read intrinsic data from.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\STOR_DiffDiskGrowthTestCase.ps1 -vmName sles11sp3x64 -hvServer localhost -testParams "IDE=1,1,Diff;ParentVhd=VHDXParentDiff.vhdx;sshkey=rhel5_id_rsa.ppk;ipv4=10.200.50.192;RootDir=" 

.Link
    None.
#>



param ([String] $vmName, [String] $hvServer, [String] $testParams)


#######################################################################
#
# GetRemoteFileInfo()
#
# Description:
#     Use WMI to retrieve file information for a file residing on the
#     Hyper-V server.
#
# Return:
#     A FileInfo structure if the file exists, null otherwise.
#
#######################################################################
function GetRemoteFileInfo([String] $filename, [String] $server )
{
    $fileInfo = $null
    
    if (-not $filename)
    {
        return $null
    }
    
    if (-not $server)
    {
        return $null
    }
    
    $remoteFilename = $filename.Replace("\", "\\")
    $fileInfo = Get-WmiObject -query "SELECT * FROM CIM_DataFile WHERE Name='${remoteFilename}'" -computer $server
    
    return $fileInfo
}


############################################################################
#
# Main script body
#
############################################################################

$retVal = $False

#
# Display a little info about our environment
#
"STOR_DiffDiskGrowthTestCase.ps1"
"  vmName = ${vmName}"
"  hvServer = ${hvServer}"
"  testParams = ${testParams}"

#
# Make sure we have access to the Microsoft Hyper-V snapin
#
$hvModule = Get-Module Hyper-V
if ($hvModule -eq $NULL)
{
    import-module Hyper-V
    $hvModule = Get-Module Hyper-V
}

if ($hvModule.companyName -ne "Microsoft Corporation")
{
    "Error: The Microsoft Hyper-V PowerShell module is not available"
    return $Falses
}

$controllerType = $null
$controllerID = $null
$lun = $null
$vhdType = $null
$vhdName = $null
$parentVhd = $null
$sshKey = $null
$ipv4 = $null

#
# Parse the testParams string and make sure all
# required test parameters have been specified.
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
        Continue
    }
    
    $lValue = $tokens[0].Trim()
    $rValue = $tokens[1].Trim()

    #
    # ParentVHD test param?
    #
    if ($lValue -eq "ParentVHD")
    {
        $parentVhd = $rValue
        continue
    }
    
    if (@("IDE", "SCSI") -contains $lValue)
    {
        $controllerType = $lValue
            
        $diskArgs = $rValue.Trim().Split(',')
        
        if ($diskArgs.Length -ne 3)
        {
            "Error: Incorrect number of arguments: $p"
            $retVal = $false
            Continue
        }
        
        $controllerID = $diskArgs[0].Trim()
        $lun = $diskArgs[1].Trim()
        $vhdType = $diskArgs[2].Trim()
        Continue
    }
    
    if ($lValue -eq "MountPoint")
    {
        $mountPoint = $rValue
        Continue
    }
    
    if ($lValue -eq "sshKey")
    {
        $sshKey = $rValue
        Continue  
    }
    
    if ($lValue -eq "ipv4")
    {
        $ipv4 = $rValue
        Continue
    }
    if ($lValue -eq "rootdir")
    {
        $rootdir = $rValue
        Continue
    }
}

cd $rootdir

#
# Make sure we have all the data we need to do our job
#
if (-not $controllerType)
{
    "Error: Missing controller type in test parameters"
    return $False
}

if (-not $controllerID)
{
    "Error: Missing controller index in test parameters"
    return $False
}

if (-not $lun)
{
    "Error: Missing lun in test parameters"
    return $False
}

if (-not $vhdType)
{
    "Error: Missing vhdType in test parameters"
    return $False
}

if (-not $sshKey)
{
    "Error: Missing sshKey in test parameters"
    return $False
}

if (-not $mountPoint)
{
    "Warn : Missing mountPoint test parameter. Defaulting to /mnt"
    $mountPoint = "/mnt"
}

if (-not $sshKey)
{
    "Error: Missing sshKey test parameter"
    return $False
}

if (-not $ipv4)
{
    "Error: Missing ipv4 test parameter"
    return $False
}

$hostInfo = Get-VMHost -ComputerName $hvServer
if (-not $hostInfo)
{
    "Error: Unable to collect Hyper-V settings for ${hvServer}"
    return $False
}

$defaultVhdPath = $hostInfo.VirtualHardDiskPath
if (-not $defaultVhdPath.EndsWith("\"))
{
    $defaultVhdPath += "\"
}

if ($parentVhd.EndsWith(".vhd"))
{
    $vhdName = $defaultVhdPath + ${vmName} +"-" + ${controllerType} + "-" + ${controllerID}+ "-" + ${lun} + "-" + "Diff.vhd"  
}
else
{
    $vhdName = $defaultVhdPath + ${vmName} +"-" + ${controllerType} + "-" + ${controllerID}+ "-" + ${lun} + "-" + "Diff.vhdx"  
} 

#
# The .vhd file should have been created by our
# setup script. Make sure the .vhd file exists.
#
$vhdFileInfo = GetRemoteFileInfo $vhdName $hvServer
if (-not $vhdFileInfo)
{
    "Error: VHD file does not exist: ${vhdFilename}"
    return $False
}

$vhdInitialSize = $vhdFileInfo.FileSize

#
# Make sure the .vhd file is a differencing disk
#
$vhdInfo = Get-VHD -path $vhdName -ComputerName $hvServer
if (-not $vhdInfo)
{
    "Error: Unable to retrieve VHD information on VHD file: ${vhdFilename}"
    return $False
}

if ($vhdInfo.VhdType -ne "Differencing")
{
    "Error: VHD `"${vhdName}`" is not a Differencing disk"
    return $False
}

#
# Collect info on the parent VHD
#
$parentVhdFilename = $vhdInfo.ParentPath

$parentFileInfo = GetRemoteFileInfo $parentVhdFilename $hvServer
if (-not $parentFileInfo)
{
    "Error: Unable to collect file information on parent VHD `"${parentVhd}`""
    return $False
}

$parentInitialSize = $parentFileInfo.FileSize

#
# Tell the guest OS on the VM to mount the differencing disk
#

$sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "mount /dev/sdb1 /mnt" | out-null
if (-not $?)
{
    "Error: Unable to send mount request to VM"
    return $False
}

$sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "mkdir -p /mnt/ica" | out-null
if (-not $?)
{
    "Error: Unable to send mkdir request to VM"
    return $False
}

#
# Tell the guest OS to write a few MB to the differencing disk
#
$sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dd if=/dev/sda1 of=/mnt/ica/test.dat count=2048 > /dev/null 2>&1" | out-null 
if (-not $?)
{
    "Error: Unable to send cp command to VM to grow the .vhd"
    return $False
}

#
# Tell the guest OS on the VM to unmount the differencing disk
# 
$sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "umount /mnt" | out-null 
if (-not $?)
{
    "Warn : Unable to send umount request to VM"
    return $False
}

#
# Save the current size of the parent VHD and differencing disk
#
$parentInfo = GetRemoteFileInfo $parentVhdFilename $hvServer
$parentFinalSize = $parentInfo.fileSize

$vhdInfo = GetRemoteFileInfo $vhdFilename $hvServer
$vhdFinalSize = $vhdInfo.FileSize

#
# Make sure the parent matches its initial size
#
if ($parentFinalSize -eq $parentInitialSize)
{
    #
    # The parent VHD was not written to
    #
    "Info : The parent .vhd file did not change in size"
    $retVal = $true
}

if ($vhdFinalSize -gt $vhdInitialSize)
{
    "Info : The differencing disk grew in size from ${vhdInitialSize} to ${vhdFinalSize}"
}

return $retVal
