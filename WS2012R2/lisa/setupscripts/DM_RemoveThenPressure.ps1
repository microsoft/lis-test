#####################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
#####################################################################

<#
.Synopsis
 Verify that a VM's assigned memory could decrease when no pressure available. Then do stress test, assigned and demand memory
 could increase.
.DESCRIPTION
    Step 1: Verify that a VM's assigned memory could decrease when no pressure available.
    After VM sleeps less than 7 minutes, it is higher than minimum memory.
    Step2: Do stress-ng test, during stress test, assigned and demand memory increase
    Step3: After stress test, check that assigned and memory decrease again, no any crash in VM.

    Note: the startupMem shall be set as larger, e.g. same with maxMem.

    The testParams have the format of:
        vmName=Name of a VM, enable=[yes|no], minMem= (decimal) [MB|GB|%], maxMem=(decimal) [MB|GB|%],
    startupMem=(decimal) [MB|GB|%], memWeight=(0 < decimal < 100)

    The following is an example of a testParam for configuring Dynamic Memory
     "vmName=sles11x64sp3;enable=yes;minMem=512MB;maxMem=80%;startupMem=80%;memWeight=0;

   .Parameter vmName
    Name of the VM

    .Parameter hvServer
    Name of the Hyper-V server hosting the VM.

    .Parameter testParams
    Test data for this test case

    .Example
    setupscripts\DM_RemoveNoPressure.ps1 -vmName nameOfVM -hvServer localhost -testParams 'sshKey=KEY;ipv4=IPAddress;rootDir=path\to\dir;'
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)
Set-PSDebug -Strict

