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
    Change RSS settings during iPerf

.Description
    While a Linux VM is transferring data via iPerf, change on of the RSS settings 
    for the vSwitch and confirm network traffic continues to flow.
    Steps:
        1.  Configure a Linux VM with SR-IOV, and a second VM with SR-IOV (Windows or Linux).
        2.  Start iPerf in server mode on the second VM.
        3.  On the Linux VM, start iPerf in client mode for about a 10 minute run.
        4.  Using Hyper-V manager, or a PowerShell cmdlet, change one of the RSS settings for the vSwitch.

.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

.Example
    <test>
        <testName>Change_RSS</testName>
        <testScript>setupscripts\SR-IOV_ChangeRSS.ps1</testScript>
        <files>remote-scripts/ica/utils.sh,remote-scripts/ica/SR-IOV_Utils.sh</files> 
        <setupScript>
            <file>setupscripts\RevertSnapshot.ps1</file>
            <file>setupscripts\SR-IOV_enable.ps1</file>
        </setupScript> 
        <noReboot>False</noReboot>
        <testParams>
            <param>NIC=NetworkAdapter,External,SRIOV,001600112200</param>
            <param>TC_COVERED=SRIOV-12</param>
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

#
# Run iPerf3 with SR-IOV enabled
#
# Start the client side
"Start Client"
.\bin\plink.exe -i ssh\$sshKey root@${vm2ipv4}  "iperf3 -s > client.out &"

"Start Server"
# Start iPerf3 testing
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "echo 'source constants.sh && iperf3 -t 600 -c `$BOND_IP2 --logfile PerfResults.log &' > runIperf.sh"
Start-Sleep -s 5
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "bash ~/runIperf.sh > ~/iPerf.log 2>&1"

# Wait 30 seconds and read the throughput
"Get Logs"
Start-Sleep -s 60
[decimal]$vfBeforeThroughput = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PerfResults.log | head -1 | awk '{print `$7}'"
if (-not $vfBeforeThroughput){
    "ERROR: No result was logged! Check if iPerf was executed!" | Tee-Object -Append -file $summaryLog
    return $false
}

"The throughput before changing the RSS profile is $vfBeforeThroughput Gbits/sec" | Tee-Object -Append -file $summaryLog
Start-Sleep -s 10

#
# Change RSS profile
#
# First, we'll save the current RSS profile
$rssProfile = Get-NetAdapterRss -Name "vEthernet (SRIOV)*"
$rssProfile = $rssProfile.Profile

"Changing RSS profile on VM1"
Set-NetAdapterRss -Name "vEthernet (SRIOV)*" -Profile ClosestStatic
if (-not $?) {
    "ERROR: Failed to change RSS profile for SRIOV interface!" | Tee-Object -Append -file $summaryLog
    Set-NetAdapterRss -Name "vEthernet (SRIOV)*" -Profile $rssProfile
    return $false 
}

# Check if bond is still up & running
Start-Sleep -s 30
$status = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "ifconfig | grep bond0"
if (-not $status) {
    "ERROR: The VF is down after changing RSS profile!" | Tee-Object -Append -file $summaryLog
    Set-NetAdapterRss -Name "vEthernet (SRIOV)*" -Profile $rssProfile
    return $false    
}

# Read the throughput with RSS profile changed
Start-Sleep -s 60
[decimal]$vfBeforeThroughput = $vfBeforeThroughput * 0.7
[decimal]$vfFinalThroughput = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PerfResults.log | head -1 | awk '{print `$7}'"

"The throughput after changing RSS profile is $vfFinalThroughput Gbits/sec" | Tee-Object -Append -file $summaryLog
if (-not $vfFinalThroughput) {
    "ERROR: After changing RSS profile, the throughput is significantly lower
    Please check if the VF is still running" | Tee-Object -Append -file $summaryLog
    Set-NetAdapterRss -Name "vEthernet (SRIOV)*" -Profile $rssProfile
    return $false 
}

# Check for Call Traces in VM system logs
Start-Sleep -s 60
$status = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "grep 'Call Trace' /var/log/* --exclude-dir=*"
if ($status) {
    "ERROR: System logs shows Call Traces. Please check the VM for further info" | Tee-Object -Append -file $summaryLog
    Set-NetAdapterRss -Name "vEthernet (SRIOV)*" -Profile $rssProfile
    return $false    
}
# Change back the RSS profile
Set-NetAdapterRss -Name "vEthernet (SRIOV)*" -Profile $rssProfile

return $true
