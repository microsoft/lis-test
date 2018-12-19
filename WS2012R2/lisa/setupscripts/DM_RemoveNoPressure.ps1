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
 Verify that a VM's assigned memory could decrease when no pressure available.

 Description:
    Verify that a VM's assigned memory could decrease when no pressure available but higher than minimum memory.
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

$vm1 = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue

# Get VM1's minimum memory setting
[int64]$vm1MinMem = ($vm1.MemoryMinimum/1MB)
"Info: Minimum memory for $vmName is $vm1MinMem MB"

$sleepPeriod = 120 #seconds

# Get VM1's memory
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

"Info: Memory stats after $vmName just boots up"
"  ${vmName}: assigned - $vm1BeforeAssigned | demand - $vm1BeforeDemand"

$sleepPeriod = 0 #seconds

# Get VM1's memory again
while ($sleepPeriod -lt 420){
    [int64]$vm1AfterAssigned = ($vm1.MemoryAssigned/1MB)
    [int64]$vm1AfterDemand = ($vm1.MemoryDemand/1MB)
    if ( $vm1AfterAssigned -lt $vm1BeforeAssigned){
        break
    }
    $sleepPeriod+= 5
    Start-Sleep -s 5
}

"Info: Memory stats after ${vmName} sleeps $sleepPeriod seconds"
"  ${vmName}: assigned - $vm1AfterAssigned | demand - $vm1AfterDemand"

# Verify assigned memory and demand decrease after sleep less than 7 minutes
if ($vm1AfterAssigned -ge $vm1BeforeAssigned -or $vm1AfterDemand -ge $vm1BeforeDemand ){
    "Error: ${vmName} assigned or demand memory does not decrease after sleep $sleepPeriod seconds" | Tee-Object -Append -file $summaryLog
    return $False
}
else{
    "Info: ${vmName} assigned and demand memory decreases after sleep $sleepPeriod seconds"
}

# Verify assigned memory does not drop below minimum memory
if ($vm1AfterAssigned -lt $vm1MinMem){
    "Error: $vm1Name assigned memory drops below minimum memory set, $vm1MinMem MB" | Tee-Object -Append -file $summaryLog
    return $false
}

# Wait 2 minutes and check call traces
$retVal = CheckCallTracesWithDelay $sshKey $ipv4
if (-not $retVal) {
    Write-Output "ERROR: Call traces have been found on VM after the test run" | Tee-Object -Append -file $summaryLog
    return $false
} else {
    Write-Output "Info: No Call Traces have been found on VM" | Tee-Object -Append -file $summaryLog
}

return $True
