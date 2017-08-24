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
    SR-IOV ReplicationVM tests.

.Description
    1. Transfer a 1GB file between 2 VMs to verify SR-IOV functionality
    2. Replicate VM to another host
    3. Failover to another host
    3. Start both VMs to Replica host
    4. Transfer again an 1GB file
    Acceptance: In both cases, the network traffic goes through VF
    
.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

.Example
    <test>
        <testName>Replication_Single_VF</testName>
        <testScript>setupScripts\SR-IOV_Replication.ps1</testScript>
        <files>remote-scripts/ica/utils.sh</files> 
        <setupScript>
            <file>setupscripts\RevertSnapshot.ps1</file>
            <file>setupscripts\SR-IOV_enable.ps1</file>
        </setupScript> 
        <noReboot>False</noReboot>
        <testParams>
            <param>NIC=NetworkAdapter,External,SRIOV,001600112200</param>
            <param>TC_COVERED=??</param>                                   
            <param>VF_IP1=10.11.12.31</param>
            <param>VF_IP2=10.11.12.32</param>
            <param>NETMASK=255.255.255.0</param>
            <param>REMOTE_USER=root</param>
            <param>ReplicationServer=ReplicaServer</param>
            <param>ReplicationPort=8080</param>
            <param>enableVF=yes</param>
            <!-- Optional param - fill only if replication server is clustered -->
            <param>clusterName=cluster_name</param>
        </testParams>
        <timeout>2400</timeout>
    </test>
#>

param ([String] $vmName, [String] $hvServer, [string] $testParams)

#############################################################
#
# Function to determine the node that contains the VMs replicated
#
#############################################################
function GetVMOwner()
{
    $vm1ClusterInfo = Get-ClusterGroup -Cluster $clusterName -Name $vmName
    if (-not $vm1ClusterInfo) {
        "ERROR: Failed to get information about $vmName from $clusterName"
        return $false   
    }   
    $vm1owner = $vm1ClusterInfo.OwnerNode.Name

    $vm2ClusterInfo = Get-ClusterGroup -Cluster $clusterName -Name $vm2Name
    if (-not $vm2ClusterInfo) {
        "ERROR: Failed to get information about $vm2Name from $clusterName"
        return $false   
    }   
    $vm2owner = $vm2ClusterInfo.OwnerNode.Name

    # If VMs are on different nodes, move them to the same node
    if ($vm1owner -ne $vm2owner){
        $error.Clear()
        Move-ClusterVirtualMachineRole -Name $vm2Name -Cluster $clusterName -Node $vm1owner -MigrationType "quick"
        if ($error.Count -gt 0)
        {
            "Error: Unable to move the VM"
            $error
            return $False
        }
    }
    $error.Clear()
    return $vm1owner
}

