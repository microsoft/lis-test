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
 Verify that a VM with low memory pressure looses memory when another VM has a high memory demand.

 Description:
   Verify a VM with low memory pressure and lots of memory looses memory when a starved VM has a
   high memory demand.

   3 VMs are required for this test.

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
    setupscripts\DM_RemoveUnderPressure.ps1 -vmName nameOfVM -hvServer localhost -testParams 'sshKey=KEY;ipv4=IPAddress;rootDir=path\to\dir;vmName=NameOfVM1
        vmName=NameOfVM2;vmName=NameOfVM3'
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

# Name of third VM if have
$vm3Name = $null

# number of tries
[int]$tries = 0

# default number of tries
Set-Variable defaultTries -option Constant -value 10

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
        "VM2NAME"       { $vm2Name = $fields[1].Trim() }
        "VM3NAME"       { $vm3Name = $fields[1].Trim() }
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
    "Error: Please pass the sshKey to the script." | Tee-Object -Append -file $summaryLog
    return $false
}

if ($tries -le 0)
{
    $tries = $defaultTries
}


$vm1Name = $vmName

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

$vm3 = Get-VM -Name $vm3Name -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm3)
{
    "Error: VM $vm3Name does not exist" | Tee-Object -Append -file $summaryLog
    return $false
}

# determine which is vm2 and whih is vm3 based on memory weight
$vm2MemWeight = (Get-VMMemory -VM $vm2).Priority
if (-not $?)
{
    "Error: Unable to get $vm2Name memory weight." | Tee-Object -Append -file $summaryLog
    return $false
}

$vm3MemWeight = (Get-VMMemory -VM $vm3).Priority
if (-not $?)
{
    "Error: Unable to get $vm3Name memory weight." | Tee-Object -Append -file $summaryLog
    return $false
}

if ($vm3MemWeight -eq $vm2MemWeight)
{
    "Error: $vm3Name must have a higher memory weight than $vm2Name" | Tee-Object -Append -file $summaryLog
    return $false
}

if ($vm3MemWeight -lt $vm2MemWeight)
{
    # switch vm2 with vm3
    $aux = $vm2Name
    $vm2Name = $vm3Name
    $vm3Name = $aux

    $vm2 = Get-VM -Name $vm2Name -ComputerName $hvServer -ErrorAction SilentlyContinue

    if (-not $vm2)
    {
        "Error: VM $vm2Name does not exist anymore" | Tee-Object -Append -file $summaryLog
        return $false
    }

    $vm3 = Get-VM -Name $vm3Name -ComputerName $hvServer -ErrorAction SilentlyContinue

    if (-not $vm3)
    {
        "Error: VM $vm3Name does not exist anymore" | Tee-Object -Append -file $summaryLog
        return $false
    }
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

$timeoutStress = 1
$sleepPeriod = 120 #seconds
# get VM1 and VM2's Memory
while ($sleepPeriod -gt 0)
{
    [int64]$vm1BeforeAssigned = ($vm1.MemoryAssigned/[int64]1048576)
    [int64]$vm1BeforeDemand = ($vm1.MemoryDemand/[int64]1048576)
    [int64]$vm2BeforeAssigned = ($vm2.MemoryAssigned/[int64]1048576)
    [int64]$vm2BeforeDemand = ($vm2.MemoryDemand/[int64]1048576)

    if ($vm1BeforeAssigned -gt 0 -and $vm1BeforeDemand -gt 0 -and $vm2BeforeAssigned -gt 0 -and $vm2BeforeDemand -gt 0)
    {
        break
    }

    $sleepPeriod-= 5
    Start-Sleep -s 5
}

if ($vm1BeforeAssigned -le 0 -or $vm1BeforeDemand -le 0)
{
    "Error: vm1 or vm2 reported 0 memory (assigned or demand)." | Tee-Object -Append -file $summaryLog
    Stop-VM -VMName $vm2name -ComputerName $hvServer -force
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
Start-Sleep -s 240
# get memory stats for vm1 and vm2 just before vm3 starts
[int64]$vm1Assigned = ($vm1.MemoryAssigned/[int64]1048576)
[int64]$vm1Demand = ($vm1.MemoryDemand/[int64]1048576)
[int64]$vm2Assigned = ($vm2.MemoryAssigned/[int64]1048576)
[int64]$vm2Demand = ($vm2.MemoryDemand/[int64]1048576)

"Memory stats after $vm1Name and $vm2Name started stress-ng, but before $vm3Name starts: "
"  ${vm1Name}: assigned - $vm1Assigned | demand - $vm1Demand"
"  ${vm2Name}: assigned - $vm2Assigned | demand - $vm2Demand"

# Try to start VM3
$timeout = 120
StartDependencyVM $vm3Name $hvServer $tries
WaitForVMToStartKVP $vm3Name $hvServer $timeout

Start-sleep -s 60
# get memory stats after vm3 started
[int64]$vm1AfterAssigned = ($vm1.MemoryAssigned/[int64]1048576)
[int64]$vm1AfterDemand = ($vm1.MemoryDemand/[int64]1048576)
[int64]$vm2AfterAssigned = ($vm2.MemoryAssigned/[int64]1048576)
[int64]$vm2AfterDemand = ($vm2.MemoryDemand/[int64]1048576)

"Memory stats after $vm1Name and $vm2Name started stress-ng and after $vm3Name started: "
"  ${vm1Name}: assigned - $vm1AfterAssigned | demand - $vm1AfterDemand"
"  ${vm2Name}: assigned - $vm2AfterAssigned | demand - $vm2AfterDemand"

# Wait for jobs to finish now and make sure they exited successfully
$totalTimeout = $timeout = 120
$timeout = 0
$firstJobState = $false
$secondJobState = $false
$min = 0
while ($true)
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

        "Job1 finished in $min minutes."
    }

    if ($job2.State -like "Completed" -and -not $secondJobState)
    {
        $secondJobState = $true
        $retVal = Receive-Job $job2
        if (-not $retVal[-1])
        {
            "Error: Consume Memory script returned false on VM2 $vm2Name" | Tee-Object -Append -file $summaryLog
            Stop-VM -VMName $vm2name -ComputerName $hvServer -force
            Stop-VM -VMName $vm3name -ComputerName $hvServer -force
            return $falses
        }
        $diff = $totalTimeout - $timeout
        "Job2 finished in $min minutes."
    }

    if ($firstJobState -and $secondJobState)
    {
        break
    }

    if ($timeout%60 -eq 0)
    {
       "$min minutes passed"
        $min += 1
    }

    if ($totalTimeout -le 0)
    {
        break
    }
    $timeout += 5
    $totalTimeout -= 5
    Start-Sleep -s 5
}

