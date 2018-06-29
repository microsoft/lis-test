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
            <param>VF_IP1=10.11.12.31</param>
            <param>VF_IP2=10.11.12.32</param>
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
        "VF_IP1" { $vmVF_IP1 = $fields[1].Trim() }
        "VF_IP2" { $vmVF_IP2 = $fields[1].Trim() }
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

if ($remoteServer -eq $null)
{
    $remoteServer = $hvServer
}

$vm2ipv4 = GetIPv4 $vm2Name $remoteServer
"${vm2Name} IPADDRESS: ${vm2ipv4}"

#
# Configure the eth1 on test VM
#
Start-Sleep -s 5
$retVal = ConfigureVF $ipv4 $sshKey $netmask
if (-not $retVal)
{
    "ERROR: Failed to configure eth1 on vm $vmName (IP: ${ipv4}), by setting a static IP of $vmVF_IP1 , netmask $netmask"
    return $false
}
Start-Sleep -s 10

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

#
# Start iPerf3 on both VMs
#
# Start the client side
"Start Client"
.\bin\plink.exe -i ssh\$sshKey root@${vm2ipv4}  "kill `$(ps aux | grep iperf | head -1 | awk '{print `$2}')"
.\bin\plink.exe -i ssh\$sshKey root@${vm2ipv4} "iperf3 -s > client.out &"

"Start Server"
# Start iPerf3 testing
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "echo 'source constants.sh && iperf3 -t 1800 -c `$VF_IP2 --logfile PerfResults.log &' > runIperf.sh"
Start-Sleep -s 5
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "bash ~/runIperf.sh > ~/iPerf.log 2>&1"

# Wait 30 seconds and read the throughput
Start-Sleep -s 30
[decimal]$vfInitialThroughput = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PerfResults.log | head -1 | awk '{print `$7}'"
if (-not $vfInitialThroughput){
    "ERROR: No result was logged! Check if iPerf was executed!" | Tee-Object -Append -file $summaryLog
    return $false
}

#"The throughput before starting the stress test is $vfInitialThroughput Gbits/sec" | Tee-Object -Append -file $summaryLog

Start-Sleep -s 10

#
# Disable SR-IOV from host side
#
# Get the physical NIC description
$switchName = Get-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer | Where-Object {$_.SwitchName -like 'SRIOV*'} | Select -ExpandProperty SwitchName
$hostNIC_name = Get-VMSwitch -Name $switchName -ComputerName $hvServer| Select -ExpandProperty NetAdapterInterfaceDescription

"Disabling VF on $hostNIC_name"
Disable-NetAdapterSriov -InterfaceDescription $hostNIC_name -CIMsession $hvServer
if (-not $?) {
    "ERROR: Failed to disable SR-IOV on $hostNIC_name!" | Tee-Object -Append -file $summaryLog
    return $false
}

# Read the throughput with SR-IOV disabled; it should be lower
Start-Sleep -s 80
[decimal]$vfDisabledThroughput = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PerfResults.log | head -1 | awk '{print `$7}'"
if (-not $vfDisabledThroughput){
    "ERROR: No result was logged after SR-IOV was disabled!" | Tee-Object -Append -file $summaryLog
    Enable-NetAdapterSriov -InterfaceDescription $hostNIC_name -CIMsession $hvServer
    return $false
}

"The throughput with SR-IOV disabled is $vfDisabledThroughput Gbits/sec" | Tee-Object -Append -file $summaryLog
if ($vfDisabledThroughput -ge $vfInitialThroughput) {
    "ERROR: The throughput was higher with SR-IOV disabled, it should be lower" | Tee-Object -Append -file $summaryLog
    Enable-NetAdapterSriov -InterfaceDescription $hostNIC_name -CIMsession $hvServer
    return $false
}
Start-Sleep -s 10

#
# Enable SR-IOV on both VMs
#
"Enable VF on vm1"
Enable-NetAdapterSriov -InterfaceDescription $hostNIC_name -CIMsession $hvServer
if (-not $?) {
    "ERROR: Failed to enable SR-IOV on $hostNIC_name! Please try to manually enable it" | Tee-Object -Append -file $summaryLog
    return $false
}

Start-Sleep -s 70

# Read the throughput again, it should be higher than before
# We should see a throughput at least 70% higher
# Get 70% of the initial throughput
[decimal]$vfInitialThroughput = $vfInitialThroughput * 0.7
"Values under $vfInitialThroughput Gbits/sec will end this test with a failure"

[decimal]$vfFinalThroughput = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PerfResults.log | head -1 | awk '{print `$7}'"

"The throughput after re-enabling SR-IOV is $vfFinalThroughput Gbits/sec" | Tee-Object -Append -file $summaryLog
if ($vfFinalThroughput -lt  $vfInitialThroughput) {
    "ERROR: After re-enabling SR-IOV, the throughput has not increased enough
    Please check if the VF was successfully restarted" | Tee-Object -Append -file $summaryLog
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
return $true