#############################################################
#
# Clean up function
#
#############################################################
function CleanReplication()
{
    $vmOwner = ""
    if ($clusterName){
        $vmOwner = GetVMOwner
    }
    else {
        # If replication is not performed on a cluster
        $vmOwner = $ReplicaServer
    }

    Stop-VM -VMName $vmName -ComputerName $vmOwner
    Stop-VM -VMName $vm2Name -ComputerName $vmOwner
    #
    # Redo the initial state of both VMs
    #

    # Remove replication of vms on both hosts
    Remove-VMReplication -VMName $vmName -ComputerName $hvServer
    if (-not $?) {
        "ERROR: Failed to remove replication for $vmName"
        return $false     
    }

    Start-Sleep -s 3
    Remove-VMReplication -VMName $vm2Name -ComputerName $hvServer
    if (-not $?) {
        "ERROR: Failed to remove replication for $vm2Name"
        return $false     
    }


    Start-Sleep -s 3
    Remove-VMReplication -VMName $vmName -ComputerName $vmOwner
    if (-not $?) {
        "ERROR: Failed to remove replication for $vmName on Replica Server $vmOwner"
        return $false     
    }

    Start-Sleep -s 3
    Remove-VMReplication -VMName $vm2Name -ComputerName $vmOwner
    if (-not $?) {
        "ERROR: Failed to remove replication for $vm2Name on Replica Server $vmOwner"
        return $false     
    }

    Start-Sleep -s 30
    # If VMs are in a cluster, remove the cluster role
    if ($clusterName){
        Remove-ClusterGroup -Name $vmName -Cluster $clusterName -RemoveResources -Force -Confirm:$false
        if (-not $?) {
            "ERROR: Failed to remove Cluster Role for $vmName on cluster $clusterName"
            return $false     
        }

        Remove-ClusterGroup -Name $vm2Name -Cluster $clusterName -RemoveResources -Force -Confirm:$false
        if (-not $?) {
            "ERROR: Failed to remove Cluster Role for $vm2Name on cluster $clusterName"
            return $false     
        }
    }

    # Now it's safe to delete both VMs on Replica Server
    $vm = Get-VM $vmName -ComputerName $vmOwner -ErrorAction SilentlyContinue
    if ($vm)
    {
        if (Get-VM -Name $vmName -ComputerName $vmOwner |  Where { $_.State -like "Running" })
            {
                Stop-VM $vmName -ComputerName $vmOwner -Force
                if (-not $?) {
                    "ERROR: Unable to shut $vmName down in order to remove it!"
                    return $False
                }
            }
            
        Remove-VM $vmName -ComputerName $vmOwner -Force
    }

    $vm2 = Get-VM $vm2Name -ComputerName $vmOwner -ErrorAction SilentlyContinue
    if ($vm2)
    {
        if (Get-VM -Name $vm2Name -ComputerName $vmOwner |  Where { $_.State -like "Running" })
            {
                Stop-VM $vm2Name -ComputerName $vmOwner -Force
                if (-not $?) {
                    "ERROR: Unable to shut $vmName down in order to remove it!"
                    return $False
                }
            }
            
        Remove-VM $vm2Name -ComputerName $vmOwner -Force
    }
}
#############################################################
#
# Main script body
#
#############################################################
$retVal = $False
Set-PSDebug -Strict

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
        "VF_IP3" { $vmVF_IP3 = $fields[1].Trim() }
        "VF_IP4" { $vmVF_IP4 = $fields[1].Trim() }
        "NETMASK" { $netmask = $fields[1].Trim() } 
        "REMOTE_USER" { $remoteUser = $fields[1].Trim() }
        "VM2NAME" { $vm2Name = $fields[1].Trim() }
        "ReplicationServer" { $ReplicaServer = $fields[1].Trim() }
        "ReplicationPort" { $RecoveryPort = $fields[1].Trim() }
        "clusterName" { $clusterName = $fields[1].Trim() }
        "enableVF"  { $enableVF = $fields[1].Trim() }
    }
}

#
# Configure the VF on test VM
#
$retVal = ConfigureVF $ipv4 $sshKey $netmask
if (-not $retVal)
{
    "ERROR: Failed to configure VF on vm $vmName (IP: ${ipv4}), by setting a static IP of $vmVF_IP1 , netmask $netmask"
    return $false
}
"VF configured successfully"

#
# Create an 1 GB file on test VM
#
Start-Sleep -s 3
$retVal = CreateFileOnVM $ipv4 $sshKey 1024
if (-not $retVal)
{
    "ERROR: Failed to create a file on vm $vmName (IP: ${ipv4}), by setting a static IP of $vmVF_IP1 , netmask $netmask"
    return $false
}
"File created successfully"

#
# Send the file from the test VM to the dependency VM
#
Start-Sleep -s 3
$retVal = SRIOV_SendFile $ipv4 $sshKey 7000
if (-not $retVal)
{
    "ERROR: Failed to send the file from vm $vmName to $vm2Name"
    return $false
}
"File sent successfully between $vmName and $vm2Name on $hvServer" 
"Replication procedure will start"

#
# Start the VM replication
#
Enable-VMReplication -VMName $vmName -ReplicaServerName $ReplicaServer -ReplicaServerPort $RecoveryPort -AuthenticationType Kerberos -CompressionEnabled $true -RecoveryHistory 0
if (-not $?) {
    "ERROR: Failed to enable replication for $vmName on $hvServer"
    return $false     
}
Enable-VMReplication -VMName $vm2Name -ReplicaServerName $ReplicaServer -ReplicaServerPort $RecoveryPort -AuthenticationType Kerberos -CompressionEnabled $true -RecoveryHistory 0
if (-not $?) {
    "ERROR: Failed to enable replication for $vm2Name on $hvServer"
    return $false     
}

#
# If clustered, verify the replication and get the owner nodes
#
$vmOwner = ""
if ($clusterName){
    $vmOwner = GetVMOwner
}
else {
    # If replication is not performed on a cluster
    $vmOwner = $ReplicaServer
}

