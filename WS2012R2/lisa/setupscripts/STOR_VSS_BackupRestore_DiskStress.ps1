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
    This script will push VSS_Disk_Stress.sh script to the vm. 
    While the script is running it will perform the backup/restore operation. 
    
    It uses a second partition as target. 

    Note: The script has to be run on the host. A second partition
    different from the Hyper-V one has to be available. 

    A typical xml entry looks like this:

    <test>
    <testName>VSS_BackupRestore_DiskStress</testName>
        <testScript>setupscripts\VSS_BackupRestore_DiskStress.ps1</testScript> 
        <testParams>
            <param>driveletter=F:</param>
            <param>iOzoneVers=3_424</param>
            <param>TC_COVERED=VSS-14</param>
        </testParams>
        <timeout>1200</timeout>
        <OnERROR>Continue</OnERROR>
    </test>
    
    The iOzoneVers param is needed for the download of the correct iOzone version. 

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

$retVal = $false
$remoteScript = "STOR_VSS_Disk_Stress.sh"

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
        "iOzoneVers" { $iOzoneVers = $fields[1].Trim() }
        "TestLogDir" { $TestLogDir = $fields[1].Trim() }
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

if ($null -eq $iOzoneVers)
{
    Write-Output "ERROR: Test parameter iOzoneVers was not specified"
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

restore $vmName $hvServer $backupLocation

$sts = restoreBackup $backupLocation
if (-not $sts[-1])
{
    return $False
}

$sts = checkResults $vmName $hvServer
if (-not $sts[-1]) 
{
    $retVal = $False
} 
else 
{
	$retVal = $True
    $results = $sts
}

runCleanup $backupLocation

Write-Output "INFO: Test ${results}"
return $retVal