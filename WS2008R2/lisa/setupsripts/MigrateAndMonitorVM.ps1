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
    

.Description
    

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)


#
# Check input arguments
#
if (-not $vmName -or $vmName.Length -eq 0)
{
    "Error: vmName is null"
    return $False
}

if (-not $hvServer -or $hvServer.Length -eq 0)
{
    "Error: hvServer is null"
    return $False
}

if (-not $testParams -or $testParams.Length -lt 3)
{
    "Error: testParams is null or invalid"
    return $False
}

$ipv4 = $null
$rootdir = $null
$tc = $null
#
# Parse the testParams string
#
$params = $testParams.Split(';')
foreach ($p in $params)
{
    if ($p.Trim().Length -eq 0)
    {
        continue
    }

    $fields = $p.Trim().Split('=')
    
    if ($fields.Length -ne 2)
    {
	    #"Warn : test parameter '$p' is being ignored because it appears to be malformed"
        continue
    }
    
    if ($fields[0].Trim() -eq "IPV4")
    {
        $ipv4 = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "RootDir")
    {
        $rootdir = $fields[1].Trim()
    }
     if ($fields[0].Trim() -eq "TC_COVERED")
    {
        $tc = $fields[1].Trim()
    }
}


$sts = get-module | select-string -pattern FailoverClusters -quiet
if (! $sts)
{
    Import-module FailoverClusters
}

#
# change the working directory to root dir
#

cd $rootdir

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers ${tc}" | Out-File -Append $summaryLog


#
# Create a ping object.  We do this to simplify checking
# if the ping was successful
#
[System.Reflection.Assembly]::LoadWithPartialName("system.net.networkinformation")
$ping = new-object System.Net.NetworkInformation.Ping
if (-not $ping)
{
    "Error: $vmName - Unable to create a ping object"
    return $False
}

#
# Initialize our counters
#
$pingCount = 0
$goodPings = 0
$firstPing = $False
$lastPing  = $False

#
# Make sure we can Ping the VM before starting the migration
#
$pingCount += 1
$pingReply = $ping.send($ipv4)
if ($pingReply.Status -ne "Success")
{
    Write-Output "Error: Cannot ping VM prior to migration.  Status = $($pingReply.Status)" | Out-File -Append $summaryLog
    return $False
}
$firstPing = $True
$goodPings += 1

#
# Start the VM migration, and make sure it is running
#
$job = Start-Job -file setupScripts\MigrateVM.ps1 -argumentList $vmName, $hvServer, $testParams

if (-not $job)
{
    Write-Output "Error: Migration job not started" | Out-File -Append $summaryLog
    return $False
}

#
# Make sure the job is actually running
$jobInfo = Get-Job -ID $job.id
if ($jobInfo.State -ne "Running")
{
    Write-Output "Error: $vmName - Migration job did not start or terminated immediately" | Out-File -Append $summaryLog
}
else
{
    #
    # Ping the VM during the migration.  Keep some
    # ping statistics.  Terminate the loop when
    # the migration completes.
    #
    $migrateJobRunning = $True
    while ( $migrateJobRunning )
    {
        $pingReply = $ping.send($ipv4)
        if ($pingReply.Status -eq "Success")
        {
            $goodPings += 1
            $lastPing = $True
        }
        else
        {
            $lastPing = $False
        }
        $pingCount += 1

        #
        # Get info on the migration job
        #
        $jobInfo = Get-Job -ID $job.id
        if ($jobInfo.state -eq "Completed")
        {
            $migrateJobRunning = $False
            continue
        }

        #
        # take a short nap while the migration is being performed
        #
        Start-Sleep -s 2
    }
}

Start-Sleep -s 30

$pingReply = $ping.send($ipv4)
if ($pingReply.Status -eq "Success")
{
    $goodPings += 1
    $lastPing = $True
}
else
{
    $lastPing = $False
}
$pingCount += 1
        
#
# Receive the migration job's output
#
$jobInfo = Receive-Job -ID $job.id
Remove-Job -ID $job.id

#
# Display the migrate job output
#
"Info : $vmName - Migrate job output"
foreach ($data in $jobInfo)
{
    "    $data"
}

"Total pings : $pingCount"
"Good pings  : $goodPings"

$badPings = $pingCount - $goodPings

"Bad pings   : $badPings"
"First ping  : $firstPing"
"Last ping   : $lastPing"

#
# Add ping stats to summary
#
Write-Output "Good pings = $goodPings" | Out-File -Append $summaryLog
Write-Output "Bad pings  = $badPings"  | Out-File -Append $summaryLog

#
# Currently, we consider a successful migration if the migration
# reports success, and the last ping was successful.
#
$retVal = ($jobInfo[$jobInfo.Length-1] -eq $True) -and ($lastPing)

return $retVal
