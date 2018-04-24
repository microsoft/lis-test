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
    This script creates a disk to be used for backup and restore tests
  .Description
    This script will create a new VHD double the size of the VHD in the
    given vm. The VHD will be mounted to a new partiton, initialized and
    formatted with NTFS

    Note: The script has to be run on the host.

  .Parameter vmName
    Name of the VM that will be tested and for which the VHD will be
    deleted
#>

param ([string]$vmName, [string] $hvServer, [string]$testParams)

$retVal = $False

#############################################################
#
# Main script body
#
#############################################################

# Check input arguments
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
    "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    "sshKey" { $sshKey = $fields[1].Trim() }
    "ipv4" { $ipv4 = $fields[1].Trim() }
    "rootdir" { $rootDir = $fields[1].Trim() }
    "driveletter" { $driveletter = $fields[1].Trim() }
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

$summaryLog = "${vmName}_summary.log"

# Source STOR_VSS_Utils.ps1 for common VSS functions
if (Test-Path ".\setupScripts\STOR_VSS_Utils.ps1") {
  . .\setupScripts\STOR_VSS_Utils.ps1
  Write-Output "Sourced STOR_VSS_Utils.ps1" | Tee-Object -Append -file $summaryLog
}
else {
  Write-Output "Could not find setupScripts\STOR_VSS_Utils.ps1" | Tee-Object -Append -file $summaryLog
    return $false
}

$backupdiskpath = (get-vmhost).VirtualHardDiskPath + "\" + $vmName + "_VSS_DISK.vhdx"
$tempFile = (get-vmhost).VirtualHardDiskPath + "\" + $vmName + "_DRIVE_LETTER.txt"

#This is used to set the $global:driveletter variable
$var = getDriveLetter $vmName $hvServer

if ($global:driveletter)
{
  Dismount-VHD -Path $backupDiskPath -ErrorAction SilentlyContinue
  if ($? -eq $False)
  {
    Write-Output "Dismounting VHD has failed"| Tee-Object -Append $summaryLog
  }

  Remove-Item $backupdiskpath -Force -ErrorAction SilentlyContinue
  if ($? -eq $False)
  {
    Write-Output "Could not remove backup disk"| Tee-Object -Append $summaryLog
  }

  Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
  if ($? -eq $False)
  {
    Write-Output "Could not remove temporary file"| Tee-Object -Append $summaryLog
  }

  Write-Output "Cleanup completed!" | Tee-Object -Append $summaryLog
  return $True
}
else
{
  Write-Output "Drive letter isn't set" | Tee-Object -Append -file $summaryLog
}