# we need a scriptblock in order to pass this function to start-job
$scriptBlock = {
  # function for starting stress-ng
function ConsumeMemory([String]$conIpv4, [String]$sshKey, [String]$rootDir){

  # because function is called as job, setup rootDir and source TCUtils again
    if (Test-Path $rootDir){
        Set-Location -Path $rootDir
        if (-not $?){
        "Error: Could not change directory to $rootDir !"
        return $false
        }
        "Changed working directory to $rootDir"
    }
    else{
    "Error: RootDir = $rootDir is not a valid path"
    return $false
    }

  # Source TCUitls.ps1 for getipv4 and other functions
    if (Test-Path ".\setupScripts\TCUtils.ps1") {
        . .\setupScripts\TCUtils.ps1
    "Sourced TCUtils.ps1"
    }
    else {
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
    }

      $cmdToVM = @"
#!/bin/bash
        __freeMem=`$(cat /proc/meminfo | grep -i MemFree | awk '{ print `$2 }')
        __freeMem=`$((__freeMem/1024))
        echo ConsumeMemory: Free Memory found `$__freeMem MB >> /root/HotAdd.log 2>&1
        __threads=32
        __chunks=`$((`$__freeMem / `$__threads))
        echo "Going to start `$__threads instance(s) of stress-ng every 2 seconds, each consuming `$__chunks MB memory" >> /root/HotAdd.log 2>&1
        stress-ng -m `$__threads --vm-bytes `${__chunks}M -t 120 --backoff 1500000
        echo "Waiting for jobs to finish" >> /root/HotAdd.log 2>&1
        wait
        exit 0
"@

    #"pingVMs: sendig command to vm: $cmdToVM"
    $filename = "ConsumeMem.sh"

    # check for file
    if (Test-Path ".\${filename}"){
        Remove-Item ".\${filename}"
    }

    Add-Content $filename "$cmdToVM"

    # send file
    $retVal = SendFileToVM $conIpv4 $sshKey $filename "/root/${$filename}"

    # check the return Value of SendFileToVM
    if (-not $retVal[-1]){
        return $false
    }

    # execute command as job
    $retVal = SendCommandToVM $conIpv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"

    return $retVal
  }
}

######################################################################
#
# Main script body
#
#######################################################################
#
# Check input arguments
#
if ($vmName -eq $null){
    "Error: VM name is null"
    return $False
}

if ($hvServer -eq $null){
    "Error: hvServer is null"
    return $False
}

if ($testParams -eq $null){
    "Error: testParams is null"
    return $False
}

$params = $testParams.Split(";")
foreach ($p in $params){
    $fields = $p.Split("=")

    switch ($fields[0].Trim()){
        "ipv4"    { $ipv4    = $fields[1].Trim() }
        "sshKey"  { $sshKey  = $fields[1].Trim() }
        "appGitURL"  { $appGitURL  = $fields[1].Trim() }
        "appGitTag"  { $appGitTag  = $fields[1].Trim() }
        "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
        "rootdir"       { $rootDir     =$fields[1].Trim() }
    }
}

# Change the working directory to where we need to be
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist!"
    return $false
}
cd $rootDir

# Source TCUtils.ps1 for test related functions
if (Test-Path ".\setupScripts\TCUtils.ps1"){
    . .\setupScripts\TCUtils.ps1
}
else{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}

$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Install stress-ng if not installed
$retVal = installApp "stress-ng" $ipv4 $appGitURL $appGitTag

if (-not $retVal){
    "stress-ng is not installed! Please install it before running the memory stress tests." | Tee-Object -Append -file $summaryLog
    return $false
}

"Stress-ng is installed! Will begin running memory stress tests shortly."

$vm1 = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue

# Get VM1's minimum memory setting
[int64]$vm1MinMem = ($vm1.MemoryMinimum/1MB)
"Info: Minimum memory for $vmName is $vm1MinMem MB"

$sleepPeriod = 120 #seconds
#
# Get VM1's memory after MemoryDemand available
#
while ($sleepPeriod -gt 0){
    [int64]$vm1BeforeAssigned = ($vm1.MemoryAssigned/1MB)
    [int64]$vm1BeforeDemand = ($vm1.MemoryDemand/1MB)

    if ($vm1BeforeAssigned -gt 0 -and $vm1BeforeDemand -gt 0){
        break
    }

    $sleepPeriod-= 5
    Start-Sleep -s 5
}

if ($vm1BeforeAssigned -le 0 -or $vm1BeforeDemand -le 0){
    "Error: vm1 $vmName reported 0 memory (assigned or demand)." | Tee-Object -Append -file $summaryLog
    return $False
}
#
# Step 1: Verify assigned memory could decrease after sleep a while
#
"Info: Memory stats after $vmName just boots up"
"  ${vmName}: assigned - $vm1BeforeAssigned | demand - $vm1BeforeDemand"

$sleepPeriod = 0 #seconds

while ($sleepPeriod -lt 420){
    [int64]$vm1Assigned = ($vm1.MemoryAssigned/1MB)
    [int64]$vm1Demand = ($vm1.MemoryDemand/1MB)
    if ( $vm1Assigned -lt $vm1BeforeAssigned){
        break
    }
    $sleepPeriod+= 5
    Start-Sleep -s 5
}

"Info: Memory stats after ${vmName} sleeps $sleepPeriod seconds"
"  ${vmName}: assigned - $vm1Assigned | demand - $vm1Demand"

# Verify assigned memory and demand decrease after sleep for a while
if ($vm1Assigned -ge $vm1BeforeAssigned -or $vm1Demand -ge $vm1BeforeDemand ){
    "Error: ${vmName} assigned or demand memory does not decrease after sleep $sleepPeriod seconds" | Tee-Object -Append -file $summaryLog
    return $False
}
else{
    "Info: ${vmName} assigned and demand memory decreases after sleep $sleepPeriod seconds"
}

#
# Step 2: Test assigned/demand memory could increase during stress test
#
# Sleep 2 more minutes to wait for the assigned memory decrease
Start-Sleep -s 120

[int64]$vm1BeforeAssigned = ($vm1.MemoryAssigned/1MB)
[int64]$vm1BeforeDemand = ($vm1.MemoryDemand/1MB)

# Verify assigned memory does not drop below minimum memory
if ($vm1BeforeAssigned -lt $vm1MinMem){
    "Error: $vm1Name assigned memory drops below minimum memory set, $vm1MinMem MB" | Tee-Object -Append -file $summaryLog
    return $false
}
"Memory stats before $vmName started stress-ng"
"  ${vmName}: assigned - $vm1BeforeAssigned | demand - $vm1BeforeAssigned"

# Send Command to consume
$job1 = Start-Job -ScriptBlock { param($ip, $sshKey, $rootDir) ConsumeMemory $ip $sshKey $rootDir } -InitializationScript $scriptBlock -ArgumentList($ipv4,$sshKey,$rootDir)
if (-not $?){
   "Error: Unable to start job for creating pressure on $vmName"
   return $false
}

# Sleep a few seconds so stress-ng starts and the memory assigned/demand gets updated
start-sleep -s 50

# Get memory stats while stress-ng is running
[int64]$vm1Demand = ($vm1.MemoryDemand/1MB)
[int64]$vm1Assigned = ($vm1.MemoryAssigned/1MB)
"Memory stats after $vmName started stress-ng"
"  ${vmName}: assigned - $vm1Assigned | demand - $vm1Demand"

if ($vm1Demand -le $vm1BeforeDemand -or $vm1Assigned -le $vm1BeforeAssigned){
   "Error: Memory assigned or demand did not increase after starting stress-ng"
   return $false
}
else{
    "Info: ${vmName} assigned and demand memory increased after starting stress-ng"
}

# Wait for jobs to finish now and make sure they exited successfully
$timeout = 120
$firstJobStatus = $false
while ($timeout -gt 0){
    if ($job1.Status -like "Completed"){
        $firstJobStatus = $true
        $retVal = Receive-Job $job1
    if (-not $retVal[-1]){
            "Error: Consume Memory script returned false on VM1 $vmName"
            return $false
        }
    }

    if ($firstJobStatus){
       break
    }

    $timeout -= 1
    start-sleep -s 1
}

#
# Step3: Verify assigned/demand memory could decrease again after stress test finished
#

# Get VM1's memory
while ($sleepPeriod -lt 420){
    [int64]$vm1AfterAssigned = ($vm1.MemoryAssigned/1MB)
    [int64]$vm1AfterDemand = ($vm1.MemoryDemand/1MB)
    if ( $vm1AfterAssigned -lt $vm1Assigned){
        break
    }
    $sleepPeriod+= 5
    Start-Sleep -s 5
}

"Info: Memory stats after ${vmName} sleeps $sleepPeriod seconds"
"  ${vmName}: assigned - $vm1AfterAssigned | demand - $vm1AfterDemand"

# Verify assigned memory and demand decrease after sleep less than 7 minutes
if ($vm1AfterAssigned -ge $vm1Assigned -or $vm1AfterDemand -ge $vm1Demand ){
    "Error: ${vmName} assigned or demand memory does not decrease after stress-ng stopped" | Tee-Object -Append -file $summaryLog
    return $False
}
else{
    "Info: ${vmName} assigned and demand memory decreases after stress-ng stopped"
}

# Wait for 2 minutes and check call traces
$retVal = CheckCallTracesWithDelay $sshKey $ipv4
if (-not $retVal) {
    Write-Output "ERROR: Call traces have been found on VM after the test run" | Tee-Object -Append -file $summaryLog
    return $false
} else {
    Write-Output "Info: No Call Traces have been found on VM" | Tee-Object -Append -file $summaryLog
}

return $True
