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
    Continuous iPerf, disable SR-IOV NIC then enable SR-IOV NIC

.Description
    Disable SR-IOV NIC from host while transferring data of the device
    While disabled, the traffic should fallback to the synthetic device and 
    throughput should drop. Once SR-IOV NIC is enabled again, traffic
    should be handled by the SR-IOV device and throughput should increase.

.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

.Example
    <test>
        <testName>DisableNIC</testName>
        <testScript>setupscripts\SR-IOV_DisableNIC.ps1</testScript>
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
# Install iPerf3 on VM1
#
"Installing iPerf3 on ${vmName}"
$retval = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "dos2unix SR-IOV_Utils.sh && source SR-IOV_Utils.sh && InstallDependencies"
if (-not $retVal)
{
    "ERROR: Failed to install iPerf3 on vm $vmName (IP: ${ipv4})"
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
# Start iPerf3 on both VMs
#
# Start the client side
"Start Client"
.\bin\plink.exe -i ssh\$sshKey root@${vm2ipv4}  "kill `$(ps aux | grep iperf | head -1 | awk '{print `$2}')"
.\bin\plink.exe -i ssh\$sshKey root@${vm2ipv4}  "iperf3 -s > client.out &"

"Start Server"
# Start iPerf3 testing
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "echo 'source constants.sh && iperf3 -t 1800 -c `$BOND_IP2 --logfile PerfResults.log &' > runIperf.sh"
Start-Sleep -s 5
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "bash ~/runIperf.sh > ~/iPerf.log 2>&1"

# Wait 30 seconds and read the throughput
Start-Sleep -s 30
[decimal]$vfInitialThroughput = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PerfResults.log | head -1 | awk '{print `$7}'"
if (-not $vfInitialThroughput){
    "ERROR: No result was logged! Check if iPerf was executed!" | Tee-Object -Append -file $summaryLog
    return $false
}

"The throughput before starting the stress test is $vfInitialThroughput Gbits/sec" | Tee-Object -Append -file $summaryLog

# Get 70% of the initial throughput
[decimal]$vfInitialThroughput = $vfInitialThroughput * 0.7
"Values under $vfInitialThroughput Gbits/sec will end this test with a failure"
Start-Sleep -s 10

#
# Disable SR-IOV from host side
#
# Get the physical NIC description
$switchName = Get-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer | Where-Object {$_.SwitchName -like 'SRIOV*'} | Select -ExpandProperty SwitchName
$hostNIC_name = Get-VMSwitch -Name $switchName | Select -ExpandProperty NetAdapterInterfaceDescription

"Disabling $hostNIC_name NIC on $hvServer"
Disable-NetAdapter -InterfaceDescription $hostNIC_name -Confirm:$False
if (-not $?) {
    "ERROR: Failed to disable SR-IOV on $hostNIC_name!" | Tee-Object -Append -file $summaryLog
    return $false 
}

# Check if module and VF device are still in use
Start-Sleep -s 10
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "lspci -vvv | grep -e ixgbevf -e mlx4_core"
if ($?) {
    "ERROR: The VF module is still in use!" | Tee-Object -Append -file $summaryLog
    return $false 
}

.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "ls /sys/class/net/ | grep -v 'eth0\|eth1\|bond*\|lo'"
if ($?) {
    "ERROR: The VF device is still showing up in /sys/class/net!" | Tee-Object -Append -file $summaryLog
    return $false 
}

#
# Enable SR-IOV on both VMs
#
"Enabling $hostNIC_name NIC on $hvServer"
Enable-NetAdapter -InterfaceDescription $hostNIC_name
if (-not $?) {
    "ERROR: Failed to enable SR-IOV on $hostNIC_name! Please try to manually enable it" | Tee-Object -Append -file $summaryLog
    return $false 
}

Start-Sleep -s 20

# Read the throughput again, it should be higher than before
# We should see a throughput at least 70% higher
[decimal]$vfFinalThroughput = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PerfResults.log | head -1 | awk '{print `$7}'"

"The throughput after re-enabling SR-IOV is $vfFinalThroughput Gbits/sec" | Tee-Object -Append -file $summaryLog
if ($vfFinalThroughput -lt  $vfInitialThroughput) {
    "ERROR: After re-enabling SR-IOV, the throughput has not increased enough 
    Please check if the VF was successfully restarted" | Tee-Object -Append -file $summaryLog
    return $false 
}

return $true