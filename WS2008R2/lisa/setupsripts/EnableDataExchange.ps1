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
    This is a PowerShell script is used to enable the data exchange integration service from VM properties. 

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false

#
# Check input arguments
#
if (-not $vmName)
{
    "Error: VM name is null"
    return $retVal
}

if (-not $hvServer)
{
    "Error: hvServer is null"
    return $retVal
}

<#if (-not $testParams)
{
    "Error: No testParams provided"
    "       This script requires the snapshot name as the test parameter"
    return $retVal
}#>

#
# Find the testParams we require.  Complain if not found
#

<#$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    if ($fields[0].Trim() -eq "???")
    {
        $Snapshot = $fields[1].Trim()
    }
            
}

if (-not $Snapshot)
{
    "Error: Missing testParam SnapshotName"
    return $retVal
} #>

#
# Import the HyperV module
#


$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
   Import-module .\HyperVLibV2Sp1\Hyperv.psd1 
}

#
# Change the state of Data exchange integration service to ON
#
$a = Get-VMIntegrationService  -VMName $vmName -ComputerName $hvServer -Name "Key-Value Pair Exchange" 
if ($? -ne "True")
{
 Write-Host "Error while getting the state of the data exchange service"
 return $retVal
}

if ($a.Enabled -eq "False")
{
 write-host "Data exchange service is in disabled state, setting it to ON"
 $a | Enable-VMIntegrationService
}
else
{
 write-host "Data exchange service is already in enabled state"
 $retVal = $true
 return $retVal
}

if ($a.Enabled -eq "True")
{
 Write-host "Data exchange for VM ${vmName} enabled successfully"
 $retVal = $true
}
else
{
write-host "Failed to enable data exchange for Vm ${vmName}" 
return $retVal
}

return $retVal
