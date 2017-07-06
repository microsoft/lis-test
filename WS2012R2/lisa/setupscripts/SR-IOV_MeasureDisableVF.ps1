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
    Continuous iPerf, disable SR-IOV, enable SR-IOV and measure time to switch

.Description
    Disable SR-IOV while transferring data of the device, then enable SR-IOV. 
    For both operations, measure time between the switch.
    If the time is bigger than 10 seconds, fail the test
   
.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

.Example
    <test>
        <testName>Measure_DisableVF</testName>
        <testScript>setupscripts\SR-IOV_MeasureDisableVF.ps1</testScript>
        <files>remote-scripts/ica/utils.sh,remote-scripts/ica/SR-IOV_Utils.sh</files> 
        <setupScript>
            <file>setupscripts\RevertSnapshot.ps1</file>
            <file>setupscripts\SR-IOV_enable.ps1</file>
        </setupScript> 
        <noReboot>False</noReboot>
        <testParams>
            <param>NIC=NetworkAdapter,External,SRIOV,001600112800</param>
            <param>TC_COVERED=SRIOV-7</param>
            <param>BOND_IP1=10.11.12.31</param>
            <param>BOND_IP2=10.11.12.32</param>
            <param>NETMASK=255.255.255.0</param>
            <param>REMOTE_SERVER=remoteHost</param>
        </testParams>
        <cleanupScript>setupscripts\SR-IOV_ShutDown_Dependency.ps1</cleanupScript>
        <timeout>2400</timeout>
    </test>
#>

param ([String] $vmName, [String] $hvServer, [string] $testParams)

#############################################################
#
# Main script body
#
#############################################################
$retVal = $False
$leaveTrail = "no"

#
# Check the required input args are present
#

# Write out test Params
$testParams


if ($hvServer -eq $null)
{
    "ERROR: hvServer is null"
    return $False
}

if ($testParams -eq $null)
{
    "ERROR: testParams is null"
    return $False
}

#change working directory to root dir
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
        "ERROR: Could not change directory to $rootDir !"
        return $false
    }
    "Changed working directory to $rootDir"
}
else
{
    "ERROR: RootDir = $rootDir is not a valid path"
    return $false
}

# Source TCUitls.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1")
{
    . .\setupScripts\TCUtils.ps1
}
else
{
    "ERROR: Could not find setupScripts\TCUtils.ps1"
    return $false
}

# Source NET_UTILS.ps1 for network functions
if (Test-Path ".\setupScripts\NET_UTILS.ps1")
{
    . .\setupScripts\NET_UTILS.ps1
}
else
{
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
        "BOND_IP1" { $vmBondIP1 = $fields[1].Trim() }
        "BOND_IP2" { $vmBondIP2 = $fields[1].Trim() }
        "NETMASK" { $netmask = $fields[1].Trim() }
        "VM2NAME" { $vm2Name = $fields[1].Trim() }
        "REMOTE_SERVER" { $remoteServer = $fields[1].Trim()}
        "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    }
}

$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Get IPs
$ipv4 = GetIPv4 $vmName $hvServer
"${vmName} IPADDRESS: ${ipv4}"
$vm2ipv4 = GetIPv4 $vm2Name $remoteServer
"${vm2Name} IPADDRESS: ${vm2ipv4}"

#
# Configure the bond on test VM
#
$retVal = ConfigureBond $ipv4 $sshKey $netmask
if (-not $retVal)
{
    "ERROR: Failed to configure bond on vm $vmName (IP: ${ipv4}), by setting a static IP of $vmBondIP1 , netmask $netmask"
    return $false
}
Start-Sleep -s 5
# Verify distro VM. If it's RHEL/CentOS no reboot is needed
$sts = SendCommandToVM $ipv4 $sshKey "cat /etc/redhat-release"
if (-not $sts[-1]){
    # Reboot VM
    Restart-VM -VMName $vmName -ComputerName $hvServer -Force
    $sts = WaitForVMToStartSSH $ipv4 200
    if( -not $sts[-1]){
        "ERROR: VM $vmName has not booted after the restart" | Tee-Object -Append -file $summaryLog
        return $false    
    }

    # Get IPs
    Start-Sleep -s 5
    $ipv4 = GetIPv4 $vmName $hvServer
    "${vmName} IP Address after reboot: ${ipv4}"
}

