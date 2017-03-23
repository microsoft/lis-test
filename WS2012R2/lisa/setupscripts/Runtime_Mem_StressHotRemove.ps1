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
	Verify that can remove memory while stress tool is running.

 Description:
    Verify that memory changes while stress tool is running.

	Only 1 VM is required for this test.

   .Parameter vmName
    Name of the VM under test.

    .Parameter hvServer
    Name of the Hyper-V server hosting the VM.

    .Parameter testParams
    Test data for this test case.

    .Example
    setupscripts\Runtime_Mem_StressHotRemove.ps1 -vmName nameOfVM -hvServer localhost -testParams 
    'sshKey=KEY; ipv4=IPAddress; rootDir=path\to\dir; startupMem=2GB'
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

function checkStressNg([String]$conIpv4, [String]$sshKey)
{
    $cmdToVM = @"
#!/bin/bash
        command -v stress-ng
        sts=`$?
        exit `$sts
"@
    #"pingVMs: sendig command to vm: $cmdToVM"
    $filename = "CheckStress-ng.sh"

    # check for file
    if (Test-Path ".\${filename}"){
        Remove-Item ".\${filename}"
    }

    Add-Content $filename "$cmdToVM"

    # send file
    $retVal = SendFileToVM $conIpv4 $sshKey $filename "/root/${$filename}"
    # check the return Value of SendFileToVM
    if (-not $retVal){
        return $false
    }

    # execute command
    $retVal = SendCommandToVM $conIpv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"
    return $retVal
}

# we need a scriptblock in order to pass this function to start-job
$scriptBlock = {
  # function for starting stress-ng
  function ConsumeMemory([String]$conIpv4, [String]$sshKey, [String]$rootDir)
  {

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
        # Will stress only half of free memory
        __freeMem=`$((__freeMem/2))
        echo ConsumeMemory: Memory to be stressed: `$__freeMem MB >> /root/HotAdd.log 2>&1
        __threads=16
        __chunks=`$((`$__freeMem / `$__threads))
        echo "Going to start `$__threads instance(s) of stress-ng every 2 seconds, each consuming `$__chunks memory" >> /root/HotAdd.log 2>&1
        stress-ng -m `$__threads --vm-bytes `${__chunks}M -t 150 --backoff 1500000
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
$vm1Name = $null

# change working directory to root dir
$testParams -match "RootDir=([^;]+)"
if (-not $?){
  "Mandatory param RootDir=Path; not found!"
  return $false
}
$rootDir = $Matches[1]

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
if (Test-Path ".\setupScripts\TCUtils.ps1"){
  . .\setupScripts\TCUtils.ps1
}
else{
  "Error: Could not find setupScripts\TCUtils.ps1"
  return $false
}

$params = $testParams.Split(";")
foreach ($p in $params){
    $fields = $p.Split("=")

    switch ($fields[0].Trim()){
      "TC_COVERED"    { $TC_COVERED = $fields[1].Trim() }
      "ipv4"          { $ipv4       = $fields[1].Trim() }
      "sshKey"        { $sshKey     = $fields[1].Trim() }
      "startupMem"  { 
        $startupMem  = ConvertToMemSize $fields[1].Trim() $hvServer

        if ($startupMem -le 0){
          "Error: Unable to convert startupMem to int64."
          return $false
        }
        "startupMem: $startupMem"
      }
    }
}

if (-not $sshKey){
  "Error: Please pass the sshKey to the script."
  return $false
}

# Delete any previous summary.log file
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue

Write-output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

$vm1 = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue

if (-not $vm1){
  "Error: VM $vmName does not exist"
  return $false
}

# Check if stress-ng is installed
"Checking if stress-ng is installed"

$retVal = checkStressNg $ipv4 $sshKey

if (-not $retVal){
    "Stress-ng is not installed! Please install it before running the memory stress tests."
    return $false
}

"Stress-ng is installed! Will begin running memory stress tests shortly."

# Get memory stats from vm1
start-sleep -s 10
$sleepPeriod = 60

# get VM1 memory from host and guest
while ($sleepPeriod -gt 0){
  [int64]$vm1BeforeAssigned = ($vm1.MemoryAssigned/1MB)
  [int64]$vm1BeforeDemand = ($vm1.MemoryDemand/1MB)

  [int64]$vm1BeforeAssignedGuest = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "cat /proc/meminfo | grep -i MemFree | awk '{ print `$2 }'"

  if ($vm1BeforeAssigned -gt 0 -and $vm1BeforeDemand -gt 0 -and $vm1BeforeAssignedGuest -gt 0){
    break
  }

  $sleepPeriod-= 5
  start-sleep -s 5
}

if ($vm1BeforeAssigned -le 0 -or $vm1BeforeDemand -le 0 -or $vm1BeforeAssignedGuest -le 0){
  "Error: vm1 $vmName reported 0 memory (assigned or demand)."
  return $False
}

