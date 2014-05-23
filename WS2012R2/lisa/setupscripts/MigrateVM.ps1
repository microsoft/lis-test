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

.Link
    None.
#>
param([string] $vmName, [string] $hvServer, [string] $migrationType)

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