#
# Start ping
#
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "echo 'source constants.sh && ping -c 1200 -I bond0 `$BOND_IP2 > PingResults.log &' > runPing.sh"
Start-Sleep -s 5
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "bash ~/runPing.sh > ~/Ping.log 2>&1"
Start-Sleep -s 10

[decimal]$initialRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"
if (-not $initialRTT){
    "ERROR: No result was logged! Check if bond is up!" | Tee-Object -Append -file $summaryLog
    .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "ifconfig"
    return $false
}
"The RTT before disabling VF is $initialRTT ms" | Tee-Object -Append -file $summaryLog

# We add 0.4 ms to the initial RTT to future determine if the data is transmitted through VF or netvsc
[decimal]$initialRTT = $initialRTT + 0.03
#
# Disable SR-IOV on test VM
#
"Disabling VF on vm1"
Set-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer -IovWeight 0
if (-not $?) {
    "ERROR: Failed to disable SR-IOV on $vmName!" | Tee-Object -Append -file $summaryLog
    return $false 
}

# icmp seq
[int]$initial_icmpSeq = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -1 PingResults.log | head -1 | awk '{print `$5}' | sed 's/=/ /' | awk '{print `$2}'"

# Read the throughput with SR-IOV disabled; it should be lower
$timeToRun = 0
$hasSwitched = $false
while ($hasSwitched -eq $false){ 
    [decimal]$disabledRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -1 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"
    [int]$disabled_icmpSeq = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -1 PingResults.log | head -1 | awk '{print `$5}' | sed 's/=/ /' | awk '{print `$2}'"
    if (($disabledRTT -ge $initialRTT) -and ($disabled_icmpSeq -ne $initial_icmpSeq)) {
        $hasSwitched = $true
    }

    $timeToRun++
    if ($timeToRun -ge 100) {
        "ERROR: The switch beteen VF and netvsc was not made. RTT values show that traffic goes through VF!" | Tee-Object -Append -file $summaryLog
        return $false 
    }

    if ($hasSwitched -eq $false){
        Start-Sleep -s 1
    }
}
[int]$timetoSwitch = $disabled_icmpSeq - $initial_icmpSeq
if ($timetoSwitch -gt 10) {
    "ERROR: After disabling VF, $timetoSwitch seconds passed until Ping worked again. Time is too big" | Tee-Object -Append -file $summaryLog
    return $false
}

Start-Sleep -s 5
"After disabling VF, $timetoSwitch seconds passed until Ping worked again. RTT value is $disabledRTT" | Tee-Object -Append -file $summaryLog

#
# Read icmp seq value & enable SR-IOV on test VM
#
Start-Sleep -s 10

"Enable VF on vm1"
Set-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer -IovWeight 1
if (-not $?) {
    "ERROR: Failed to enable SR-IOV on $vmName!" | Tee-Object -Append -file $summaryLog
    return $false 
}

# icmp seq
[int]$initial_icmpSeq_2 = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -1 PingResults.log | head -1 | awk '{print `$5}' | sed 's/=/ /' | awk '{print `$2}'"

# Read the throughput with SR-IOV disabled; it should be lower
$timeToRun = 0
$hasSwitched = $false
while ($hasSwitched -eq $false){ 
    [decimal]$enabledRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -1 PingResults.log | head -2 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"
    [int]$enabled_icmpSeq = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -1 PingResults.log | head -2 | awk '{print `$5}' | sed 's/=/ /' | awk '{print `$2}'"
    if (($enabledRTT -le $initialRTT) -and ($enabled_icmpSeq -ne $initial_icmpSeq_2)){
        $hasSwitched = $true
        $timetoSwitch = $enabled_icmpSeq - $initial_icmpSeq_2
        "After enabling VF, $timetoSwitch seconds passed until Ping worked again. RTT value is $enabledRTT ms " | Tee-Object -Append -file $summaryLog
    }

    $timeToRun++
    if ($timeToRun -ge 100) {
        $hasSwitched = $true
    }

    if ($hasSwitched -eq $false){
        Start-Sleep -s 1
    }
}

[int]$timetoSwitch = $enabled_icmpSeq - $initial_icmpSeq_2 
if ($timetoSwitch -gt 10) {
    "ERROR: After enabling VF, $timetoSwitch seconds passed until Ping worked again. Time is too big" | Tee-Object -Append -file $summaryLog
    return $false
}

Start-Sleep -s 3
"After enabling VF, $timetoSwitch seconds passed until Ping worked again. RTT value is $enabledRTT" | Tee-Object -Append -file $summaryLog

return $true