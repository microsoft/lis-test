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
    Verify that demand changes with memory pressure by eatmemory inside the VM.

 Description:
    Verify that demand changes with memory pressure by eatmemory inside the VM and vm does not crash.

    Only 1 VM is required for this test.

    The testParams have the format of:

        vmName=Name of a VM, enable=[yes|no], minMem= (decimal) [MB|GB|%], maxMem=(decimal) [MB|GB|%],
        startupMem=(decimal) [MB|GB|%], memWeight=(0 < decimal < 100)

    The following is an example of a testParam for configuring Dynamic Memory

        "vmName=sles11x64sp3;enable=yes;minMem=512MB;maxMem=80%;startupMem=80%;memWeight=0;

    All scripts must return a boolean to indicate if the script completed successfully or not.

   .Parameter vmName
    Name of the VM.

    .Parameter hvServer
    Name of the Hyper-V server hosting the VM.

    .Parameter testParams
    Test data for this test case

    .Example
    setupscripts\DM_HotAdd_Eatmemory.ps1 -vmName nameOfVM -hvServer localhost -testParams 'sshKey=KEY;ipv4=IPAddress;rootDir=path\to\dir;vmName=NameOfVM1'
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

# Need a scriptblock in order to pass this function to start-job
$ScriptBlock = {
function DoStressEatmemory([String]$conIpv4, [String]$sshKey, [String]$rootDir, [int64]$memMB)
{
    # Because function is called as job, setup rootDir and source TCUtils again
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

    # Source TCUitls.ps1 for functions
    if (Test-Path ".\setupScripts\TCUtils.ps1"){
      . .\setupScripts\TCUtils.ps1
      "Sourced TCUtils.ps1"
    }
    else{
      "Error: Could not find setupScripts\TCUtils.ps1"
      return $false
    }

    $cmdToVM = @"
    #!/bin/bash
    count=0
    echo "Info: eatmemory $memMB MB" > HotAdd.log
    while true; do
        count=`$((`$count+1))
        echo "Info: eatmemory for `$count time" >> HotAdd.log
        eatmemory "${memMB}M"
        if [ `$? -nq 0 ]; then
            echo "Error: Cannot execute eatmemory $memMB MB > HotAddErrors.log"
            exit 1
        fi
    done
    exit 0
"@

    $filename = "CheckEatmemory.sh"

    # Check for file
    if (Test-Path ".\${filename}"){
        Remove-Item ".\${filename}"
    }

    Add-Content $filename "$cmdToVM"

    # Send file
    $retVal = SendFileToVM $conIpv4 $sshKey $filename "/root/${$filename}"

    # Check the return Value of SendFileToVM
    if (-not $retVal){
        return $false
    }

    # Execute command
    $retVal = SendCommandToVM $conIpv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"

    return $retVal
}
}

#######################################################################
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

# Write out test Params
$testParams

# sshKey used to authenticate ssh connection and send commands
$sshKey = $null

# IP Address of first VM
$ipv4 = $null

# Name of first VM
$vm1Name = $vmName

# Change working directory to root dir
$testParams -match "RootDir=([^;]+)"
if (-not $?){
    "Mandatory param RootDir=Path; not found!"
    return $false
}
$rootDir = $Matches[1]

if (Test-Path $rootDir){
    Set-Location -Path $rootDir
    if (-not $?)
    {
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
if (Test-Path ".\setupScripts\TCUtils.ps1"){
    . .\setupScripts\TCUtils.ps1
}
else
{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}

$params = $testParams.Split(";")
foreach ($p in $params){
    $fields = $p.Split("=")

    switch ($fields[0].Trim())
    {
        "ipv4"    { $ipv4    = $fields[1].Trim() }
        "sshKey"  { $sshKey  = $fields[1].Trim() }
        "appGitURL"  { $appGitURL  = $fields[1].Trim() }
        "appGitTag"  { $appGitTag  = $fields[1].Trim() }
        "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    }
}

if (-not $sshKey){
    "Error: Please pass the sshKey to the script."
    return $false
}

$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Install eatmemory if not installed
"Checking if eatmemory is installed"

$retVal = installApp "eatmemory" $ipv4 $appGitURL $appGitTag

if (-not $retVal){
    "Eatmemory is not installed! Please install it before running the memory stress tests." | Tee-Object -Append -file $summaryLog
    return $false
}

$vm1 = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
$sleepPeriod = 120 #seconds
# Get VM1 memory
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
    "Error: vm1 $vm1Name reported 0 memory (assigned or demand)." | Tee-Object -Append -file $summaryLog
    return $False
}

"Memory stats after $vm1Name started reporting "
"  ${vm1Name}: assigned - $vm1BeforeAssigned | demand - $vm1BeforeDemand"

$vmMemory=(Get-VMMemory -VM $vm1)

if ($vmMemory.DynamicMemoryEnabled){
    [int64]$vm1ConsumeMem = $vmMemory.Maximum
}
else{
    [int64]$vm1ConsumeMem = $vmMemory.Startup
}

# Transform to MB and stress with maximum
$vm1ConsumeMem /= 1MB
"Stress test consumes memory: $vm1ConsumeMem MB"
# Send Command to consume
$job1 = Start-Job -InitializationScript $scriptBlock -ScriptBlock { param($ipv4,$sshKey, $rootDir, $vm1ConsumeMem) DoStressEatmemory $ipv4 $sshKey $rootDir $vm1ConsumeMem } -ArgumentList($ipv4,$sshKey,$rootDir,$vm1ConsumeMem) | Receive-job

if (-not $?){
    "Error: Unable to start job for creating pressure on $vm1Name" | Tee-Object -Append -file $summaryLog
    return $false
}
$sleepTime = 30
# Wait for eatmemory to start and the memory assigned/demand gets updated
Start-Sleep -s $sleepTime

#Get memory stats for vm1 after eatmemory starts
[int64]$vm1Assigned = ($vm1.MemoryAssigned/1MB)
[int64]$vm1Demand = ($vm1.MemoryDemand/1MB)

"Memory stats before $vm1Name started eatmemory"
"  ${vm1Name}: assigned - $vm1Assigned | demand - $vm1Demand"

if ($vm1Demand -le $vm1BeforeDemand){
    "Error: Memory Demand did not increase after starting eatmemory" | Tee-Object -Append -file $summaryLog
    return $false
}
# Sleep for 3 minutes to wait for eatmemory runnning
$sleepTime = 180
Start-Sleep -s $sleepTime

$isAlive = WaitForVMToStartKVP $vm1Name $hvServer 10
if (-not $isAlive){
    "Error: VM is unresponsive after running the memory stress test" | Tee-Object -Append -file $summaryLog
    return $false
}
# Check whether has error
$errorsOnGuest = echo y | bin\plink -i ssh\${sshKey} root@$ipv4 "cat HotAddErrors.log"
if (-not  [string]::IsNullOrEmpty($errorsOnGuest)){
    $errorsOnGuest
    return $false
}

# Wait for 2 minutes and check call traces and ignore oom
$retVal = CheckCallTracesWithDelay $sshKey $ipv4 $true
if (-not $retVal) {
    Write-Output "ERROR: Call traces (ignore OOM) have been found on VM after the test run" | Tee-Object -Append -file $summaryLog
    return $false
} else {
    Write-Output "Info: No Call Traces (ignore OOM) have been found on VM" | Tee-Object -Append -file $summaryLog
}

return $true
