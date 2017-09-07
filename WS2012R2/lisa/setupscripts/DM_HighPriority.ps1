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
 Verify that high priority VMs are preferentially served memory.

 Description:
   Verify that VMs with high memory priority get assigned more memory under pressure, than a VM with lower priority.

   2 VMs are required for this test.

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
    setupscripts\DM_HighPriority.ps1 -vmName nameOfVM -hvServer localhost -testParams 'sshKey=KEY;ipv4=IPAddress;rootDir=path\to\dir;vmName=NameOfVM1;vmName=NameOfVM2'
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)
Set-PSDebug -Strict
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

# IP Address of second VM
$vm2ipv4 = $null

# Name of first VM
$vm1Name = $null

# Name of second VM
$vm2Name = $null

# string array vmNames
[String[]]$vmNames = @()

# number of tries
[int]$tries = 0

# default number of tries
Set-Variable defaultTries -option Constant -value 3

# change working directory to root dir
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
        "vmName"  { $vmNames = $vmNames + $fields[1].Trim() }
        "ipv4"    { $ipv4    = $fields[1].Trim() }
        "sshKey"  { $sshKey  = $fields[1].Trim() }
        "tries"  { $tries  = $fields[1].Trim() }
        "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
      }
}

$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

if (-not $sshKey)
{
    "Error: sshKey was not specified." | Tee-Object -Append -file $summaryLog
    return $false
}

if ($tries -le 0)
{
    $tries = $defaultTries
}

if ($vmNames.count -lt 2)
{
    "Error: two VMs are necessary for the High Priority test." | Tee-Object -Append -file $summaryLog
    return $false
}

$vm1Name = $vmNames[0]
$vm2Name = $vmNames[1]
if ($vm1Name -notlike $vmName)
{
    if ($vm2Name -like $vmName)
    {
        # switch vm1Name with vm2Name
        $vm1Name = $vmNames[1]
        $vm2Name = $vmNames[0]
    }
    else
    {
      "Error: The first vmName testparam must be the same as the vmname from the vm section in the xml." | Tee-Object -Append -file $summaryLog
      return $false
    }
}

$vm1 = Get-VM -Name $vm1Name -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm1)
{
    "Error: VM $vm1Name does not exist" | Tee-Object -Append -file $summaryLog
    return $false
}

$vm2 = Get-VM -Name $vm2Name -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm2)
{
    "Error: VM $vm2Name does not exist" | Tee-Object -Append -file $summaryLog
    return $false
}

# Check if stress-ng is installed
"Checking if stress-ng is installed"

$retVal = check_app "stress-ng"
if (-not $retVal)
{
    "stress-ng is not installed! Please install it before running the memory stress tests." | Tee-Object -Append -file $summaryLog
    return $false
}
"stress-ng is installed! Will begin running memory stress tests shortly."

#
# LIS Started VM1, so start VM2
#
$timeout = 120
StartDependencyVM $vm2Name $hvServer $tries
WaitForVMToStartKVP $vm2Name $hvServer $timeout 
$vm2ipv4 = GetIPv4 $vm2Name $hvServer

$timeoutStress = 0
$sleepPeriod = 120 #seconds
# get VM1 and VM2's Memory
while ($sleepPeriod -gt 0)
{
    [int64]$vm1BeforeAssigned = ($vm1.MemoryAssigned/1MB)
    [int64]$vm1BeforeDemand = ($vm1.MemoryDemand/1MB)
    [int64]$vm2BeforeAssigned = ($vm2.MemoryAssigned/1MB)
    [int64]$vm2BeforeDemand = ($vm2.MemoryDemand/1MB)

    if ($vm1BeforeAssigned -gt 0 -and $vm1BeforeDemand -gt 0 -and $vm2BeforeAssigned -gt 0 -and $vm2BeforeDemand -gt 0)
    {
      break
    }

    $sleepPeriod-= 5
    Start-Sleep -s 5
}

if ($vm1BeforeAssigned -le 0 -or $vm1BeforeDemand -le 0 -or $vm2BeforeAssigned -le 0 -or $vm2BeforeDemand -le 0)
{
    "Error: vm1 or vm2 reported 0 memory (assigned or demand)." | Tee-Object -Append -file $summaryLog
    Stop-VM -VMName $vm2name -ComputerName $hvServer $vm2name -force
    return $False
}

"Memory stats after both $vm1Name and $vm2Name started reporting "
"  ${vm1Name}: assigned - $vm1BeforeAssigned | demand - $vm1BeforeDemand"
"  ${vm2Name}: assigned - $vm2BeforeAssigned | demand - $vm2BeforeDemand"

# Check if stress-ng is installed
"Checking if stress-ng is installed"

$retVal = check_app "stress-ng" $vm2ipv4
if (-not $retVal)
{
    "stress-ng is not installed on $vm2Name! Please install it before running the memory stress tests." | Tee-Object -Append -file $summaryLog
    return $false
}

"stress-ng is installed on $vm2Name! Will begin running memory stress tests shortly."

# Calculate the amount of memory to be consumed on VM1 and VM2 with stress-ng
[int64]$vm1ConsumeMem = (Get-VMMemory -VM $vm1).Maximum
[int64]$vm2ConsumeMem = (Get-VMMemory -VM $vm2).Maximum
# only consume 75% of max memory
$vm1ConsumeMem = ($vm1ConsumeMem / 4) * 3
$vm2ConsumeMem = ($vm2ConsumeMem / 4) * 3
# transform to MB
$vm1ConsumeMem /= 1MB
$vm2ConsumeMem /= 1MB

