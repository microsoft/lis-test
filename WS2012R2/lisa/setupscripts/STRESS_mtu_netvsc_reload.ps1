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
    MTU & netvsc reload test

.Parameter vmName
    Name of the VM to test.

.Parameter hvServer
    Name of the Hyper-v server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.

.Example
    .\STRESS_mtu_netvsc_reload.ps1 "testVM" "localhost" "rootDir=D:\Lisa"
#>

param ([String] $vmName, [String] $hvServer, [String] $testParams)
##############################################################################
#
# Main script body
#
##############################################################################

if ($hvServer -eq $null) {
    "ERROR: hvServer is null"
    return $False
}

if ($testParams -eq $null) {
    "ERROR: testParams is null"
    return $False
}

# Change working directory to root dir
$testParams -match "RootDir=([^;]+)"
if (-not $?) {
    "Mandatory param RootDir=Path; not found!"
    return $false
}
$rootDir = $Matches[1]

if (Test-Path $rootDir) {
    Set-Location -Path $rootDir

    if (-not $?) {
        "ERROR: Could not change directory to $rootDir !"
        return $false
    }
    "Changed working directory to $rootDir"
}
else {
    "ERROR: RootDir = $rootDir is not a valid path"
    return $false
}

# Source TCUtils.ps1
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
}
else {
    "ERROR: Could not find setupScripts\TCUtils.ps1"
    return $false
}

# Source NET_UTILS.ps1
if (Test-Path ".\setupScripts\NET_UTILS.ps1") {
    . .\setupScripts\NET_UTILS.ps1
}
else {
    "ERROR: Could not find setupScripts\NET_Utils.ps1"
    return $false
}

# Process the test params
$params = $testParams.Split(';')
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {
        "SshKey" { $sshKey = $fields[1].Trim() }
        "ipv4" { $ipv4 = $fields[1].Trim() }   
        "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    }
}

$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

"${vmName} IP Address: ${ipv4}"

# Start changing MTU on VM
$mtu_values = 1505, 2048, 4096, 8192, 16384
$iteration = 1
foreach ($i in $mtu_values) {
    Write-Output "Changing MTU on VM to $i"

    $sts = .\bin\plink.exe -v -i ssh\$sshKey root@${ipv4} "echo 'sleep 5 && ip link set dev eth0 mtu $i &' > changeMTU.sh"
    $sts = .\bin\plink.exe -v -i ssh\$sshKey root@${ipv4} "bash ~/changeMTU.sh > changeMTU.log 2>&1"

    Start-Sleep -s 30
    Test-Connection -ComputerName $ipv4
    if (-not $?) {
        Write-Output "VM became unresponsive after changing MTU on VM to $i on iteration $iteration " | Tee-Object -Append -file $summaryLog
        return $false
    }
    $iteration++
}
Write-Output "Successfully changed MTU for $iteration times" | Tee-Object -Append -file $summaryLog

# Start unloading/loading netvsc for 25 times
$reloadCommand = @'
#!/bin/bash

pass=0
while [ $pass -lt 25 ]
do
    modprobe -r hv_netvsc
    sleep 1
    modprobe hv_netvsc
    sleep 1
    pass=$((pass+1))
    echo $pass > reload_netvsc.log
done
ifdown eth0 && ifup eth0
'@

# Check for file
if (Test-Path ".\reload_netvsc.sh") {
    Remove-Item ".\reload_netvsc.sh"
}

Add-Content "reload_netvsc.sh" "$reloadCommand"
$retVal = SendFileToVM $ipv4 $sshKey reload_netvsc.sh "/root/reload_netvsc.sh"
$sts = .\bin\plink.exe -v -i ssh\$sshKey root@${ipv4} "dos2unix reload_netvsc.sh && echo 'sleep 5 && bash ~/reload_netvsc.sh &' > runtest.sh"
$sts = .\bin\plink.exe -v -i ssh\$sshKey root@${ipv4} "bash ~/runtest.sh > reload_netvsc.log 2>&1"

Start-Sleep -s 600
$ipv4 = GetIPv4 $vmName $hvServer
"${vmName} IP Address after reloading hv_netvsc: ${ipv4}"

Test-Connection -ComputerName $ipv4
if (-not $?) {
    Write-Output "Error: VM became unresponsive after reloading hv_netvsc" | Tee-Object -Append -file $summaryLog
    return $false
}
else {
    Write-Output "Successfully reloaded hv_netvsc for 25 times" | Tee-Object -Append -file $summaryLog
    return $True
}
