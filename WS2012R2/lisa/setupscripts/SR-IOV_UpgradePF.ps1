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
    NOTE: This is a Mellanox specific TC
    Host PF driver update/downgrade, SR-IOV in guest should work without any interrupts

.Description
    Perform a Physical Function (PF) driver upgrade and down grade.  
    Upgrading or downgrading the driver should not affect SR-IOV functionality.
    Steps:
        Configure SR-IOV on a Linux VM and confirm SR-IOV is working.
        Upgrade the PF driver.
        Test SR-IOV functionality.
        Downgrade the PF driver.
        Test SR-IOV functionality.

    Acceptance Criteria:
        SR-IOV continues to work correctly after upgrading the PF driver.
        SR-IOV continues to work correctly after downgrading the PF driver.
    
.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

.Example
    <test>
        <testName>Upgrade_Downgrade_PF</testName>
        <testScript>setupscripts\SR-IOV_UpgradePF.ps1</testScript>
        <files>remote-scripts/ica/utils.sh,remote-scripts/ica/SR-IOV_Utils.sh</files> 
        <setupScript>
            <file>setupscripts\RevertSnapshot.ps1</file>
            <file>setupscripts\SR-IOV_enable.ps1</file>
        </setupScript> 
        <noReboot>False</noReboot>
        <testParams>
            <param>NIC=NetworkAdapter,External,SRIOV,001600112200</param>
            <param>TC_COVERED=SRIOV-18</param>
            <param>BOND_IP1=10.11.12.31</param>
            <param>BOND_IP2=10.11.12.32</param>
            <param>NETMASK=255.255.255.0</param>
            <param>REMOTE_SERVER=remoteHost</param>
            <param>OLDER_DRIVER_FOLDER_PATH=\\network\path\to\old\drivers</param>
            <param>NEWER_DRIVER_FOLDER_PATH=\\network\path\to\new\drivers</param>
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
        "OLDER_DRIVER_FOLDER_PATH" { $olderDriverPath = $fields[1].Trim()}
        "NEWER_DRIVER_FOLDER_PATH" { $newerDriverPath = $fields[1].Trim()}
        "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    }
}

$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Get IPs
$ipv4 = GetIPv4 $vmName $hvServer
"${vmName} IPADDRESS: ${ipv4}"

# Get default Hyper-V VHD path; The drivers will be copied here
$hostInfo = Get-VMHost -ComputerName $hvServer
$defaultVhdPath = $hostInfo.VirtualHardDiskPath
if (-not $defaultVhdPath.EndsWith("\")) {
    $defaultVhdPath += "\"
}

# Copy the drivers to local vhd path
Copy-Item -Path $olderDriverPath -Destination $defaultVhdPath -Force -Recurse
Start-Sleep -s 5
Copy-Item -Path $newerDriverPath -Destination $defaultVhdPath -Force -Recurse

# Get file names from each folder
$newerDriverPath =  Get-ChildItem $defaultVhdPath -Directory -Recurse | Sort-Object LastAccessTime -Descending | Select-Object -First 1
$olderDriverPath =  Get-ChildItem $defaultVhdPath -Directory -Recurse | Select-Object -First 1

$olderFirmware = Get-ChildItem $olderDriverPath.FullName | Where-Object {$_.Name -like '*mlxfw*'}
$olderDriver = Get-ChildItem $olderDriverPath.FullName | Where-Object {$_.Name -like '*Azure_Compute_*'}

$newerFirmware = Get-ChildItem $newerDriverPath.FullName | Where-Object {$_.Name -like '*mlxfw*'}
$newerDriver = Get-ChildItem $newerDriverPath.FullName | Where-Object {$_.Name -like '*Azure_Compute_*'}

# Unblock files
Unblock-File -Path $olderFirmware.FullName
Unblock-File -Path $olderDriver.FullName
Unblock-File -Path $newerFirmware.FullName
Unblock-File -Path $newerDriver.FullName

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
# Run Ping
#
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "echo 'source constants.sh && ping -c 1200 -I bond0 `$BOND_IP2 > PingResults.log &' > runPing.sh"
Start-Sleep -s 5
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "bash ~/runPing.sh > ~/Ping.log 2>&1"

# Wait 60 seconds and read the RTT
"Get Logs"
Start-Sleep -s 60
[decimal]$pfInitialRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"
if (-not $pfInitialRTT){
    "ERROR: No result was logged! Check if Ping was executed!" | Tee-Object -Append -file $summaryLog
    return $false
}

"The RTT before starting upgrading and downgrading: $pfInitialRTT ms" | Tee-Object -Append -file $summaryLog
Start-Sleep -s 10

#
# Upgrade the firmware & driver
#
# Install the newest driver & firmware
Start-Process -FilePath $newerDriver.FullName -ArgumentList "/R /S /v/qn" -Wait
Start-Sleep -s 150
Start-Process -FilePath $newerFirmware.FullName -ArgumentList "-f -y --sfx-no-pause" -Wait

# Restart VF
Start-Sleep -s 20
RestartVF $ipv4 $sshKey

# Read the RTT after upgrading
Start-Sleep -s 20
[decimal]$pfUpgradedRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"
if (-not $pfUpgradedRTT){
    "ERROR: No result was logged after SR-IOV was disabled!" | Tee-Object -Append -file $summaryLog
    return $false
}

"The RTT after upgrading the driver & firmware: $pfUpgradedRTT ms" | Tee-Object -Append -file $summaryLog

#
# Downgrade the firmware; driver can't be downgraded
#
# Install older firmware
Start-Process -FilePath $olderFirmware.FullName -ArgumentList "-f -y --sfx-no-pause" -Wait

# Read the RTT after upgrading
Start-Sleep -s 20
[decimal]$pfDowngradedRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"
if (-not $pfDowngradedRTT){
    "ERROR: No result was logged after firwmare was downgraded!" | Tee-Object -Append -file $summaryLog
    return $false
}

"The RTT after downgrading the firmware: $pfDowngradedRTT ms" | Tee-Object -Append -file $summaryLog

#
# Upgrade the firmware again
#
# Install older firmware
Start-Process -FilePath $newerFirmware.FullName -ArgumentList "-f -y --sfx-no-pause" -Wait

# Read the RTT after upgrading
Start-Sleep -s 20
[decimal]$pfFinalRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"
if (-not $pfFinalRTT){
    "ERROR: No result was logged after the firmware was upgraded again!" | Tee-Object -Append -file $summaryLog
    return $false
}
"The RTT after upgrading the firmware: $pfFinalRTT ms" | Tee-Object -Append -file $summaryLog

# Last, check if the RTT values are worse in the end
[decimal]$pfInitialRTT = $pfInitialRTT + 0.05
if ($pfFinalRTT -gt $pfInitialRTT ) {
    "ERROR: After upgrading & downgrading, the RTT value is too high
    Please check if the VF was successfully restarted" | Tee-Object -Append -file $summaryLog
    return $false 
}

return $true