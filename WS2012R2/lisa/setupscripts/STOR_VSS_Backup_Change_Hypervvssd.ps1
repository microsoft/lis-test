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
    This script will stop hypervvssd daemons then do offline backup, then start hypervvssd again to do online backup.

    A typical XML definition for this test case would look similar
    to the following:

    <test>
        <testName>STOR_VSS_Backup_Change_Hypervvssd</testName>
        <setupScript>setupscripts\RevertSnapshot.ps1</setupScript>
        <files>remote-scripts/ica/utils.sh</files>
        <testScript>setupscripts\STOR_VSS_Backup_Change_Hypervvssd.ps1</testScript>

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

    .\setupscripts\STOR_VSS_Backup_Change_Hypervvssd.ps1 -hvServer localhost -vmName vm_name -testParams 'driveletter=D:;RootDir=path/to/testdir;sshKey=sshKey;ipv4=ipaddress'

#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$remoteScript = "STOR_VSS_Set_VSS_Daemon.sh"
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
    "TestLogDir" { $TestLogDir = $fields[1].Trim() }
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

# Change the working directory to where we need to be
cd $rootDir
# Source TCUtils.ps1 for common functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
	. .\setupScripts\TCUtils.ps1
	"Info: Sourced TCUtils.ps1"
}
else {
	"Error: Could not find setupScripts\TCUtils.ps1"
	return $false
}

$loggerManager = [LoggerManager]::GetLoggerManager($vmName, $testParams)
$global:logger = $loggerManager.TestCase

$logger.info("This script covers test case: ${TC_COVERED}")

# Source STOR_VSS_Utils.ps1 for common VSS functions
if (Test-Path ".\setupScripts\STOR_VSS_Utils.ps1") {
	. .\setupScripts\STOR_VSS_Utils.ps1
	$logger.info("Sourced STOR_VSS_Utils.ps1")
}
else {
	$logger.error("Could not find setupScripts\STOR_VSS_Utils.ps1")
	return $false
}

# run set up
$sts = runSetup $vmName $hvServer
if (-not $sts[-1])
{
    return $False
}

$driveletter = $global:driveletter

if ($null -eq $driveletter)
{
    "ERROR: Backup driveletter is not specified."
    return $False
}

# set the backup type array, if stop hypervvssd, it executes offline backup, if start hypervvssd, it executes online backup
$backupTypes = @("offline","online")

# set hypervvssd status, firstly stop, then start
$setAction= @("stop","start")

for ($i = 0; $i -le 1; $i++ )
{
    $serviceAction = $setAction[$i]
    $sts = SendCommandToVM $ipv4 $sshkey "echo serviceAction=$serviceAction  >> /root/constants.sh"
    if (-not $sts[-1]){
        $logger.error("Could not echo serviceAction to vm's constants.sh.")
        return $False
    }
    $logger.info("$serviceAction hyperv backup service")

     # Run the remote script
    $sts = RunRemoteScript $remoteScript
    if (-not $sts[-1])
    {
        $logger.error("Running $remoteScript script failed on VM!")
        return $False
    }

    Start-Sleep -s 3
    $stsBackUp = startBackup $vmName $driveLetter

    # when stop hypervvssd, backup offline backup
    if ( -not $stsBackUp[-1])
    {
        return $False
    }
    else
    {
        $backupLocation = $stsBackUp
        # if stop hypervvssd, vm does offline backup
        $bkType = getBackupType
        $temp = $backupTypes[$i]
        if  ( $bkType -ne $temp )
        {
            $logger.error("Failed: Not get expected backup type as $temp")
            return $False
        }
        else
        {
             $logger.info("Got expected backup type $temp")
        }
        runCleanup $backupLocation
    }
}

$logger.info("Test successful")
return $True
