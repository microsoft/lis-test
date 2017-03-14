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
    This script will push test if VSS backup will gracefully fail in case
    of failure. 
    
    It uses a second partition as target. 

    Note: The script has to be run on the host. A second partition
    different from the Hyper-V one has to be available. 

    A typical xml entry looks like this:

    <test>
    <testName>VSS_BackupRestore_Fail</testName>
        <setupScript>setupscripts\AddHardDisk.ps1</setupScript>
        <testScript>setupscripts\VSS_BackupRestore_Fail.ps1</testScript> 
        <testParams>
            <param>driveletter=F:</param>
            <param>SCSI=0,1,Dynamic</param>
            <param>IDE=0,1,Dynamic</param>
            <param>FILESYS-ext3</param>
            <param>TC_COVERED=VSS-18</param>
        </testParams>
        <cleanupScript>setupscripts\RemoveHardDisk.ps1</cleanupScript>
        <timeout>1200</timeout>
        <OnERROR>Continue</OnERROR>
    </test>
    
.Parameter vmName
    Name of the VM to backup/restore.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\VSS_BackuRestore_DiskStress.ps1 -hvServer localhost -vmName NameOfVm -testParams 'sshKey=path/to/ssh;rootdir=path/to/testdir;ipv4=ipaddress;driveletter=D:;iOzoneVers=3_424'

#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$remoteScript = "STOR_VSS_Disk_Fail.sh"
$retVal = $false

####################################################################### 
# 
# Main script body 
# 
#######################################################################

# Check input arguments
if ($vmName -eq $null)
{
    Write-Output "ERROR: VM name is null"
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
        "TestLogDir" { $TestLogDir = $fields[1].Trim() }
        "FILESYS" { $FILESYS = $fields[1].Trim() }
        default  {}
        }
}

if ($null -eq $sshKey)
{
    Write-Output "ERROR: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4)
{
    Write-Output "ERROR: Test parameter ipv4 was not specified"
    return $False
}

if ($null -eq $rootdir)
{
    Write-Output "ERROR: Test parameter rootdir was not specified"
    return $False
}

if ($null -eq $driveletter)
{
    Write-Output "ERROR: Test parameter driveletter was not specified."
    return $False
}

if ($null -eq $FILESYS)
{
    Write-Output "ERROR: Test parameter FILESYS was not specified."
    return $False
}

if ($null -eq $TestLogDir)
{
    $TestLogDir = $rootdir
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



$sts = runSetup $vmName $hvServer $driveletter
if (-not $sts[-1]) 
{
    return $False
}

# Run the remote script
$sts = RunRemoteScript $remoteScript
if (-not $sts[-1])
{
    Write-Output "ERROR executing $remoteScript on VM. Exiting test case!" >> $summaryLog
    Write-Output "ERROR: Running $remoteScript script failed on VM!"
    return $False
}
Write-Output "$remoteScript execution on VM: Success"
Write-Output "$remoteScript execution on VM: Success" >> $summaryLog


$sts = startBackup $vmName $driveletter
if (-not $sts[-1])
{
    return $False
}
else 
{
    $backupLocation = $sts
}

Write-Output "INFO: Going through event logs for Warninig ID 10107"
# Now Check if Warning related Error is present in Event Log ? Backup should fail .
$EventLog = Get-WinEvent -ProviderName Microsoft-Windows-Hyper-V-VMMS | where-object {  $_.TimeCreated -gt $Date}
if(-not $EventLog)
{
    "ERROR: Cannot get Event log."
    $retVal = $False
} 

# Event ID 10107 is what we looking here, it will be always be 10107.
foreach ($event in $EventLog)
   {
       Write-Output "VSS Backup Error in Event Log number is $($event.ID):" 
       if ($event.Id -eq 10150)
       {
           $results = "Passed"
           $retVal = $True
           Write-Output "INFO: " + $event.Message
           Write-Output "INFO: VSS Backup Error in Event Log : Success"
           Write-Output "VSS Backup Error in Event Log : Success" >> $summaryLog
       }
   }

if ($retVal -eq $false)
{
     Write-Output "ERROR: VSS Backup Error not in Event Log"
     Write-Output "ERROR: VSS Backup Error not in Event Log" >> $summaryLog
}

runCleanup $backupLocation

Write-Output "INFO: Test ${results}"
return $retVal