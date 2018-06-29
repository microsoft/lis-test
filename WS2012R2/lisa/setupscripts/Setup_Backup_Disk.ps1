# ########################################################################
# #
# # Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# # Copyright (c) Microsoft Corporation
# #
# # All rights reserved.
# # Licensed under the Apache License, Version 2.0 (the ""License"");
# # you may not use this file except in compliance with the License.
# # You may obtain a copy of the License at
# #     http://www.apache.org/licenses/LICENSE-2.0
# #
# # THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# # OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# # ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# # PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
# #
# # See the Apache Version 2.0 License for specific language governing
# # permissions and limitations under the License.
# #
# ########################################################################
#
#
# <#
#   .Synopsis
#     This script creates a disk to be used for backup and restore tests
#   .Description
#     This scrip will create a new VHD double the size of the VHD in the
#     given vm. The VHD will be mounted to a new partiton, initialized and
#     formatted with NTFS
#
#     Note: The script has to be run on the host.
#
#   .Parameter vmName
#     Name of the VM that will be tested and for which the VHD will be
#     created
# #>
#
# param ([string]$vmName)
#
# $retVal = $False
#
# #############################################################
# #
# # Main script body
# #
# #############################################################
#

param ([string]$vmName, [string] $hvServer, [string]$testParams)

$retVal = $False
$summaryLog = "${vmName}_summary.log"

if ($vmName -eq $null)
{
    "ERROR: VM name is null"
    return $retVal
}

# Check input params
$params = $testParams.Split(";")

foreach ($p in $params)
{
  $fields = $p.Split("=")

  switch ($fields[0].Trim())
    {
    "rootdir" { $rootDir = $fields[1].Trim() }
     default  {}
    }
}

if ($null -eq $rootDir)
{
    "ERROR: Test parameter rootDir was not specified"
    return $False
}

# Change the working directory to where we need to be
cd $rootDir

# Source STOR_VSS_Utils.ps1 for common VSS functions
if (Test-Path ".\setupScripts\STOR_VSS_Utils.ps1") {
  . .\setupScripts\STOR_VSS_Utils.ps1
  Write-Output "Sourced STOR_VSS_Utils.ps1" | Tee-Object -Append -file $summaryLog
}
else {
  Write-Output "Could not find setupScripts\STOR_VSS_Utils.ps1" | Tee-Object -Append -file $summaryLog
    return $false
}

$backupdisksize = 2*$(Get-VMHardDiskDrive $vmName | get-vhd).size
$backupdiskpath = (get-vmhost).VirtualHardDiskPath + "\" + $vmName + "_VSS_DISK.vhdx"

$driveletter = ls function:[g-y]: -n | ?{ !(test-path $_) } | random

$originaldriveletter = $driveletter
[char]$driveletter = $driveletter.Replace(":","")

if ([string]::IsNullOrEmpty($driveletter)) {
    Write-Output "Setup: The driveletter variable is empty!" | Tee-Object -Append -file $summaryLog
    return $retVal
}

if (Test-Path ($backupdiskpath)) {
    Write-Output "Disk already exists. Deleting old disk and creating new disk." | Tee-Object -Append -file $summaryLog
    Dismount-VHD $backupdiskpath
    Remove-Item $backupdiskpath
    New-VHD -Path $backupdiskpath -Size $backupdisksize
} else {
    New-VHD -Path $backupdiskpath -Size $backupdisksize
}

# Try mounting VHD. If first time fails, try again once more.
Mount-VHD -Path $backupdiskpath
$mountedSuccessfully = $?
if(! $mountedSuccessfully)
{
    Dismount-VHD $backupdiskpath

    # Try mounting again
    Mount-VHD -Path $backupdiskpath
}

$backupdisk = Get-Vhd -path $backupdiskpath

Initialize-Disk $backupdisk.DiskNumber
$diskpartition = New-Partition -DriveLetter $driveletter -DiskNumber $backupdisk.DiskNumber -UseMaximumSize
$volume = Format-Volume -FileSystem NTFS -Confirm:$False -Force -Partition $diskpartition

New-PSDrive -Name $driveletter -PSProvider FileSystem -Root $originaldriveletter -Description "VSS"

$filePath = (get-vmhost).VirtualHardDiskPath + "\" + "$vmName" + "_DRIVE_LETTER.txt"

if(Test-Path ($filePath))
{
    Write-Output "Removing existing file." | Tee-Object -Append -file $summaryLog
    Remove-Item $filePath
}

Write-Output "$originaldriveletter" >> $filePath

return $?

