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
 Verify that demand changes with memory pressure inside the VM.

 Description:
   Verify that demand changes with memory pressure inside the VM.

   Only 1 VM is required for this test.

   The testParams have the format of:

      vmName=Name of a VM, enable=[yes|no], minMem= (decimal) [MB|GB|%], maxMem=(decimal) [MB|GB|%],
      startupMem=(decimal) [MB|GB|%], memWeight=(0 < decimal < 100)

   Only the vmName param is taken into consideration. This needs to appear at least twice for
   the test to start.

      Tries=(decimal)
       This controls the number of times the script tries to start the second VM. If not set, a default
       value of 3 is set.
       This is necessary because Hyper-V usually removes memory from a VM only when a second one applies pressure.
       However, the second VM can fail to start while memory is removed from the first.
       There is a 30 second timeout between tries, so 3 tries is a conservative value.

   The following is an example of a testParam for configuring Dynamic Memory

       "Tries=3;vmName=sles11x64sp3;enable=yes;minMem=512MB;maxMem=80%;startupMem=80%;memWeight=0;
       vmName=sles11x64sp3_2;enable=yes;minMem=512MB;maxMem=25%;startupMem=25%;memWeight=0"

   All scripts must return a boolean to indicate if the script completed successfully or not.

   .Parameter vmName
    Name of the VM to remove NIC from .

    .Parameter hvServer
    Name of the Hyper-V server hosting the VM.

    .Parameter testParams
    Test data for this test case

    .Example
    setupscripts\DM_HotAdd_Stress_ng.ps1 -vmName nameOfVM -hvServer localhost -testParams 'sshKey=KEY;ipv4=IPAddress;rootDir=path\to\dir;vmName=NameOfVM1'
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

#######################################################################
#
# Main script body
#
#######################################################################
#
# Check input arguments
#
if ($vmName -eq $null)
{
    "Error: VM name is null"
    return $False
}

if ($hvServer -eq $null)
{
    "Error: hvServer is null"
    return $False
}

if ($testParams -eq $null)
{
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

# Number of tries
[int]$tries = 0

# Default number of tries
Set-Variable defaultTries -option Constant -value 3

# Change working directory to root dir
$testParams -match "RootDir=([^;]+)"
if (-not $?)
{
    "Mandatory param RootDir=Path; not found!"
    return $false
}
$rootDir = $Matches[1]

if (Test-Path $rootDir)
{
    Set-Location -Path $rootDir
    if (-not $?)
    {
        "Error: Could not change directory to $rootDir !"
        return $false
    }
    "Changed working directory to $rootDir"
}
else
{
    "Error: RootDir = $rootDir is not a valid path"
    return $false
}

# Source TCUitls.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1")
{
    . .\setupScripts\TCUtils.ps1
}
else
{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")

    switch ($fields[0].Trim())
    {
        "ipv4"    { $ipv4    = $fields[1].Trim() }
        "sshKey"  { $sshKey  = $fields[1].Trim() }
        "tries"  { $tries  = $fields[1].Trim() }
        "appGitURL"  { $appGitURL  = $fields[1].Trim() }
        "appGitTag"  { $appGitTag  = $fields[1].Trim() }
        "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
        "Stress_Level" { $timeoutStress = $fields[1].Trim() }
    }

}

if (-not $sshKey)
{
    "Error: Please pass the sshKey to the script."
    return $false
}

if ($tries -le 0)
{
    $tries = $defaultTries
}


$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

$vm1 = Get-VM -Name $vm1Name -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm1)
{
    "Error: VM $vm1Name does not exist"
    return $false
}

# Install stress-ng if not installed
"Checking if stress-ng is installed"

$retVal = installApp "stress-ng" $ipv4 $appGitURL $appGitTag

if (-not $retVal)
{
    "stress-ng is not installed! Please install it before running the memory stress tests." | Tee-Object -Append -file $summaryLog
    return $false
}

Start-Sleep -s 40
$sleepPeriod = 120 #seconds
# Get VM1 and VM2's Memory
while ($sleepPeriod -gt 0)
{
    [int64]$vm1BeforeAssigned = ($vm1.MemoryAssigned/1MB)
    [int64]$vm1BeforeDemand = ($vm1.MemoryDemand/1MB)

    if ($vm1BeforeAssigned -gt 0 -and $vm1BeforeDemand -gt 0)
    {
        break
    }

    $sleepPeriod-= 5
    Start-Sleep -s 5
  }

