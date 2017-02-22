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
	Creates a quick snapshot, to not revert to the default ICABase snapshot.

.Description
    Modified version of STOR_TakeRevert_Snapshot.ps1 to only create a snapshot.
    This is usefull if the default snapshot represents a clean state,
    then a temporary additional snapshot is needed before further changes.

    A typical test case definition for this test script would look
    similar to the following:
             <test>
            <testName>PreVSS_TakeSnapshot</testName>
            <testScript>setupScripts\PreVSS_TakeSnapshot.ps1</testScript>
            <timeout>1500</timeout>
            <onError>Continue</onError>
            <noReboot>False</noReboot>
        </test>

.Parameter vmName
    Name of the VM to perform the test with.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.

.Example
    setupScripts\PreVSS_TakeSnapshot.ps1 -vmName "myVm" -hvServer "localhost" -TestParams ""
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false
$rootDir = $null
$ipv4 = $null
$sshKey = $null

#
# Check input arguments
#
if (-not $vmName)
{
    "Error: VM name is null."
    return $retVal
}

if (-not $hvServer)
{
    "Error: hvServer is null."
    return $retVal
}

if (-not $testParams)
{
    "Error: No testParams provided!"
    "This script requires the test case ID and the logs folder as the test parameters."
    return $retVal
}

#
# Checking the mandatory testParams
#
$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
        switch ($fields[0].Trim())
        {
        "ipv4" { $ipv4 = $fields[1].Trim() }
        "rootdir" { $rootDir = $fields[1].Trim() }
        default  {}
        }
}

if (-not $rootDir)
{
    "Error: Missing testParam rootDir value"
}

if (-not $ipv4)
{
    "Error: Missing testParam ipv4 value"
    return $retVal
}

# Change the working directory for the log files
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $retVal
}
cd $rootDir

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue

#######################################################################
#
# Main script block
#
#######################################################################

# Source the TCUtils.ps1 file
. .\setupscripts\TCUtils.ps1

Write-Host "Waiting for VM $vmName to stop..."
if ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Off") {
    Stop-VM -ComputerName $hvServer -Name $vmName -Force -Confirm:$false
}

#
# Waiting until the VM is off
#
if (-not (WaitForVmToStop $vmName $hvServer 300))
{
    Write-Output "Error: Unable to stop VM"
    return $False
}

#
# Take a snapshot then restore the VM to the snapshot
#
"Info: Taking Snapshot of VM $vmName"

Checkpoint-VM -Name $vmName -SnapshotName ICABase_Upstream -ComputerName $hvServer
if (-not $?)
{
    Write-Output "Error taking snapshot!" | Out-File -Append $summaryLog
    return $False
}

#
# Waiting for the VM to run again and respond to SSH - port 22
#
Start-VM $vmName -ComputerName $hvServer

$timeout = 300
while ($timeout -gt 0) {
    if ( (TestPort $ipv4) ) {
        break
    }

    Start-Sleep -seconds 2
    $timeout -= 2
}

if ($timeout -eq 0) {
    Write-Output "Error: Test case timed out waiting for VM to boot" | Out-File -Append $summaryLog
    return $False
}

$retVal = $True
Write-Output "Snapshot has been created." | Out-File -Append $summaryLog

return $retVal
