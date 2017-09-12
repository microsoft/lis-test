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
    Enable SR-IOV on VM

.Description
    This is a setupscript that enables SR-IOV on VM
    Steps:
    1. Add new NICs to VMs
    2. Configure/enable SR-IOV on VMs settings via cmdlet Set-VMNetworkAdapter
    3. Run bondvf.sh on VM2 No more
    4. Set up SR-IOV on VM2
    Optional: Set up an internal network on VM2

.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

.Example
    <test>
        <testName>VerifyVF_basic</testName>
        <testScript>SR-IOV_VerifyVF_basic.sh</testScript>
        <files>remote-scripts\ica\SR-IOV_VerifyVF_basic.sh,remote-scripts/ica/utils.sh</files>
        <setupScript>
            <file>setupscripts\RevertSnapshot.ps1</file>
            <file>setupscripts\SR-IOV_enable.ps1</file>
        </setupScript>
        <noReboot>False</noReboot>
        <testParams>
            <param>NETWORK_NAME=SRIOV</param>
            <param>TC_COVERED=??</param>
            <param>BOND_IP1=10.11.12.31</param>
            <param>BOND_IP2=10.11.12.32</param>
            <param>NETMASK=255.255.255.0</param>
            <param>REMOTE_USER=root</param>
            <param>Clean_Dependency=yes</param>
        </testParams>
        <timeout>600</timeout>
    </test>

#>
param ([String] $vmName, [String] $hvServer, [string] $testParams)
#############################################################
#
# Main script body
#
#############################################################
$retVal = $False

# Write out test Params
$testParams

if ($hvServer -eq $null) {
    "ERROR: hvServer is null"
    return $False
}

if ($testParams -eq $null) {
    "ERROR: testParams is null"
    return $False
}

#change working directory to root dir
$testParams -match "RootDir=([^;]+)"
if (-not $?) {
    "Mandatory param RootDir=Path; not found!"
    return $false
}
$rootDir = $Matches[1]

if (Test-Path $rootDir) {
    Set-Location -Path $rootDir
    if (-not $?) {
        "ERROR: Could not change directory to $rootDir !"
        return $false
    }
    "Changed working directory to $rootDir"
}
else {
    "ERROR: RootDir = $rootDir is not a valid path"
    return $false
}

# Source TCUitls.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
}
else {
    "ERROR: Could not find setupScripts\TCUtils.ps1"
    return $false
}

# Source NET_UTILS.ps1 for network functions
if (Test-Path ".\setupScripts\NET_UTILS.ps1") {
    . .\setupScripts\NET_UTILS.ps1
}
else {
    "ERROR: Could not find setupScripts\NET_Utils.ps1"
    return $false
}

$networkName = $null
$remoteServer = $null
$nicIterator = 0
$vmBondIP = @()
$bondIterator = 0
$nicValues = @()
$leaveTrail = "no"
$params = $testParams.Split(';')
foreach ($p in $params)
{
    $fields = $p.Split("=")

    switch ($fields[0].Trim())
    {
    "VM2NAME" { $vm2Name = $fields[1].Trim() }
    "SSH_PRIVATE_KEY"  { $sshKey  = $fields[1].Trim() }
    "ipv4"    { $ipv4    = $fields[1].Trim() }
    "BOND_IP1" {
        $vmBondIP1 = $fields[1].Trim()
        $vmBondIP += ($vmBondIP1)
        $bondIterator++ }
    "BOND_IP2" {
        $vmBondIP2 = $fields[1].Trim()
        $vmBondIP += ($vmBondIP2)
        $bondIterator++ }
    "NETMASK" { $netmask = $fields[1].Trim() }
    "VM2SERVER" { $remoteServer = $fields[1].Trim()}
    "NETWORK_NAME" { $networkName = $fields[1].Trim() }
    default   {}  # unknown param - just ignore it
    }
}

if (-not $vm2Name) {
    "ERROR: test parameter vm2Name was not specified"
    return $False
}

# Make sure vm2 is not the same as vm1
if ("$vm2Name" -like "$vmName") {
    "ERROR: vm2 must be different from the test VM."
    return $false
}

if (-not $networkName) {
    "ERROR: test parameter NETWORK_NAME was not specified"
    return $False
}

# Check if VM2 is on another host
# If VM2 is on the same host, $remoteServer will be same as $hvServer
if (-not $remoteServer) {
    $remoteServer = $hvServer
}

#
# Attach SR-IOV to both VMs and start VM2
#
# Verify VM2 exists
$vm2 = Get-VM -Name $vm2Name -ComputerName $remoteServer -ERRORAction SilentlyContinue
if (-not $vm2) {
    "ERROR: VM ${vm2Name} does not exist"
    return $False
}

# Enable SR-IOV
Get-VMNetworkAdapter -VMName $vm2Name -ComputerName $remoteServer | Where-Object {($_).SwitchName -eq $networkName} | Set-VMNetworkAdapter -IovWeight 1
if ($? -eq "True") {
    $retVal = $True
}
else {
    "ERROR: Failed to enable SR-IOV on $vm2Name!"
}
Get-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer | Where-Object {($_).SwitchName -eq $networkName} | Set-VMNetworkAdapter -IovWeight 1
if ($? -eq "True") {
    $retVal = $True
}
else {
    "ERROR: Failed to enable SR-IOV on $vmName!"
}

return $retVal