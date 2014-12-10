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
    

.Description
    

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>
############################################################################
#
# MigrateVM.ps1
# 
# Description:
#     Script to migrate a VM from one cluster node to another. The script
# assumes that the 2-Node cluster is configured.
#     
# "MigrateVM.ps1 -vmName $vmName -hvServer $hvServer -testParams `"$testParams`""
#
############################################################################
param([string] $vmName, [string] $hvServer, [string] $testParams)

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

if (-not $testParams -or $testParams.Length -lt 3)
{
    "Error: testParams is null or invalid"
    return $False
}

$migtype = $null
$rootdir = $null
#
# Parse the testParams string
#
$params = $testParams.Split(';')
foreach ($p in $params)
{
    if ($p.Trim().Length -eq 0)
    {
        continue
    }

    $fields = $p.Trim().Split('=')
    
    if ($fields.Length -ne 2)
    {
	    #"Warn : test parameter '$p' is being ignored because it appears to be malformed"
        continue
    }
    
    if ($fields[0].Trim() -eq "MigType")
    {
        $migtype = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "RootDir")
    {
        $rootdir = $fields[1].Trim()
    }
}

#
# change the working directory to root dir
#

cd $rootdir

#
# Load the cluster commandlet module
#
$sts = get-module | select-string -pattern FailoverClusters -quiet
if (! $sts)
{
    Import-module FailoverClusters
}

#
# Have migration networks been configured?
#
$migrationNetworks = Get-ClusterNetwork
if (-not $migrationNetworks)
{
    "Error: $vmName - There are no Live Migration Networks configured"
    return $False
}

#
# Get the VMs current node
#
$vmResource =  Get-ClusterResource | where-object {$_.OwnerGroup.name -eq "$vmName" -and $_.ResourceType.Name -eq "Virtual Machine"}
if (-not $vmResource)
{
    "Error: $vmName - Unable to find cluster resource for current node"
    return $False
}

$currentNode = $vmResource.OwnerNode.Name
if (-not $currentNode)
{
    "Error: $vmName - Unable to set currentNode"
    return $False
}

#
# Get nodes the VM can be migrated to
#
$clusterNodes = Get-ClusterNode
if (-not $clusterNodes -and $clusterNodes -isnot [array])
{
    "Error: $vmName - There is only one cluster node in the cluster."
    return $False
}

#
# For the initial implementation, just pick a node that does not
# match the current VMs node
#
$destinationNode = $clusterNodes[0].Name.ToLower()
if ($currentNode -eq $clusterNodes[0].Name.ToLower())
{
    $destinationNode = $clusterNodes[1].Name.ToLower()
}

if (-not $destinationNode)
{
    "Error: $vmName - Unable to set destination node"
    return $False
}

#"Info : Migrating VM $vmName from $currentNode to $destinationNode"

$error.Clear()
$sts = Move-ClusterVirtualMachineRole -name $vmName -node $destinationNode -MigrationType $migtype 
if ($error.Count -gt 0)
{
    "Error: $vmName - Unable to move the VM"
    $error
    return $False
}

#"Info : Migrating VM $vmName back from $destinationNode to $currentNode"

$error.Clear()
$sts = Move-ClusterVirtualMachineRole -name $vmName -node $currentNode -MigrationType $migtype
if ($error.Count -gt 0)
{
    "Error: $vmName - Unable to move the VM"
    $error
    return $False
}

#
# If we got here, everything worked
#
return $True
