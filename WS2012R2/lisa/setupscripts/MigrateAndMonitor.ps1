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
    Performs basic Live/Quick Migration operations
.Description
    This is a Pwershell test case script that implements Live/Quick Migration
    of a VM.
    Keeps pinging the VM while migration is in progress, ensures that migration
    of VM is successful and the that the ping should not loose

    A typical test case definition for this test script would look similar to
    the following:

.Parameter vmName
    Name of the VM to migrate.
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
.Parameter testParams
    Test data for this test case
.Example

.Link
    None.
#>

param( [String] $vmName,
       [String] $hvServer,
       [String] $testParams
)

########################################################################
#
# Main entry point for script
#
########################################################################

if (-not $vmName -or $vmName.Length -eq 0)
{
    "Error: No vmName was specified"
    Return $False   
}

if (-not $hvServer)
{
    "Error: No hvServer was specified"
    Return $False
}

if (-not $testParams)
{
    "Error: No test parameters specified"
    Return $False
}

#
# Debug - display the test parameters so they are captured in the log file
#
Write-Output "TestParams : '${testParams}'"

$migrationType  = $null
$TC_COVERED     = $null
$ipv4           = $null

$params = $testParams.TrimEnd(";").Split(";")
foreach ($param in $params)
{
    $fields = $param.Split("=")

    switch ($fields[0].Trim())
    {
        "MigType"       { $migrationType    = $fields[1].Trim() }
        "ipv4"          { $ipv4             = $fields[1].Trim() }
        "TC_COVERED"    { $TC_COVERED       = $fields[1].Trim() }
        default         {} #unknown param - just ignore it
    }
}

echo "Covers : ${TC_COVERED}" >> $summaryLog

#
# Create a ping object
#
[System.Reflection.Assembly]::LoadWithPartialName("system.net.networkinformation")
$ping = New-Object System.Net.NetworkInformation.Ping
if (-not $ping)
{
    "Error: Unable to create a ping object"
}

#
# Initialize counters
#
$pingCount = 0
$goodPings = 0
$badPings = 0
$firstPing = $False
$lastPing = $False

"Info: Trying to ping the VM before starting migration"
$pingCount += 1
$pingReply = $ping.Send($ipv4)
if ($pingReply.Status -ne "Success")
{
    "Error: Cannont ping VM prior to migration. Status = $($pingReply.Status)"
    return $False
}
$firstPing = $true
$goodPings += 1

#
# Start the VM migration, and make sure it is running
#
"Info: Starting migration job"
$job = Start-Job -FilePath setupScripts\MigrateVM.ps1 -ArgumentList $vmName, $hvServer, $migrationType

if (-not $job)
{
    "Error: Migration job not started"
    return $False
}

"Info: Checking if the migration job is actually running"
$jobInfo = Get-Job -Id $job.Id
if($jobInfo.State -ne "Running")
{
    "Error: Migration job did not start or terminated immediately"
}

"Info: Pinging VM during the migration"
$migrateJobRunning = $true
while ($migrateJobRunning)
{
    $pingReply = $ping.Send($ipv4)
    if ($pingReply.Status -eq "Success")
    {
        $goodPings += 1
        $lastPing = $true
    }
    else
    {
        $badPings += 1
        $lastPing = $False
    }
    $pingCount += 1

    $jobInfo = Get-Job -Id $job.Id
    if($jobInfo.State -ne "Completed")
    {
        $migrateJobRunning = $False
        continue
    }
}

"Info: Pinging VM after migration"
$pingReply = $ping.Send($ipv4)
if ($pingReply.Status -eq "Success")
{
    $goodPings += 1
    $lastPing = $true
}
else
{
    $badPings += 1
    $lastPing = $False
}
$pingCount += 1

#
# Receiving the migration job's output
#
$jobInfo = Receive-Job -Id $job.Id
Remove-Job -Id $job.Id

#
# Display migrate job output
#
"Info: $vmName - Migrate job output"
foreach ($data in $jobInfo)
{
    "    $data"
}

"Total pings : $pingCount"
"Good pings  : $goodPings"

"Total pings : $pingCount"
"Bad pings  : $badPings"

#
# Adding pun stats to summary
#
echo "Good pings = $goodPings" >> ${vmName}_summary.log
echo "Bad pings  = $badPings"  >> ${vmName}_summary.log

#
# Checking if migration reports success and the last ping is successful
#
$retVal = ($jobInfo[$jobInfo.Length-1] -eq $True) -and ($lastPing)

return $retVal

