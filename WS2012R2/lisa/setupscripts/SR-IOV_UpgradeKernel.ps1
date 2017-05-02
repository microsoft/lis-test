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
    Guest kernel update, SR-IOV should work without any interrupts

.Description
    Description:
    Perform a Linux kernel update. After the kernel update, SR-IOV should continue to work correctly.
    Steps:
        1. Configure SR-IOV on a Linux VM and confirm SR-IOV is working.
        2. Upgrade the Linux kernel.
        3. Reboot the VM
        3. Test SR-IOV functionality.

    Acceptance Criteria:
        After the upgrade, the SR-IOV device works correctly.
 
.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

.Example
    <test>
        <testName>Upgrade_Linux_Kernel</testName>
        <testScript>setupscripts\SR-IOV_UpgradeKernel.ps1</testScript>
        <files>remote-scripts/ica/utils.sh,remote-scripts/ica/SR-IOV_Utils.sh,remote-scripts/ica/SR-IOV_UpgradeKernel.sh</files> 
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
$kernelVersionOld = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "uname -r"
"Kernel version before upgrade: $kernelVersionOld" | Tee-Object -Append -file $summaryLog

#
# Test ping before upgrading the kernel
#
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "echo 'source constants.sh && ping -c 30 -I bond0 `$BOND_IP2 > PingResults.log &' > runPing.sh"
Start-Sleep -s 5
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "bash ~/runPing.sh > ~/Ping.log 2>&1"
Start-Sleep -s 10

[decimal]$beforeUpgradeRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"
if (-not $beforeUpgradeRTT){
    "ERROR: No result was logged before installing the kernel!" | Tee-Object -Append -file $summaryLog
    .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "ifconfig"
    return $false
}

"The RTT before upgrading the kernel is $beforeUpgradeRTT ms" | Tee-Object -Append -file $summaryLog
Start-Sleep -s 10

#
# Upgrade the kernel and reboot the VM after
#
$sts = RunRemoteScript "SR-IOV_UpgradeKernel.sh"
if (-not $sts[-1])
{
    "ERROR executing SR-IOV_UpgradeKernel.sh on VM. Exiting test case!" | Tee-Object -Append -file $summaryLog
    "ERROR: Running SR-IOV_UpgradeKernel.sh script failed on VM!"
    return $False
}
"Kernel was installed"

# Reboot VM
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "reboot"

Start-Sleep -s 30
$timeout = 200 # seconds
if (-not (WaitForVMToStartKVP $vmName $hvServer $timeout))
{
    "ERROR: $vmName never started KVP after reboot" | Tee-Object -Append -file $summaryLog
    return $False
}

# Check if the kernel was indeed upgraded
$kernelVersionNew = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "uname -r"
"Kernel version after upgrade: $kernelVersionNew" | Tee-Object -Append -file $summaryLog

if ($kernelVersionOld -eq $kernelVersionNew) {
    "ERROR: Kernel wasn't upgraded" | Tee-Object -Append -file $summaryLog
    return $False    
}

#
# Test ping after upgrading the kernel
#
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "echo 'source constants.sh && ping -c 30 -I bond0 `$BOND_IP2 > PingResults.log &' > runPing.sh"
Start-Sleep -s 5
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "bash ~/runPing.sh > ~/Ping.log 2>&1"
Start-Sleep -s 10

[decimal]$afterUpgradeRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"
if (-not $afterUpgradeRTT){
    "ERROR: No result was logged! Check if Ping was executed!" | Tee-Object -Append -file $summaryLog
    return $false
}

"The RTT after upgrading the kernel is $afterUpgradeRTT ms" | Tee-Object -Append -file $summaryLog
Start-Sleep -s 10

return $true