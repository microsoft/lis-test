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
    Continuous iPerf, disable SR-IOV, enable SR-IOV

.Description
    Disable SR-IOV while transferring data of the device, then enable SR-IOV. 
    While disabled, the traffic should fallback to the synthetic device and throughput should drop. 
    Once SR-IOV is enabled again, traffic should handled by the SR-IOV device and throughput increase.
   
.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

.Example
    <test>
        <testName>iPerf_DisableVF</testName>
        <testScript>setupscripts\SR-IOV_iPerf_DisableVF.ps1</testScript>
        <files>remote-scripts/ica/utils.sh,remote-scripts/ica/SR-IOV_Utils.sh</files> 
        <setupScript>
            <file>setupscripts\RevertSnapshot.ps1</file>
            <file>setupscripts\SR-IOV_enable.ps1</file>
        </setupScript> 
        <noReboot>False</noReboot>
        <testParams>
            <param>NIC=NetworkAdapter,External,SRIOV,001600112200</param>
            <param>TC_COVERED=SRIOV-8</param>
            <param>BOND_IP1=10.11.12.31</param>
            <param>BOND_IP2=10.11.12.32</param>
            <param>NETMASK=255.255.255.0</param>
            <param>REMOTE_SERVER=remoteHostName</param>
        </testParams>
        <timeout>1800</timeout>
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

#
# Reboot VM
#
Restart-VM -VMName $vmName -ComputerName $hvServer -Force
$sts = WaitForVMToStartSSH $ipv4 200
if( -not $sts[-1]){
    "ERROR: VM $vmName has not booted after the restart" | Tee-Object -Append -file $summaryLog
    return $false    
}

# Get IPs
Start-Sleep -s 5
$ipv4 = GetIPv4 $vmName $hvServer
"${vmName} IP Address: ${ipv4}"

#
# Run Ping with SR-IOV enabled
#
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "echo 'source constants.sh && ping -c 600 -I bond0 `$BOND_IP2 > PingResults.log &' > runPing.sh"
Start-Sleep -s 5
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "bash ~/runPing.sh > ~/Ping.log 2>&1"

# Wait 60 seconds and read the RTT
"Get Logs"
Start-Sleep -s 15
[decimal]$initialRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"
if (-not $initialRTT){
    "ERROR: No result was logged! Check if Ping was executed!" | Tee-Object -Append -file $summaryLog
    return $false
}

"The RTT before switching the SR-IOV NIC is $initialRTT ms" | Tee-Object -Append -file $summaryLog

#
# Switch SR-IOV NIC to a non-SRIOV NIC
#
# Get the NIC
$nicInfo = Get-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer | Where-Object {$_.SwitchName -like 'SRIOV*'}
$sriovSwitch = $nicInfo.SwitchName

# Connect a non-SRIOV vSwitch. We will use the samech as the management NIC
[string]$managementSwitch = Get-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer | Select-Object -First 1 | Select -ExpandProperty SwitchName
Connect-VMNetworkAdapter -VMNetworkAdapter $nicInfo -SwitchName $managementSwitch -Confirm:$False
if (-not $?) {
    "ERROR: Failed to switch the NIC!" | Tee-Object -Append -file $summaryLog
    return $false 
}
Start-Sleep -s 10

# Check if the  SR-IOV module is still loaded
.\bin\plink.exe -i .\ssh\$sshKey root@${ipv4} "lspci -vvv | grep 'mlx4_core\|ixgbevf'"
if ($?) {
    "ERROR: SR-IOV module is still loaded on the VM after the NIC switch!" | Tee-Object -Append -file $summaryLog
    return $false 
}

# Check if the VF is available in sys/class/net
.\bin\plink.exe -i .\ssh\$sshKey root@${ipv4} "ls /sys/class/net | grep -v 'eth0\|eth1\|lo\|bond*'"
if ($?) {
    "ERROR: VF is still available in sys/class/net " | Tee-Object -Append -file $summaryLog
    return $false 
}
else {
    "VF is no longer present in the VM after deattaching the SR-IOV vSwitch " | Tee-Object -Append -file $summaryLog  
}

#
# Switch non-SR-IOV NIC back to a SRIOV NIC
#
# Connect to the initial SRIOV vSwitch
Connect-VMNetworkAdapter -VMNetworkAdapter $nicInfo -SwitchName $sriovSwitch -Confirm:$False

Start-Sleep -s 15
# Read the RTT again, it should be simillar to the initial read
[decimal]$initialRTT = $initialRTT * 1.7
[decimal]$finalRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"

"The RTT after attaching SR-IOV vSwitch again is $finalRTT ms" | Tee-Object -Append -file $summaryLog
if ($finalRTT -gt $initialRTT) {
    "ERROR: After re-enabling SR-IOV, the RTT value has not lowered enough
    Please check if the VF was successfully restarted" | Tee-Object -Append -file $summaryLog
    return $false 
}

return $true