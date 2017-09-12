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
    Run continous Ping while disabling and enabling the SR-IOV feature

.Description
    Continuously ping a server, from a Linux client, over a SR-IOV connection. 
    Disable SR-IOV on the Linux client and observe RTT increase.  
    Re-enable SR-IOV and observe that RTT lowers. 
      
.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

.Example
    <test>
        <testName>Ping_DisableVF</testName>
        <testScript>setupscripts\SR-IOV_Ping_DisableVF.ps1</testScript>
        <files>remote-scripts/ica/utils.sh,remote-scripts/ica/SR-IOV_Utils.sh</files> 
        <setupScript>
            <file>setupscripts\RevertSnapshot.ps1</file>
            <file>setupscripts\SR-IOV_enable.ps1</file>
        </setupScript> 
        <noReboot>False</noReboot>
        <testParams>
            <param>NIC=NetworkAdapter,External,SRIOV,001600112200</param>
            <param>TC_COVERED=SRIOV-5A</param>
            <param>VF_IP1=10.11.12.31</param>
            <param>VF_IP2=10.11.12.32</param>
            <param>NETMASK=255.255.255.0</param>
            <param>REMOTE_SERVER=remoteHostname</param>
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

#
# Configure VF on test VM
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
# Run Ping with SR-IOV enabled
#
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "echo 'source constants.sh && ping -c 600 -I eth1 `$VF_IP2 > PingResults.log &' > runPing.sh"
Start-Sleep -s 5
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "bash ~/runPing.sh > ~/Ping.log 2>&1"

# Wait 60 seconds and read the RTT
"Get Logs"
Start-Sleep -s 30
[decimal]$vfEnabledRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"
if (-not $vfEnabledRTT){
    "ERROR: No result was logged! Check if Ping was executed!" | Tee-Object -Append -file $summaryLog
    return $false
}
"The RTT before disabling SR-IOV is $vfEnabledRTT ms" | Tee-Object -Append -file $summaryLog

#
# Disable SR-IOV on test VM
#
Start-Sleep -s 5
"Disabling VF on vm1"
Set-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer -IovWeight 0
if (-not $?) {
    "ERROR: Failed to disable SR-IOV on $vmName!" | Tee-Object -Append -file $summaryLog
    return $false 
}

# Read the RTT with SR-IOV disabled; it should be higher
Start-Sleep -s 30
[decimal]$vfDisabledRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"
if (-not $vfDisabledRTT){
    "ERROR: No result was logged after SR-IOV was disabled!" | Tee-Object -Append -file $summaryLog
    return $false
}

"The RTT with SR-IOV disabled is $vfDisabledRTT ms" | Tee-Object -Append -file $summaryLog
if ($vfDisabledRTT -le $vfEnabledRTT) {
    "ERROR: The RTT was lower with SR-IOV disabled, it should be higher" | Tee-Object -Append -file $summaryLog
    return $false 
}

#
# Enable SR-IOV on test VM
"Enable VF on vm1"
Set-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer -IovWeight 1
if (-not $?) {
    "ERROR: Failed to enable SR-IOV on $vmName!" | Tee-Object -Append -file $summaryLog
    return $false 
}

Start-Sleep -s 30

# Read the RTT again, it should be lower than before
# We should see values to close to the initial RTT measured
[decimal]$vfEnabledRTT = $vfEnabledRTT * 1.3
[decimal]$vfFinalRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"

"The RTT after re-enabling SR-IOV is $vfFinalRTT ms" | Tee-Object -Append -file $summaryLog
if ($vfFinalRTT -gt $vfEnabledRTT) {
    "ERROR: After re-enabling SR-IOV, the RTT value has not lowered enough
    Please check if the VF was successfully restarted" | Tee-Object -Append -file $summaryLog
    return $false 
}

return $true