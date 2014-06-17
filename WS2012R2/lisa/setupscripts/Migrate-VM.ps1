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
    Performs basic Live/Quick Migration operations
.Description
    This is a Powershell script that migrates a VM from one cluster node
    to another.
    The script assumes that the second node is configured
.Parameter vmName
    Name of the VM to migrate.
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
.Parameter migrationType
    Type of the migration to perform
.Example
    .\Migrate-Vm.ps1 -vmName VM_Name -hvServer HYPERV_SERVER -MigrationType Live -StopClusterNode $True
#>
param([string] $vmName, [string] $hvServer, [string] $migrationType, [bool] $stopClusterNode)

#
# Check input arguments
#
if (-not $vmName -or $vmName.Length -eq 0)
{
    "Error: VM name is null"
    return $false
}

if (-not $hvServer -or $hvServer.Length -eq 0)
{
    "Error: hvServer is null"
    return $false
}

if (-not $migrationType -or $migrationType.Length -eq 0)
{
    "Error: migrationType is null or invalid"
    return $False
}

#
# Load the cluster cmdlet module
#
$sts = Get-Module | Select-String -Pattern FailoverClusters -Quiet
if (! $sts)
{
    Import-Module FailoverClusters
}

#
# Check if migration networks are configured
#
$migrationNetworks = Get-ClusterNetwork
if (-not $migrationNetworks)
{
    "Error: There are no migration networks configured"
    return $False
}

#
# Get the VMs current node
#
$vmResource =  Get-ClusterResource | where-object {$_.OwnerGroup.name -eq "$vmName" -and $_.ResourceType.Name -eq "Virtual Machine"}
if (-not $vmResource)
{
    "Error: Unable to find cluster resource for current node"
    return $False
}

$currentNode = $vmResource.OwnerNode.Name
if (-not $currentNode)
{
    "Error: Unable to set currentNode"
    return $False
}

#
# Get nodes the VM can be migrated to
#
$clusterNodes = Get-ClusterNode
if (-not $clusterNodes -and $clusterNodes -isnot [array])
{
    "Error: There is only one cluster node in the cluster."
    return $False
}

# Picking up a node that does not match the current VMs node

$destinationNode = $clusterNodes[0].Name.ToLower()
if ($currentNode -eq $clusterNodes[0].Name.ToLower())
{
    $destinationNode = $clusterNodes[1].Name.ToLower()
}

if (-not $destinationNode)
{
    "Error: Unable to set destination node"
    return $False
}

"Info : Migrating VM $vmName from $currentNode to $destinationNode"

$error.Clear()
Move-ClusterVirtualMachineRole -name $vmName -node $destinationNode -MigrationType $migrationType
if ($error.Count -gt 0)
{
    "Error: Unable to move the VM"
    $error
    return $False
}


if($stopClusterNode)
{
    $clusterNodeStopped = $False
    $stoppedNode = Get-ClusterNode -Name $destinationNode
    "Info: Stoping cluster service for node ${destinationNode}"
    Stop-ClusterNode -Name $destinationNode
    $stopClusterNode = $False

    "Info: Waiting for ${destinationNode}'s cluster service to stop"
    while(-not $clusterNodeStopped)
    {
        if($stoppedNode.State -eq "Down")
        {
            $clusterNodeStopped = $True
        }
    }
    "Info: Cluster service for node ${destinationNode} is stopped"

    "Info: Sleep for 30 sec."
    $sleepTime = 30
    Start-Sleep -s $sleepTime

    "Info: Starting cluster service for node ${destinationNode}"
    Start-ClusterNode -Name $destinationNode
    "Info: Waiting for ${destinationNode}'s cluster service to be up and running"
    while($clusterNodeStopped)
    {
        if($stoppedNode.State -eq "Up")
        {
            $clusterNodeStopped = $False
        }
    }
    "Info: ${destinationNode}'s cluster service is up and running"

    "Info: checking if VM went back to ${currentNode}"
    $vms = Get-VM -ComputerName $currentNode
    foreach($vm in $vms)
    {
        if($vm.ComputerName.ToLower() -eq $currentNode.ToLower())
        {
            "Success: ${vmName} went back to ${currentNode}"
            return $True
        }
    }
    return $False
}


"Info : Migrating VM $vmName back from $destinationNode to $currentNode"

$error.Clear()
Move-ClusterVirtualMachineRole -name $vmName -node $currentNode -MigrationType $migrationType
if ($error.Count -gt 0)
{
    "Error: Unable to move the VM"
    $error
    return $False
}

return $True
