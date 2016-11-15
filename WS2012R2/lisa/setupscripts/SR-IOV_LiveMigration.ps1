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
    Migration SR-IOV tests.

.Description
    a. Configure/enable SR-IOV on the vSwitch and on the VMs synthetic NIC (or NICs).
    b. Run the bonding script to create the bond0 device.
    c. Reboot and verify the bond devices are up and working.
    d. Migrate the VM to another host in the cluster which has a NIC with SR-IOV support.
    e. Copy a file to or from the VM.
 Acceptance Criteria
    a. After migrating the VM, the VM has network connectivity.
    b. The VMs bond0 device should continue to work.

    
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
            <param>NIC_sriov_name=SRIOV</param>
            <param>TC_COVERED=??</param>
            <param>BOND_IP1=10.11.12.31</param>
            <param>BOND_IP2=10.11.12.32</param>
            <param>NETMASK=255.255.255.0</param>
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
        "NETMASK" { $netmask = $fields[1].Trim() }
        "VM2NAME" { $vm2Name = $fields[1].Trim() }
        "MigrationType" { $migrationType    = $fields[1].Trim() }
        "FAILOVER" { $disableVF = $fields[1].Trim() }
        "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    }
}
# Prepare summary log
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Get ipv4 from VM2
$vm2ipv4 = GetIPv4 $vm2Name $hvServer
"$vm2Name IPADDRESS: $vm2ipv4"

#
# Configure the bond on test VM
#
$retVal = ConfigureBond $ipv4 $sshKey $netmask
if (-not $retVal) {
    "ERROR: Failed to configure bond on vm $vmName (IP: ${ipv4}), by setting a static IP of $vmBondIP1 , netmask $netmask"
    return $false
}
"Bond configured successfully"

#
# Create an 1 GB file on test VM
#
Start-Sleep -s 3
$retVal = CreateFileOnVM $ipv4 $sshKey 1024
if (-not $retVal) {
    "ERROR: Failed to create a file on vm $vmName (IP: ${ipv4}), by setting a static IP of $vmBondIP1 , netmask $netmask"
    return $False
}
"File created successfully"

#
# Send the file from the test VM to the dependency VM
#
Start-Sleep -s 3
$retVal = SRIOV_SendFile $ipv4 $sshKey 7000
if (-not $retVal) {
    "ERROR: Failed to send the file from vm $vmName to $vm2Name"
    return $False
}
"File sent successfully before migration"
"File sent successfully before migration" | Tee-Object -Append -file $summaryLog

#
# Start the VM migration
#
Import-Module FailoverClusters
$migrationNetworks = Get-ClusterNetwork
$vmResource =  Get-ClusterResource | where-object {$_.OwnerGroup.name -eq "$vmName" -and $_.ResourceType.Name -eq "Virtual Machine"}
$currentNode = $vmResource.OwnerNode.Name
$clusterNodes = Get-ClusterNode
$destinationNode = $clusterNodes[0].Name.ToLower()
if ($currentNode -eq $clusterNodes[0].Name.ToLower()) {
    $destinationNode = $clusterNodes[1].Name.ToLower()
}

$error.Clear()
Move-ClusterVirtualMachineRole -name $vmName -node $destinationNode -MigrationType $migrationType
if ($error.Count -gt 0) {
    "Error: Unable to move the VM"
    $error
    return $False
}

Move-ClusterVirtualMachineRole -name $vm2Name -node $destinationNode -MigrationType $migrationType
if ($error.Count -gt 0) {
    "Error: Unable to move the VM"
    $error
    return $False
}

# Restart VF
Start-Sleep -s 10
if ($disableVF -ne "yes") {
    RestartVF $ipv4 $sshKey
    RestartVF $vm2ipv4 $sshKey
}

#
# Send the file from the test VM to the dependency VM
#
Start-Sleep -s 10
$retVal = SRIOV_SendFile $ipv4 $sshKey 7000
if (-not $retVal) {
    "ERROR: Failed to send the file from vm $vmName to $vm2Name"
    return $False
}
"File sent successfully after migration"
"File sent successfully after migration" | Tee-Object -Append -file $summaryLog

# Return the VMs
$error.Clear()
Move-ClusterVirtualMachineRole -name $vmName -node $currentNode -MigrationType $migrationType
if ($error.Count -gt 0) {
    "Error: Unable to move the VM"
    $error
    return $False
}

Move-ClusterVirtualMachineRole -name $vm2Name -node $currentNode -MigrationType $migrationType
if ($error.Count -gt 0) {
    "Error: Unable to move the VM"
    $error
    return $False
}
Start-Sleep -s 30
return $retVal