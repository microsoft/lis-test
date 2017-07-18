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
    This script tests VSS backup functionality.

.Description
    This script will stop hypervvssd daemons then do backup. For older hyperv-daemons version, it will get backup error, for latest version, it will do offline backup.

    A typical XML definition for this test case would look similar
    to the following:

    <test>
        <testName>STOR_VSS_Backup_Stop_VSSD</testName>
        <setupScript>setupscripts\RevertSnapshot.ps1</setupScript>
        <testScript>setupscripts\STOR_VSS_Backup_Stop_VSSD.ps1</testScript>
        <testParams>
            <param>TC_COVERED=VSS-22</param>
        </testParams>
        <timeout>2400</timeout>
        <OnError>Continue</OnError>
    </test>

.Parameter vmName
    Name of the VM to backup

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example

    .\setupscripts\STOR_VSS_Backup_Stop_VSSD.ps1 -hvServer localhost -vmName vm_name -testParams 'driveletter=D:;RootDir=path/to/testdir;sshKey=sshKey;ipv4=ipaddress'

#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

#######################################################################
#
# Main script body
#
#######################################################################

# Check input arguments
if ($vmName -eq $null)
{
    "ERROR: VM name is null"
    return $False
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

if ($null -eq $sshKey)
{
    "ERROR: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4)
{
    "ERROR: Test parameter ipv4 was not specified"
    return $False
}

if ($null -eq $rootdir)
{
    "ERROR: Test parameter rootdir was not specified"
    return $False
}

if ($null -eq $driveletter)
{
    "ERROR: Backup driveletter is not specified."
    return $False
}

# Change the working directory to where we need to be
cd $rootDir

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Source TCUtils.ps1 for common functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
	. .\setupScripts\TCUtils.ps1
	"Info: Sourced TCUtils.ps1"
}
else {
	"Error: Could not find setupScripts\TCUtils.ps1"
	return $false
}

# Source STOR_VSS_Utils.ps1 for common VSS functions
if (Test-Path ".\setupScripts\STOR_VSS_Utils.ps1") {
	. .\setupScripts\STOR_VSS_Utils.ps1
	"Info: Sourced STOR_VSS_Utils.ps1"
}
else {
	"Error: Could not find setupScripts\STOR_VSS_Utils.ps1"
	return $false
}
## run set up
$sts = runSetup $vmName $hvServer $driveletter
if (-not $sts[-1])
{
    return $False
}

# Stop hypervvssd daemons
$retVal = SendCommandToVM $ipv4 $sshKey "service hypervvssd stop"
if ($retVal -eq $False)
{
    "Error: Failed to stop the hypervvssd server!"
    return $false
}
Start-Sleep -s 1
# After stop hypervvssd,if hyperv-daemons version is smaller than 0.0.30,it gets error when do backup, otherwise it executes offline backup.
$supportHypervDaemons = "hyperv-daemons-0-0.30.20171211git.el7"
$supportStatus = GetHypervDaemonsSupportStatus $ipv4 $sshKey $supportHypervDaemons

$stsBackUp = startBackup $vmName $driveLetter

if ( -not $supportStatus)
{   # when stop hypervvssd, backup gets failure
    if ( $stsBackUp[-1])
     {
         "ERROR: Backup still could complete even not support" >> $summaryLog
         return $False
     }
     else
     {
         "Info: Get failed backup as expected when hypervvssd stopped" >> $summaryLog
     }
}
else
{  # execute offline backup when stop hyperv-vssd
    if (-not $stsBackUp[-1])
    {
        "Failed: Failed to do offline backup"
        return $False
    }
    else
    {
        $backupLocation = $stsBackUp
        # if stop hypervvssd, vm does offline backup
        $bkType = getBackupType
        if  ( $bkType -ne "offline" )
        {
            "Failed: Not get expected offline backup type"  >> $summaryLog
            return $False
        }
        else
        {
            "Info: Get expected offline backup type" >> $summaryLog
        }
        runCleanup $backupLocation
    }
}

"Info: Test successful"
return $True
