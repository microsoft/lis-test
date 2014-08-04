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
 Verify that the assigned memory never exceeds the VMs Maximum Memory setting.

 Description:
   Using a VM with dynamic memory enabled, verify the assigned memory never exceeds the VMs Maximum Memory setting.
   Expected result: VM2’s memory mustn't exceed the Maximum Memory setting.

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
    setupScripts\DM_CONFIGURE_MEMORY -vmName sles11sp3x64 -hvServer localhost -testParams "vmName=sles11x64sp3;enable=yes;minMem=512MB;maxMem=80%;startupMem=80%;memWeight=0;`
       vmName=sles11x64sp3_2;enable=yes;minMem=512MB;maxMem=25%;startupMem=25%;memWeight=0"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

# we need a scriptblock in order to pass this function to start-job
$scriptBlock = {
  # function for starting stresstestapp
  function ConsumeMemory([String]$conIpv4, [String]$sshKey, [String]$rootDir)
  {

  # because function is called as job, setup rootDir and source TCUtils again
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
    "Sourced TCUtils.ps1"
  }
  else
  {
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
  }
  
  
      $cmdToVM = @"
#!/bin/bash
        if [ ! -e /proc/meminfo ]; then
          echo ConsumeMemory: no meminfo found. Make sure /proc is mounted >> /root/HotAddRemove.log 2>&1
          exit 100
        fi
        __totalMem=`$(cat /proc/meminfo | grep -i MemTotal | awk '{ print `$2 }')
        __totalMem=`$((__totalMem/1024))
        echo ConsumeMemory: Total Memory found `$__totalMem MB >> /root/HotAddRemove.log 2>&1
        __iterations=10     
        __chunks=128
        echo "Going to start `$__iterations instance(s) of stresstestapp each consuming 256MB memory" >> /root/HotAddRemove.log 2>&1
        for ((i=0; i < `$__iterations; i++)); do
          stressapptest -M `$__chunks -s 10 &
          sleep 10
          __chunks=`$((__chunks+128))  
          echo "Memory chunks: `$__chunks" >> /root/HotAddRemove.log 2>&1
        done
        echo "Waiting for jobs to finish" >> /root/HotAddRemove.log 2>&1
        wait
        exit 0
"@

    #"pingVMs: sendig command to vm: $cmdToVM"
    $filename = "ConsumeMem.sh"
    
    # check for file
    if (Test-Path ".\${filename}")
    {
      Remove-Item ".\${filename}"
    }
    
    Add-Content $filename "$cmdToVM"
    
    # send file
    $retVal = SendFileToVM $conIpv4 $sshKey $filename "/root/${$filename}"
    
    # delete file unless the Leave_trail param was set to yes.
    if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
    {
      Remove-Item ".\${filename}"
    }
    
    # check the return Value of SendFileToVM
    if (-not $retVal[-1])
    {
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

if ($vmNames.count -lt 2)
{
  "Error: two VMs are necessary for the Maximum Memory Honored test."
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
    "Error: The first vmName testparam must be the same as the vmname from the vm section in the xml."
    return $false
  }
}

$vm1 = Get-VM -Name $vm1Name -ComputerName $hvServer -ErrorAction SilentlyContinue

if (-not $vm1)
{
  "Error: VM $vm1Name does not exist"
  return $false
}

$vm2 = Get-VM -Name $vm2Name -ComputerName $hvServer -ErrorAction SilentlyContinue

if (-not $vm2)
{
  "Error: VM $vm2Name does not exist"
  return $false
}


#
# LIS Started VM1, so start VM2
#

if (Get-VM -Name $vm2Name |  Where { $_.State -notlike "Running" })
{

  [int]$i = 0
  # try to start VM2
  for ($i=0; $i -lt $tries; $i++)
  {

    Start-VM -Name $vm2Name -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $?)
    {
      "Warning: Unable to start VM ${vm2Name} on attempt $i"
    }
    else 
    {
      $i = 0
      break   
    }

    Start-sleep -s 30
  }

  if ($i -ge $tries)
  {
    "Error: Unable to start VM2 after $tries attempts"
    return $false
  }

}

# just to make sure vm2 started
if (Get-VM -Name $vm2Name |  Where { $_.State -notlike "Running" })
{
  "Error: $vm2Names never started."
  return $false
}

# get memory stats from vm1 and vm2
# wait up to 2 min for it

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
  start-sleep -s 5

}

if ($vm1BeforeAssigned -le 0 -or $vm1BeforeDemand -le 0 -or $vm2BeforeAssigned -le 0 -or $vm2BeforeDemand -le 0)
{
  "Error: vm1 or vm2 reported 0 memory (assigned or demand)."
  Stop-VM -VMName $vm2name -force
  return $False
}

"Memory stats after both $vm1Name and $vm2Name started reporting "
"  ${vm1Name}: assigned - $vm1BeforeAssigned | demand - $vm1BeforeDemand"
"  ${vm2Name}: assigned - $vm2BeforeAssigned | demand - $vm2BeforeDemand"

# get vm2 IP
$vm2ipv4 = GetIPv4 $vm2Name $hvServer

# wait for ssh to start on vm2 
$timeout = 30 #seconds
if (-not (WaitForVMToStartSSH $vm2ipv4 $timeout))
{
    "Error: VM ${vm2Name} never started ssh"
    Stop-VM -VMName $vm2name -force
    return $False
}

# Send Command to consume
$job1 = Start-Job -ScriptBlock { param($ip, $sshKey, $rootDir) ConsumeMemory $ip $sshKey $rootDir } -InitializationScript $scriptBlock -ArgumentList($ipv4,$sshKey,$rootDir)
if (-not $?)
{
  "Error: Unable to start job for creating pressure on $vm1Name"
  Stop-VM -VMName $vm2name -force
  return $false
}

# sleep a few seconds so all stresstestapp processes start and the memory assigned/demand gets updated
start-sleep -s 50
# get memory stats for vm1 after stresstestapp starts
[int64]$vm1Assigned = ($vm1.MemoryAssigned/1MB)
[int64]$vm1Demand = ($vm1.MemoryDemand/1MB)
[int64]$vm2Assigned = ($vm2.MemoryAssigned/1MB)
[int64]$vm2Demand = ($vm2.MemoryDemand/1MB)

"Memory stats after $vm1Name started stresstestapp"
"  ${vm1Name}: assigned - $vm1Assigned | demand - $vm1Demand"
"  ${vm2Name}: assigned - $vm2Assigned | demand - $vm2Demand"

if ($vm1Demand -le $vm1BeforeDemand -or $vm1Assigned -le $vm1BeforeAssigned)
{
  "Error: Memory Demand or Assignation on $vm1Name did not increase after starting stresstestapp"
  Stop-VM -VMName $vm2name -force
  return $false
}

if ($vm2Assigned -ge $vm2BeforeAssigned)
{
  "Error: Memory Demand on $vm2Name did not decrease after starting stresstestapp"
  Stop-VM -VMName $vm2name -force
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
      "Error: Consume Memory script returned false on VM1 $vm1Name"
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
  start-sleep -s 1

}

start-sleep -s 20


# if (-not $firstJobStatus)
# {
#   "Error: consume memory script did not finish in $totalTimeout seconds"
#   Stop-VM -VMName $vm2name -force
#   return $false
# }



# stop vm2
Stop-VM -VMName $vm2name -force

# Everything ok
"Success!"
return $true