#
# Start initial replication
#
Start-VMInitialReplication -VMName $vmName -ComputerName $hvServer
Start-Sleep -s 5
$StateInfo = Get-VMReplication -VMName $vmName
while ($StateInfo.State -eq "InitialReplicationInProgress"){
    Start-Sleep -s 1
    $StateInfo = Get-VMReplication -VMName $vmName
}

Start-VMInitialReplication -VMName $vm2Name -ComputerName $hvServer
Start-Sleep -s 5
$StateInfo = Get-VMReplication -VMName $vm2Name
while ($StateInfo.State -eq "InitialReplicationInProgress"){
    Start-Sleep -s 1
    $StateInfo = Get-VMReplication -VMName $vm2Name
}
"Initial replication succeeded for $vmName and $vm2Name on $hvServer"

# VMs on initial host needs to be stopped
Stop-VM $vmName -ComputerName $hvServer -Force
if (-not $?) {
    Write-Host "Error: Unable to shut $vmName down in order to remove it!"
    CleanReplication
    return $False
}
Stop-VM $vm2Name -ComputerName $hvServer -Force
if (-not $?) {
    Write-Host "Error: Unable to shut $vmName down in order to remove it!"
    CleanReplication
    return $False
}

Start-Sleep -s 3

#
# Redo the network config on both VMs
#
$vmOwner = ""
if ($clusterName){
    $vmOwner = GetVMOwner
}
else {
    # If replication is not performed on a cluster
    $vmOwner = $ReplicaServer
}

Remove-VMNetworkAdapter -VMName $vmName -ComputerName $vmOwner
Add-VMNetworkAdapter -VMName $vmName -SwitchName "External" -ComputerName $vmOwner
if (-not $?) {
    "ERROR: Failed to attach an External adapter to $vmName"
    CleanReplication
    return $false     
}
Add-VMNetworkAdapter -VMName $vmName -SwitchName "SRIOV" -ComputerName $vmOwner
if (-not $?) {
    "ERROR: Failed to attach an SRIOV adapter to $vmName"
    CleanReplication
    return $false     
}

Remove-VMNetworkAdapter -VMName $vm2Name -ComputerName $vmOwner
Add-VMNetworkAdapter -VMName $vm2Name -SwitchName "External" -ComputerName $vmOwner
if (-not $?) {
    "ERROR: Failed to attach an External adapter to $vmName"
    CleanReplication
    return $false     
}
Add-VMNetworkAdapter -VMName $vm2Name -SwitchName "SRIOV" -ComputerName $vmOwner
if (-not $?) {
    "ERROR: Failed to attach an SRIOV adapter to $vmName"
    CleanReplication
    return $false     
}


# Add another pair of SRIOV
if ($vmVF_IP4) {
    Add-VMNetworkAdapter -VMName $vmName -SwitchName "SRIOV" -ComputerName $vmOwner
    if (-not $?) {
        "ERROR: Failed to attach an SRIOV adapter to $vmName"
        CleanReplication
        return $false     
    }

    Add-VMNetworkAdapter -VMName $vm2Name -SwitchName "SRIOV" -ComputerName $vmOwner
    if (-not $?) {
        "ERROR: Failed to attach an SRIOV adapter to $vmName"
        CleanReplication
        return $false     
    }    
}
"Successfully added NICs to both replication VMs"

# Enable SR-IOV on Replication VMs
Set-VMNetworkAdapter -VMName $vmName -ComputerName $vmOwner -IovWeight 1
if (-not $?) {
    "ERROR: Unable to enable SR-IOV on $vmName!"
    CleanReplication
    return $false  
}

Set-VMNetworkAdapter -VMName $vm2Name -ComputerName $vmOwner -IovWeight 1
if (-not $?) {
    "ERROR: Unable to enable SR-IOV on $vm2Name!"
    CleanReplication
    return $false  
}

#
# Start failover to Replication server
#
# Prepare VM1 for failover
Start-VMFailover -VMName $vmName -Prepare -Confirm:$false 
if (-not $?) {
    "ERROR: Failed to prepare $vmName for failover on $hvServer"
    CleanReplication
    return $false     
}
Start-Sleep -s 5
$StateInfo = Get-VMReplication -VMName $vmName
while ($StateInfo.State -ne "PreparedForFailover"){
    Start-Sleep -s 1
    $StateInfo = Get-VMReplication -VMName $vmName
}

