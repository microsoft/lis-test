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
    Verify runtime memory hot add feature with Dynamic Memory disabled.

 Description:
    Verify that memory changes with non 128-MB aligned values. This test will
    start a vm with 4000 MB and will hot add 1000 MB to it. After that, will
    reboot the vm and hot add another 1000 MB. Test will pass if all hot add
    operations work.

    Only 1 VM is required for this test.

    .Parameter vmName
    Name of the VM to hot add memory to.

    .Parameter hvServer
    Name of the Hyper-V server hosting the VM.

    .Parameter testParams
    Test data for this test case

    .Example
    setupscripts\Runtime_Mem_HotAdd_reboot.ps1 -vmName nameOfVM -hvServer localhost -testParams
    'sshKey=KEY;ipv4=IPAddress;rootDir=path\to\dir; startupMem=4000MB'
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
if ($vmName -eq $null) {
    "Error: VM name is null"
    return $False
}

if ($hvServer -eq $null) {
    "Error: hvServer is null"
    return $False
}

if ($testParams -eq $null) {
    "Error: testParams is null"
    return $False
}

# Write out test Params
$testParams

# sshKey used to authenticate ssh connection and send commands
$sshKey = $null

# IP Address of first VM
$ipv4 = $null

# change working directory to root dir
$testParams -match "RootDir=([^;]+)"
if (-not $?) {
  "Mandatory param RootDir=Path; not found!"
  return $false
}
$rootDir = $Matches[1]

if (Test-Path $rootDir) {
  Set-Location -Path $rootDir
  if (-not $?) {
    "Error: Could not change directory to $rootDir !"
    return $false
  }
  "Changed working directory to $rootDir"
}
else{
  "Error: RootDir = $rootDir is not a valid path"
  return $false
}

# Source TCUtils.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
  . .\setupScripts\TCUtils.ps1
}
else {
  "Error: Could not find setupScripts\TCUtils.ps1"
  return $false
}

$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")

    switch ($fields[0].Trim()) {
      "TC_COVERED"    { $TC_COVERED = $fields[1].Trim() }
      "ipv4"          { $ipv4       = $fields[1].Trim() }
      "sshKey"        { $sshKey     = $fields[1].Trim() }
      "startupMem"  {
        $startupMem = ConvertToMemSize $fields[1].Trim() $hvServer

        if ($startupMem -le 0) {
          "Error: Unable to convert startupMem to int64."
          return $false
        }
        "startupMem: $startupMem"
      }
    }
}

if (-not $sshKey) {
  "Error: Please pass the sshKey to the script."
  return $false
}

if (-not $startupMem) {
  "Error: startupMem is not set!"
  return $false
}

# Delete any previous summary.log file
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue

Write-output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Skip the test if host is lower than WS2016
$BuildNumber = GetHostBuildNumber $hvServer
if ($BuildNumber -eq 0) {
    return $False
}
elseif ($BuildNumber -lt 10500) {
    "Info: Feature supported only on WS2016 and newer" | Tee-Object -Append -file $summaryLog
    return $Skipped
}

$vm1 = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue

if (-not $vm1) {
  "Error: VM $vmName does not exist"
  return $false
}

# Get memory stats from vm1
start-sleep -s 60
$sleepPeriod = 60

# Get VM1 memory from host and guest
[int64]$vm1BeforeAssigned = ($vm1.MemoryAssigned/1MB)
[int64]$vm1BeforeDemand = ($vm1.MemoryDemand/1MB)
[int64]$vm1BeforeIncrease = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "cat /proc/meminfo | grep -i MemFree | awk '{ print `$2 }'"
"Free memory reported by guest VM before increase: $vm1BeforeIncrease"

# Check memory values
if ($vm1BeforeAssigned -le 0 -or $vm1BeforeDemand -le 0 -or $vm1BeforeIncrease -le 0) {
  "Error: vm1 $vmName reported 0 memory (assigned or demand)."
  return $False
}
"Memory stats after $vmName started reporting "
"  ${vmName}: assigned - $vm1BeforeAssigned | demand - $vm1BeforeDemand"

# Change 1 - Increase
$testMem = $startupMem + 1048576000

# Set new memory value
for ($i=0; $i -lt 3; $i++) {
  Set-VMMemory -VMName $vmName  -ComputerName $hvServer -DynamicMemoryEnabled $false -StartupBytes $testMem
  if ($? -eq $false){
     "Error: Set-VMMemory as $($testMem/1MB) MB failed" | Tee-Object -Append -file $summaryLog
      return $false
  }
  Start-sleep -s 5
  if ($vm1.MemoryAssigned -eq $testMem) {
    [int64]$vm1AfterAssigned = ($vm1.MemoryAssigned/1MB)
    [int64]$vm1AfterDemand = ($vm1.MemoryDemand/1MB)

    [int64]$vm1AfterIncrease = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "cat /proc/meminfo | grep -i MemFree | awk '{ print `$2 }'"
    "Free memory reported by guest VM after first 1000MB increase: $vm1AfterIncrease KB"
    break
  }
}

if ( $i -eq 3 ) {
  "Error: VM failed to change memory!"
  "LIS 4.1 or kernel version 4.4 required"
  return $false
}

if ( $vm1AfterAssigned -ne ($testMem/1MB)  ) {
    "Error: Memory assigned doesn't match the memory set as parameter!"
    "Memory stats after $vmName memory was changed "
    "  ${vmName}: assigned - $vm1AfterAssigned | demand - $vm1AfterDemand"
    return $false
}

if ( ($vm1AfterIncrease - $vm1BeforeIncrease) -le 700000) {
    "Error: Guest reports that memory value hasn't increased enough!"
    "Memory stats after $vmName memory was changed "
    "  ${vmName}: Initial Memory - $vm1BeforeIncrease KB :: After setting new value - $vm1AfterIncrease"
    return $false
}
"Memory stats after $vmName memory was increased by 1000MB"
"  ${vmName}: assigned - $vm1AfterAssigned | demand - $vm1AfterDemand"

# Restart VM
Restart-VM -VMName $vmName -ComputerName $hvServer -Force
$sts = WaitForVMToStartKVP $vmName $hvServer 120
if( -not $sts[-1]) {
    Write-Output "Error: VM $vmName has not booted after the restart" `
        | Tee-Object -Append -file $summaryLog
    return $False
}
"$vmName rebooted successfully! Next, we'll try to add another 1000MB of memory"

# Increase memory again after reboot
Start-sleep -s 60
$testMem = $testMem + 1048576000

# Set new memory value
for ($i=0; $i -lt 3; $i++) {
  Set-VMMemory -VMName $vmName  -ComputerName $hvServer -DynamicMemoryEnabled $false -StartupBytes $testMem
  Start-sleep -s 5
  if ($vm1.MemoryAssigned -eq $testMem) {
    [int64]$vm1AfterAssigned = ($vm1.MemoryAssigned/1MB)
    [int64]$vm1AfterDemand = ($vm1.MemoryDemand/1MB)

    [int64]$vm1AfterDecrease = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "cat /proc/meminfo | grep -i MemFree | awk '{ print `$2 }'"
    "Free memory reported by guest VM after second 1000MB increase: $vm1AfterDecrease KB"
    break
  }
}

if ( $i -eq 3 ) {
  "Error: VM failed to change memory!"
  bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dmesg | grep hot_add"
  return $false
}

"Memory stats after $vmName memory was increased with 1000MB"
"  ${vmName}: assigned - $vm1AfterAssigned | demand - $vm1AfterDemand"

"Info: VM memory changed successfully!"
return $true
