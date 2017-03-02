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
    SR-IOV Save/Pause tests

.Description
    1. Transfer a 1GB file between 2 VMs to verify SR-IOV functionality
    2. Pause/Save one VM for at least one minute
    3. Resume the VM
    4. Transfer again an 1GB file
    Acceptance: In both cases, the network traffic goes through bond0
    
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
        "BOND_IP3" { $vmBondIP3 = $fields[1].Trim() }
        "BOND_IP4" { $vmBondIP4 = $fields[1].Trim() }
        "NETMASK"  { $netmask = $fields[1].Trim() }
        "REMOTE_USER" { $remoteUser = $fields[1].Trim() }
        "VM2NAME"  { $vm2Name = $fields[1].Trim() }
        "VM_STATE" { $vmState = $fields[1].Trim()}
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
# Configure the bond on test VM
#
$retVal = ConfigureBond $ipv4 $sshKey $netmask
if (-not $retVal)
{
    "ERROR: Failed to configure bond on vm $vmName (IP: ${ipv4}), by setting a static IP of $vmBondIP1 , netmask $netmask" | Tee-Object -Append -file $summaryLog
    return $false
}

#
# Run Ping with SR-IOV enabled
#
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "echo 'source constants.sh && ping -c 20 -I bond0 `$BOND_IP2 > PingResults.log &' > runPing.sh"
Start-Sleep -s 5
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "bash ~/runPing.sh > ~/Ping.log 2>&1"

# Wait 60 seconds and read the RTT
"Get Logs"
Start-Sleep -s 10
[decimal]$beforeRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"
if (-not $beforeRTT){
    "ERROR: No result was logged! Check if Ping was executed!" | Tee-Object -Append -file $summaryLog
    return $false
}

"The RTT before saving/pausing VM is $beforeRTT ms" | Tee-Object -Append -file $summaryLog
Start-Sleep -s 10

#
# Create an 1 GB file on test VM
#
Start-Sleep -s 3
$retVal = CreateFileOnVM $ipv4 $sshKey 1024
if (-not $retVal)
{
    "ERROR: Failed to create a file on vm $vmName (IP: ${ipv4}), by setting a static IP of $vmBondIP1 , netmask $netmask" | Tee-Object -Append -file $summaryLog
    return $false
}

#
# Send the file from the test VM to the dependency VM
#
Start-Sleep -s 3
$retVal = SRIOV_SendFile $ipv4 $sshKey 7000
if (-not $retVal)
{
    "ERROR: Failed to send the file from vm $vmName to $vm2Name" | Tee-Object -Append -file $summaryLog
    return $false
}

#
# Pause/Save the test VM for 2 minutes
#
Start-Sleep -s 3
if ( $vmState -eq "pause" )
{
    Suspend-VM -Name $vmName -ComputerName $hvServer -Confirm:$False
    if ($? -ne "True")
    {
        "ERROR: VM $vmName failed to enter paused state" | Tee-Object -Append -file $summaryLog
        return $false
    }

    Start-Sleep -s 60

    Resume-VM -Name $vmName -ComputerName $hvServer -Confirm:$False
    if ($? -ne "True")
    {
        "ERROR: VM $vmName failed to resume" | Tee-Object -Append -file $summaryLog
        return $false
    }
}

elseif ( $vmState -eq "save" )
{
    Save-VM -Name $vmName -ComputerName $hvServer -Confirm:$False
    if ($? -ne "True")
    {
        "ERROR: VM $vmName failed to enter saved state" | Tee-Object -Append -file $summaryLog
        return $false
    }

    Start-Sleep -s 60

    Start-VM -Name $vmName -ComputerName $hvServer -Confirm:$False
    if ($? -ne "True")
    {
      "ERROR: VM $vmName failed to restart" | Tee-Object -Append -file $summaryLog
      return $false
    }    
}

else {
    "ERROR: Check the parameters! It should have VM_STATE=pause or VM_STATE=save" | Tee-Object -Append -file $summaryLog
    return $false    
}

# Read the RTT again, it should be lower than before
# We should see a significant imporvement, we'll check for at least 0.1 ms improvement
Start-Sleep -s 10
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "bash ~/runPing.sh > ~/Ping.log 2>&1"
Start-Sleep -s 5

[decimal]$beforeRTT = $beforeRTT + 0.04
[decimal]$afterRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"

"The RTT after re-enabling SR-IOV is $afterRTT ms" | Tee-Object -Append -file $summaryLog
if ($afterRTT -ge $beforeRTT ) {
    "ERROR: After resuming VM, the RTT value has not lowered enough
    Please check if the VF was successfully restarted" | Tee-Object -Append -file $summaryLog
    return $false 
}

#
# Send the file from the test VM to the dependency VM
#
Start-Sleep -s 20
$retVal = SRIOV_SendFile $ipv4 $sshKey 14000
if (-not $retVal)
{
    "ERROR: Failed to send the file from vm $vmName to $vm2Name after changing state" | Tee-Object -Append -file $summaryLog
    return $false
}

Start-Sleep -s 10
 "File was successfully sent from VM1 to VM2 after resuming VM" | Tee-Object -Append -file $summaryLog
return $true