if ($vm1BeforeAssigned -le 0 -or $vm1BeforeDemand -le 0)
{
    "Error: vm1 $vm1Name reported 0 memory (assigned or demand)." | Tee-Object -Append -file $summaryLog
    return $False
}

"Memory stats after $vm1Name started reporting "
"  ${vm1Name}: assigned - $vm1BeforeAssigned | demand - $vm1BeforeDemand"

# Set the amount of sleep time needed
if ($timeoutStress -eq 0) {
    $sleepTime = 200
    $duration = 0
    $chunk = 0
}
elseif ($timeoutStress -eq 1) {
    $sleepTime = 60
    $duration = 120
    $chunk = 1
}
elseif ($timeoutStress -eq 2) {
    $sleepTime = 20
    $duration = 40
    $chunk = 1
}
else {
    $sleepTime = 20
    $duration = 40
    $chunk = 1
}

# Calculate the amount of memory to be consumed on VM1 and VM2 with stress-ng
[int64]$vm1ConsumeMem = (Get-VMMemory -VM $vm1).Maximum

# Transform to MB
$vm1ConsumeMem /= 1MB

# Send Command to consume
$job1 = Start-Job -ScriptBlock { param($ip, $sshKey, $rootDir, $timeoutStress, $vm1ConsumeMem, $duration, $chunk) ConsumeMemory $ip $sshKey $rootDir $timeoutStress $vm1ConsumeMem $duration $chunk} -InitializationScript $DM_scriptBlock -ArgumentList($ipv4,$sshKey,$rootDir,$timeoutStress,$vm1ConsumeMem, $duration, $chunk)
if (-not $?)
{
    "Error: Unable to start job for creating pressure on $vm1Name" | Tee-Object -Append -file $summaryLog
    return $false
}

# Wait for stress-ng to start and the memory assigned/demand gets updated
Start-Sleep -s $sleepTime

# Get memory stats for vm1 after stress-ng starts
[int64]$vm1Assigned = ($vm1.MemoryAssigned/1MB)
[int64]$vm1Demand = ($vm1.MemoryDemand/1MB)

"Memory stats after $vm1Name started stress-ng"
"  ${vm1Name}: assigned - $vm1Assigned | demand - $vm1Demand"

if ($vm1Demand -le $vm1BeforeDemand)
{
    "Error: Memory Demand did not increase after starting stress-ng" | Tee-Object -Append -file $summaryLog
    return $false
}

# Wait for jobs to finish now and make sure they exited successfully
$timeout = 240
$firstJobStatus = $false
while ($timeout -gt 0)
{
    if ($job1.Status -like "Completed")
    {
        $firstJobStatus = $true
        $retVal = Receive-Job $job1
        if (-not $retVal[-1])
        {
          "Error: Consume Memory script returned false on VM1 $vm1Name" | Tee-Object -Append -file $summaryLog
          return $false
        }
        $diff = $totalTimeout - $timeout
        "Job finished in $diff seconds."
    }

    if ($firstJobStatus)
    {
        break
    }

    $timeout -= 1
    Start-Sleep -s 1
}

# Verify if errors occured on guest
$isAlive = WaitForVMToStartKVP $vm1Name $hvServer 10
if (-not $isAlive){
    "Error: VM is unresponsive after running the memory stress test" | Tee-Object -Append -file $summaryLog
    return $false
}

$errorsOnGuest = echo y | bin\plink -i ssh\${sshKey} root@$ipv4 "cat HotAddErrors.log"
if (-not  [string]::IsNullOrEmpty($errorsOnGuest)){
    $errorsOnGuest | Tee-Object -Append -file $summaryLog
    return $false
}

Start-Sleep -s 20
# Get memory stats after stress-ng finished
[int64]$vm1AfterAssigned = ($vm1.MemoryAssigned/1MB)
[int64]$vm1AfterDemand = ($vm1.MemoryDemand/1MB)

"Memory stats after stress-ng finished: "
"  ${vm1Name}: assigned - $vm1AfterAssigned | demand - $vm1AfterDemand"

if ($vm1AfterDemand -ge $vm1Demand)
{
    "Error: Demand did not go down after stress-ng finished." | Tee-Object -Append -file $summaryLog
    return $false
}

"Memory Hot Add (using stress-ng) completed successfully!" | Tee-Object -Append -file $summaryLog
return $true