"Memory stats after $vmName started reporting "
"  ${vmName}: assigned - $vm1BeforeAssigned | demand - $vm1BeforeDemand"

# Send Command to consume
$job1 = Start-Job -ScriptBlock { param($ip, $sshKey, $rootDir) ConsumeMemory $ip $sshKey $rootDir } -InitializationScript $scriptBlock -ArgumentList($ipv4,$sshKey,$rootDir)
if (-not $?){
  "Error: Unable to start job for creating pressure on $vmName"
  return $false
}

# sleep a few seconds so stress-ng starts and the memory assigned/demand gets updated
start-sleep -s 80

# get memory stats while stress-ng is running
[int64]$vm1Demand = ($vm1.MemoryDemand/1MB)
[int64]$vm1Assigned = ($vm1.MemoryAssigned/1MB)
"Memory stats after $vm1Name started stress-ng"
"  ${vmName}: assigned - $vm1Assigned | demand - $vm1Demand"

if ($vm1Demand -le $vm1BeforeDemand){
  "Error: Memory Demand did not increase after starting stress-ng"
  return $false
}

# Memory value to be assigned will be 300mb higher than memory demand (below that we might receive an error)
[int64]$testMem = $vm1.MemoryDemand + 314572800

# Adjust testMem value if it's not an even number
[int64]$testMem = $testMem / 1048576
if ($testMem % 2 -eq 0 ){
  [int64]$testMem = $testMem * 1048576
}   
else{
  [int64]$testMem = $testMem + 1
  [int64]$testMem = $testMem * 1048576
}

# Set new memory value
for ($i=0; $i -lt 3; $i++){
  Set-VMMemory -VMName $vmName  -ComputerName $hvServer -DynamicMemoryEnabled $false -StartupBytes $testMem 
  Start-sleep -s 5
  if ($vm1.MemoryAssigned -eq $testMem){
    [int64]$vm1AfterAssigned = ($vm1.MemoryAssigned/1MB)
    [int64]$vm1AfterDemand = ($vm1.MemoryDemand/1MB) 

    [int64]$vm1AfterAssignedGuest = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "cat /proc/meminfo | grep -i MemFree | awk '{ print `$2 }'"
    break
  }
}

[int64]$vm1AfterAssigned = ($vm1.MemoryAssigned/1MB)
if ( $vm1AfterAssigned -eq $vm1BeforeAssigned ){
  "Error: VM failed to change memory!"
  "LIS 4.1 or kernel version 4.4 required"
  return $false
}

if ( $vm1AfterAssigned -ne ($testMem/1MB)  ){
    "Error: Memory assigned doesn't match the memory set as parameter!"
    "Memory stats after $vmName memory was changed "
    "  ${vmName}: assigned - $vm1AfterAssigned | demand - $vm1AfterDemand"
    return $false
}

if ($vm1AfterAssignedGuest -ge $vm1BeforeAssignedGuest){
    "Error: Guest reports that memory value hasn't decreased!"
    "Memory stats after $vmName memory was changed "
    "  ${vmName}: Initial Memory - $vm1BeforeAssignedGuest KB :: After setting new value - $vm1AfterAssignedGuest KB"
    return $false 
}

"Memory stats after $vmName memory was changed "
"  ${vmName}: assigned - $vm1AfterAssigned | demand - $vm1AfterDemand"
"  Reported free memory inside ${vmName}: Before - $vm1BeforeAssignedGuest KB | After - $vm1AfterAssignedGuest KB"

# Wait for jobs to finish now and make sure they exited successfully
$timeout = 120
$firstJobStatus = $false
while ($timeout -gt 0){
  if ($job1.Status -like "Completed"){
    $firstJobStatus = $true
    $retVal = Receive-Job $job1
    if (-not $retVal[-1]){
      "Error: Consume Memory script returned false on VM $vmName"
      return $false
    }
    $diff = $totalTimeout - $timeout
    "Job finished in $diff seconds."
  }
  if ($firstJobStatus){
    break
  }

  $timeout -= 1
  start-sleep -s 1
}
start-sleep -s 5

# get memory stats after strss-ng stopped running
[int64]$vm1AfterStressAssigned = ($vm1.MemoryAssigned/1MB)
[int64]$vm1AfterStressDemand = ($vm1.MemoryDemand/1MB)
"Memory stats after $vmName stress-ng run"
"  ${vmName}: assigned - $vm1AfterStressAssigned | demand - $vm1AfterStressDemand"

if ($vm1AfterStressDemand -ge $vm1Demand){
  "Error: Memory Demand did not decrease after stress-ng stopped"
  return $false
}

"VM changed its memory and ran memory stress tests successfully!"
return $true