# standard chunks passed to stress-ng
[int64]$chunks = 512 #MB
[int]$vm1Duration = 400 #seconds
[int]$vm2Duration = 380 #seconds

# Send Command to consume
$job1 = Start-Job -ScriptBlock { param($ip, $sshKey, $rootDir, $timeoutStress, $vm1ConsumeMem, $vm1Duration, $chunks) ConsumeMemory $ip $sshKey $rootDir $timeoutStress $vm1ConsumeMem $vm1Duration $chunks } -InitializationScript $DM_scriptBlock -ArgumentList($ipv4,$sshKey,$rootDir,$timeoutStress,$vm1ConsumeMem,$vm1Duration,$chunks)
if (-not $?)
{
    "Error: Unable to start job for creating pressure on $vm1Name" | Tee-Object -Append -file $summaryLog
    Stop-VM -VMName $vm2name -ComputerName $hvServer -force
    return $false
}

$job2 = Start-Job -ScriptBlock { param($ip, $sshKey, $rootDir, $timeoutStress, $vm2ConsumeMem, $vm2Duration, $chunks) ConsumeMemory $ip $sshKey $rootDir $timeoutStress $vm2ConsumeMem $vm2Duration $chunks } -InitializationScript $DM_scriptBlock -ArgumentList($vm2ipv4,$sshKey,$rootDir,$timeoutStress,$vm2ConsumeMem,$vm2Duration,$chunks)
if (-not $?)
{
    "Error: Unable to start job for creating pressure on $vm2Name" | Tee-Object -Append -file $summaryLog
    Stop-VM -VMName $vm2name -ComputerName $hvServer -force
    return $false
}

# sleep a few seconds so all stress-ng processes start and the memory assigned/demand gets updated
Start-Sleep -s 10
# get memory stats for vm1 and vm2

[int64[]]$vm1Assigned = @()
[int64[]]$vm1Demand = @()
[int64[]]$vm2Assigned = @()
[int64[]]$vm2Demand = @()

[int64]$samples = 0

# Wait for jobs to finish now and make sure they exited successfully
$totalTimeout = $timeout = 420
$firstJobState = $false
$secondJobState = $false

while ($timeout -gt 0)
{
    if ($job1.State -like "Completed" -and -not $firstJobState)
    {
        $firstJobState = $true
        $retVal = Receive-Job $job1
        if (-not $retVal[-1])
        {
            "Error: Consume Memory script returned false on VM1 $vm1Name" | Tee-Object -Append -file $summaryLog
            Stop-VM -VMName $vm2name -ComputerName $hvServer -force
            Stop-VM -VMName $vm3name -ComputerName $hvServer -force
            return $false
        }
        $diff = $totalTimeout - $timeout
        "Job1 finished in $diff seconds."
    }

    if ($job2.State -like "Completed" -and -not $secondJobState)
    {
        $secondJobState = $true
        $retVal = Receive-Job $job1
        if (-not $retVal[-1])
        {
            "Error: Consume Memory script returned false on VM2 $vm2Name" | Tee-Object -Append -file $summaryLog
            Stop-VM -VMName $vm2name -ComputerName $hvServer -force
            Stop-VM -VMName $vm3name -ComputerName $hvServer -force
            return $false
        }
        $diff = $totalTimeout - $timeout
        "Job2 finished in $diff seconds."
    }

    if ($firstJobState -and $secondJobState)
    {
        break
    }

    if (-not ($firstJobState -or $secondJobState))
    {
        $vm1Assigned = $vm1Assigned + ($vm1.MemoryAssigned/1MB)
        $vm2Assigned = $vm2Assigned + ($vm2.MemoryAssigned/1MB)
        $vm1Demand = $vm1Demand + ($vm1.MemoryDemand/1MB)
        $vm2Demand = $vm2Demand + ($vm2.MemoryDemand/1MB)

        $samples += 1
    }
    if ($timeout -le 0)
    {
        break
    }

    $timeout -= 1
    Start-Sleep -s 1
}

if ($samples -le 0)
{
    "Error: No data has been sampled." | Tee-Object -Append -file $summaryLog
    Stop-VM -VMName $vm2name -ComputerName $hvServer -force
    return $false
}

"Got $samples samples"

$vm1bigger = $vm2bigger = 0
# count the number of times vm1 had higher assigned memory
for ($i = 0; $i -lt $samples; $i++)
{
    if ($vm1Assigned[$i] -gt $vm2Assigned[$i])
    {
        $vm1bigger += 1
    }
    else
    {
        $vm2bigger += 1
    }

    "sample ${i}: vm1 = $vm1Assigned[$i]    -   vm2 = $vm2Assigned[$i]"
}

if ($vm1bigger -le $vm2bigger)
{
    "Error: $vm1Name didn't grow faster than $vm2Name" | Tee-Object -Append -file $summaryLog
    Stop-VM -VMName $vm2name -ComputerName $hvServer -force
    return $false
}

# stop vm2
Stop-VM -VMName $vm2name -ComputerName $hvServer -force

# Verify if errors occured on VM1
$isAlive = WaitForVMToStartKVP $vm1Name $hvServer 10
if (-not $isAlive){
    "Error: VM is unresponsive after running the memory stress test" | Tee-Object -Append -file $summaryLog
    return $false
}

$errorsOnGuest = echo y | bin\plink -i ssh\${sshKey} root@$ipv4 "cat HotAddErrors.log"
if (-not  [string]::IsNullOrEmpty($errorsOnGuest)){
    $errorsOnGuest
    return $false
}

# Everything ok
"Success: High priority VM received more memory under same pressure" | Tee-Object -Append -file $summaryLog
return $true