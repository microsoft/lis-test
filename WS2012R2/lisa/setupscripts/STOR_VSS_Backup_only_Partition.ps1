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
    This script will format and mount connected disk in the VM.
    After that it will proceed with backup/restore operation.

    It uses a second partition as target.

    Note: The script has to be run on the host. A second partition
    different from the Hyper-V one has to be available.

    A typical xml entry looks like this:

    <test>
        <testName>VSS_BackupRestore_ext4_vhdx</testName>
        <setupScript>setupscripts\AddVhdxHardDisk.ps1</setupScript>
        <testScript>setupscripts\VSS_BackupRestore_Partition.ps1</testScript>
        <testParams>
            <param>driveletter=F:</param>
            <param>SCSI=0,1,Dynamic</param>
            <param>IDE=0,1,Dynamic</param>
            <param>FILESYS=ext4</param>
            <param>TC_COVERED=VSS-02</param>
        </testParams>
        <cleanupScript>setupscripts\RemoveVhdxHardDisk.ps1</cleanupScript>
        <timeout>1200</timeout>
        <OnError>Continue</OnError>
    </test>

.Parameter vmName
    Name of the VM to remove disk from .

.Parameter hvServer
    Name of the VM to backup/restore.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\VSS_BackuRestore_Partition.ps1 -hvServer localhost -vmName NameOfVm -testParams 'sshKey=path/to/ssh;rootdir=path/to/testdir;ipv4=ipaddress;driveletter=D:;FILESYS=ext4'

#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false
$remoteScript = "PartitionMultipleDisks.sh"

#######################################################################
#
# Main script body
#
#######################################################################

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
        "fileSystems" { $fileSystems = $fields[1].Trim() }
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

if ($null -eq $fileSystems)
{
    "ERROR: Test parameter fileSystems was not specified"
    return $False
}

# Change the working directory to where we need to be
cd $rootDir

# Source TCUtils.ps1 for common functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
	. .\setupScripts\TCUtils.ps1
	"Info: Sourced TCUtils.ps1 in STOR_VSS_BackupRestore_Partition.ps1"
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

# Run the remote script
$sts = RunRemoteScript $remoteScript
if (-not $sts[-1])
{
    $logger.error("Running $remoteScript script failed on VM!")
    return $False
}

$logfilename = ".\$remoteScript.log"
$logger.info("Here are the remote logs:")
$logger.info($(Get-Content $logfilename))
del $remoteScript.log

$sts = startBackup $vmName $driveletter
if (-not $sts[-1])
{
	return $False
} else {
	$backupLocation = $sts
}

$retVal = $True
$results = $sts

runCleanup $backupLocation

$logger.info("Test ${results}")
return $retVal
