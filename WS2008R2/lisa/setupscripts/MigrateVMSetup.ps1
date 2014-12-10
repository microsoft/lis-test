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

param ( [String] $vmName )

"MigrateVMSetup.ps1 -vmName $vmName"

#
# Load the cluster commandlet module
#
$sts = get-module | select-string -pattern FailoverClusters -quiet
if (! $sts)
{
    Import-module FailoverClusters
}

# Get the VMs current node
#
#$vmResource =  Get-ClusterResource | where-object {$_.OwnerGroup.name -eq "$vmName" -and $_.ResourceType.Name -eq "Virtual Machine"}
$vmResource =  Get-ClusterResource "Virtual Machine ${vmName}"

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

$potentialOwners = ($vmResource | Get-ClusterOwnerNode)
$preferredOwner = $potentialOwners.OwnerNodes[0].Name

if ($currentNode -ne $preferredOwner)
{
    $error.Clear()
    $sts = Move-ClusterGroup $vmName -node $preferredOwner
    if ($error.Length -gt 0)
    {
        "Error: Move-ClusterGroup failed"
        $error[0].ErrorDetails
        return $false
    }
}

#
# If we made it here, everything worked
#
return $True
