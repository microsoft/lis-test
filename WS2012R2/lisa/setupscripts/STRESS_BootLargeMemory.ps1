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
 Check if the VM is able to access all the memory assigned.

.Description
 Check if the VM is able to access more than 67700MB of RAM, in case a higher amount
 is assigned to it.

.Parameter vmName
 Name of the VM to test.

.Parameter hvServer
 Name of the Hyper-V server hosting the VM.

.Parameter testParams
 Test data for this test case.

.Example
 setupScripts\STRESS_BootLargeMemory -vmName myVM -hvServer localhost -testParams "vmName=vm;enableDM=no;startupMem=68GB;memWeight=100"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

# Read parameters
$params = $testParams.TrimEnd(";").Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")
    $value = $fields[1].Trim()

    switch ($fields[0].Trim()) {
        "sshKey"    { $sshKey  = $fields[1].Trim() }
        "ipv4"      { $ipv4    = $fields[1].Trim() }
        "rootDIR"   { $rootDir = $fields[1].Trim() }
        "TC_COVERED"    { $TC_COVERED = $fields[1].Trim() }
        "startupMem"    { $startupMem = $fields[1].Trim() }
        default     {}  # unknown param - just ignore it
    }
}

# Main script body

# Validate parameters
if (-not $vmName) {
    Write-Output "Error: VM name is null!"
    $retVal = $false
}

if (-not $hvServer) {
    Write-Output "Error: hvServer is null!"
    $retVal = $false
}

if (-not $testParams) {
    Write-Output"Error: No testParams provided!"
    $retVal = $false
}

# Change directory
cd $rootDir

# Source TCUtils.ps1
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
} else {
    "Error: Could not find setupScripts\TCUtils.ps1"
}

# Create log file
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#Define peak available memory in case of a problem. This value is the maximum value that a VM is able to
#access in case of MTRR problem. If the guest cannot access more memory than this value the MTRR problem occurs.
$peakFaultMem = [int]67700

#Get VM available memory
$guestReadableMem = bin\plink.exe -i .\ssh\$sshKey root@$ipv4 "free -m | grep Mem | xargs | cut -d ' ' -f 2"
if ($? -ne "True") {
    Write-Output "Error: Unable to send command to VM." | Tee-Object -Append -file $summaryLog
    return $Failed
}

$memInfo = bin\plink.exe -i .\ssh\$sshKey root@$ipv4 "cat /proc/meminfo | grep MemTotal | xargs | cut -d ' ' -f 2"
if ($? -ne "True") {
    Write-Output "Error: Unable to send command to VM." | Tee-Object -Append -file $summaryLog
    return $Failed
}
$memInfo = [math]::floor($memInfo/1024)

#Check if free binary and /proc/meminfo return the same value
if ($guestReadableMem -ne $memInfo) {
    Write-Output "Warning: free and proc/meminfo return different values" | Tee-Object -Append -file $summaryLog
}

if ($guestReadableMem -gt $peakFaultMem) {
	Write-Output "Info: VM is able to use all the assigned memory" | Tee-Object -Append -file $summaryLog
	return $Passed
} else {
	Write-Output "Error: VM cannot access all assigned memory." | Tee-Object -Append -file $summaryLog
	Write-Output "Assigned: $startupMem MB| VM addressable: $guestReadableMem MB" | Tee-Object -Append -file $summaryLog
	return $Failed
}
