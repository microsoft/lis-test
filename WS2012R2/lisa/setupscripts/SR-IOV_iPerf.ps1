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
    Run single thread iperf, confirm throughput enhancement.

.Description
    a. Install the iPerf benchmark utility
    b. Configure/enable SR-IOV on the vSwitch and on the VMs synthetic NIC.
    c. Run an iPerf throughput test.
       Note the throughput.
    d. Configure/Enable SR-IOV on the NIC.
    e. Run an iPerf throughput test.
       Note the throughput.
  Acceptance Criteria
    a. The throughput with SR-IOV enabled should be greater than when SR-IOV is disabled.

    
.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

.Example
    <test>
        <testName>Single_SaveVM</testName>
        <testScript>setupScripts\SR-IOV_SavePauseVM.ps1</testScript>
        <files>remote-scripts/ica/utils.sh</files> 
        <setupScript>
            <file>setupscripts\RevertSnapshot.ps1</file>
            <file>setupscripts\SR-IOV_enable.ps1</file>
        </setupScript> 
        <noReboot>False</noReboot>
        <testParams>
            <param>NIC=NetworkAdapter,External,SRIOV,001600112200</param>
            <param>TC_COVERED=??</param>                                   
            <param>BOND_IP1=10.11.12.31</param>
            <param>BOND_IP2=10.11.12.32</param>
            <param>NETMASK=255.255.255.0</param>
            <param>REMOTE_USER=root</param>
            <!-- VM_STATE has to be 'pause' or 'save' -->
            <param>VM_STATE=save</param>
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
# Install iPerf3 on both VMs
#
"Started Install"
$retVal = iPerfInstall $ipv4 $sshKey $netmask
if (-not $retVal)
{
    "ERROR: Failed to install iPerf3 on vm $vmName (IP: ${ipv4})"
    return $false
}

$retVal = iPerfInstall $vm2ipv4 $sshKey $netmask
if (-not $retVal)
{
    "ERROR: Failed to install iPerf3 on vm $vm2Name (IP: ${vm2ipv4})"
    return $false
}
"Ended install"
#
# Run iPerf3 with SR-IOV enabled
#
# Start the client side
"Start Client"
.\bin\plink.exe -i ssh\$sshKey root@${vm2ipv4}  "iperf3 -s > client.out &"

"Start Server"
# Start iPerf3 testing
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "source constants.sh && iperf3 -c `$BOND_IP2 >> PerfResults.log &"

# Get the logs
"Get Logs"
Start-Sleep -s 40
[decimal]$vfEnabledBandwidth = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "cat PerfResults.log | grep sender | awk '{print `$7}'"
if (-not $vfEnabledBandwidth){
    "ERROR: No result was logged! Check if iPerf was executed!" | Tee-Object -Append -file $summaryLog
    return $false
}

"The bandwidth with SR-IOV enabled is $vfEnabledBandwidth Gbits/sec" | Tee-Object -Append -file $summaryLog

#
# Disable SR-IOV on both VMs
#

"Disabling VF on vm1"
Set-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer -IovWeight 0
if (-not $?) {
    "ERROR: Failed to disable SR-IOV on $vmName!" | Tee-Object -Append -file $summaryLog
}

"Disabling VF on vm2"
Set-VMNetworkAdapter -VMName $vm2Name -ComputerName $remoteServer -IovWeight 0
if (-not $?) {
    "ERROR: Failed to disable SR-IOV on $vm2Name!" | Tee-Object -Append -file $summaryLog
}

#
# Run iPerf3 again and get the results
#
# Start the client side
Start-Sleep -s 20
# Start the client side
.\bin\plink.exe -i ssh\$sshKey root@${vm2ipv4}  "iperf3 -s > client.out &"

# Start iPerf3 testing
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "source constants.sh && iperf3 -c `$BOND_IP2 >> PerfResultsNoVF.log &"

# Get the logs
Start-Sleep -s 60
[decimal]$vfDisabledBandwidth = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "cat PerfResultsNoVF.log | grep sender | awk '{print `$7}'"
if (-not $vfDisabledBandwidth){
    "ERROR: No result was logged after SR-IOV was disabled! Check if iPerf was executed!" | Tee-Object -Append -file $summaryLog
    return $false
}

"The bandwidth with SR-IOV disabled is $vfDisabledBandwidth Gbits/sec" | Tee-Object -Append -file $summaryLog

#
# Compare the results
#
if ($vfDisabledBandwidth -ge $vfEnabledBandwidth) {
    "ERROR: The bandwidth with SR-IOV enabled is worse than with SR-IOV disabled!" | Tee-Object -Append -file $summaryLog
    return $false    
}

return $true