[int64]$vm1DeltaAssigned = [int64]$vm1Assigned - [int64]$vm1AfterAssigned
[int64]$vm1DeltaDemand = [int64]$vm1Demand - [int64]$vm1AfterDemand
[int64]$vm2DeltaAssigned = [int64]$vm2Assigned - [int64]$vm2AfterAssigned
[int64]$vm2DeltaDemand = [int64]$vm2Demand - [int64]$vm2AfterDemand

"Deltas for $vm1Name and $vm2Name after $vm3Name started:"
"  ${vm1Name}: deltaAssigned - $vm1DeltaAssigned | deltaDemand - $vm1DeltaDemand"
"  ${vm2Name}: deltaAssigned - $vm2DeltaAssigned | deltaDemand - $vm2DeltaDemand"

# check that at least one of the first two VMs has lower assigned memory as a result of VM3 starting
if ($vm1DeltaAssigned -le 0 -and $vm2DeltaAssigned -le 0)
{
    "Error: Neither $vm1Name, nor $vm2Name didn't lower their assigned memory in response to $vm3Name starting" | Tee-Object -Append -file $summaryLog
    Stop-VM -VMName $vm2name -ComputerName $hvServer -force
    Stop-VM -VMName $vm3name -ComputerName $hvServer -force
    return $false
}

[int64]$vm1EndAssigned = ($vm1.MemoryAssigned/[int64]1048576)
[int64]$vm1EndDemand = ($vm1.MemoryDemand/[int64]1048576)
[int64]$vm2EndAssigned = ($vm2.MemoryAssigned/[int64]1048576)
[int64]$vm2EndDemand = ($vm2.MemoryDemand/[int64]1048576)

$sleepPeriod = 120 #seconds
# get VM3's Memory
while ($sleepPeriod -gt 0)
{
    [int64]$vm3EndAssigned = ($vm3.MemoryAssigned/[int64]1048576)
    [int64]$vm3EndDemand = ($vm3.MemoryDemand/[int64]1048576)

    if ($vm3EndAssigned -gt 0 -and $vm3EndDemand -gt 0)
    {
        break
    }

    $sleepPeriod-= 5
    Start-Sleep -s 5
}

if ($vm1EndAssigned -le 0 -or $vm1EndDemand -le 0 -or $vm2EndAssigned -le 0 -or $vm2EndDemand -le 0 -or $vm3EndAssigned -le 0 -or $vm3EndDemand -le 0)
{
    "Error: One of the VMs reports 0 memory (assigned or demand) after vm3 $vm3Name started" | Tee-Object -Append -file $summaryLog
    Stop-VM -VMName $vm2name -ComputerName $hvServer -force
    Stop-VM -VMName $vm3name -ComputerName $hvServer -force
    return $false
}

# stop vm2 and vm3
Stop-VM -VMName $vm2name -ComputerName $hvServer -force
Stop-VM -VMName $vm3name -ComputerName $hvServer -force

# Verify if errors occured on guest
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
Write-Output "Success: Memory was removed from a low priority VM with minimal memory pressure to a VM with high memory pressure!" | Tee-Object -Append -file $summaryLog
return $true