# Prepare VM2 for failover
Start-VMFailover -VMName $vm2Name -Prepare -Confirm:$false
if (-not $?) {
    "ERROR: Failed to prepare $vm2Name for failover on $hvServer"
    CleanReplication
    return $false     
}
Start-Sleep -s 5
$StateInfo = Get-VMReplication -VMName $vm2Name 
while ($StateInfo.State -ne "PreparedForFailover"){
    Start-Sleep -s 1
    $StateInfo = Get-VMReplication -VMName $vm2Name
}

# Start failover on VM1
Start-Sleep -s 10
Start-VMFailover -VMName $vmName -Confirm:$false -ComputerName $vmOwner
if (-not $?) {
    "ERROR: Failed to start failover for $vmName on $vmOwner"
    CleanReplication
    return $false     
}
$StateInfo = Get-VMReplication -VMName $vmName -ComputerName $vmOwner
while ($StateInfo.State -ne "FailedOverWaitingCompletion"){
    Start-Sleep -s 1
    $StateInfo = Get-VMReplication -VMName $vmName -ComputerName $vmOwner
}

# Start failover on VM2
Start-Sleep -s 5
Start-VMFailover -VMName $vm2Name -Confirm:$false -ComputerName $vmOwner
if (-not $?) {
    "ERROR: Failed to start failover for $vm2Name on $vmOwner"
    CleanReplication
    return $false     
}
$StateInfo = Get-VMReplication -VMName $vm2Name -ComputerName $vmOwner
while ($StateInfo.State -ne "FailedOverWaitingCompletion"){
    Start-Sleep -s 1
    $StateInfo = Get-VMReplication -VMName $vm2Name -ComputerName $vmOwner
}

"Failover succeeded, both VMs will be started on Replication Server $vmOwner"
#
# Start the replication VMs and test SR-IOV again
#
Start-VM -VMName $vmName -ComputerName $vmOwner
if (-not $?)
{
    "ERROR: Unable to start VM ${vmName} on $vmOwner"
    CleanReplication
    return $False
}
Start-VM -VMName $vm2Name -ComputerName $vmOwner
if (-not $?)
{
    "ERROR: Unable to start VM ${vm2Name} on $vmOwner"
    CleanReplication
    return $False
}

# Wait for KVP on both VMs
$timeout = 200 # seconds
if (-not (WaitForVMToStartKVP $vmName $vmOwner $timeout))
{
    "ERROR: $vmName never started KVP"
    CleanReplication
    return $False
}
if (-not (WaitForVMToStartKVP $vm2Name $vmOwner $timeout))
{
    "ERROR: $vm2Name never started KVP"
    CleanReplication
    return $False
}

Start-Sleep -s 15
# Get IPs from replication VMs
$replicaIP1 = GetIPv4 $vmName $vmOwner
"$vmName IPADDRESS: $replicaIP1"

$replicaIP2 = GetIPv4 $vm2Name $vmOwner
"$vm2Name IPADDRESS: $replicaIP2"

if ($replicaIP1 -and $replicaIP2){
    "IPs were successfully obtained from both replication VMs"
}
else {
    "ERROR: Could not obtain IPs from replication VMs"
    CleanReplication
    return $False
}
Start-Sleep -s 180
# Enable VF again if needed
if ($enableVF -eq "yes") {
    $commandToSend = "cd ~ && ./ConfigureVF.sh"

    # Start VF on VM1 on Replication Server
    $retVal = SendCommandToVM "$replicaIP1" "$sshKey" $commandToSend
    if (-not $retVal)
    {
        "ERROR: Failed to configure VF on vm $vmName (IP: $$replicaIP1), by setting a static IP of $vmVF_IP1 , netmask $netmask"
        CleanReplication
        return $false
    }

    $retVal = SendCommandToVM "$replicaIP2" "$sshKey" $commandToSend
    if (-not $retVal)
    {
        "ERROR: Failed to configure VF on vm $vm2Name (IP: $replicaIP2), by setting a static IP of $vmVF_IP2 , netmask $netmask"
        CleanReplication
        return $false
    }

    "VF was successfully enabled on both Replication VMs"
}

# Test SR-IOV functionality on the Replication Server
Start-Sleep -s 180
$retVal = SRIOV_SendFile $replicaIP1 $sshKey 14000
if (-not $retVal)
{
    "ERROR: Failed to send the file from vm $vmName to $vm2Name on Replication Server $vmOwner"
    CleanReplication
    return $false
}
else {
    "SUCCESS: File was sent between $vmName and $vm2Name on Replication host $vmOwner"
    CleanReplication
}

Start-Sleep -s 60

return $retVal