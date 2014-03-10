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
    Revert a VM to a named snapshot.

Description
     This is a PowerShell test case script to validate that
     the VM snapshot is restored successfully.

     Setup scripts (and cleanup scripts) are run in a separate
     PowerShell environment, so they do not have access to the
     environment running the ICA scripts.  Since this script uses
     The PowerShell Hyper-V library, these modules must be loaded
     by this startup script.

     The .xml entry for this script could look like either of the
     following:

         <setupScript>SetupScripts\ChangeCPU.ps1</setupScript>

   The LiSA automation scripts will always pass the vmName, hvServer,
   and a string of testParams.  The testParams is a string of semicolon
   separated key value pairs.  For example, an example would be:

         "SLEEP_TIME=5; VCPU=2;"

   The setup (and cleanup) scripts need to parse the testParam
   string to find any parameters it needs.

   All setup and cleanup scripts must return a boolean ($true or $false)
   to indicate if the script completed successfully or not.

.Parameter vmName

.Parameter hvServer

.Parameter testParams

.Example
    .\RevertSnapshot "myVM" "localhost" "snapshotName=ICABase"
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

if (-not $testParams)
{
    "Error: No testParams provided"
    "       This script requires the snapshot name as the test parameter"
    return $retVal
}

#
# Find the testParams we require.  Complain if not found
#
$Snapshot = $null

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    if ($fields[0].Trim() -eq "SnapshotName")
    {
        $Snapshot = $fields[1].Trim()
    }
            
}

if (-not $Snapshot)
{
    "Error: Missing testParam SnapshotName"
    return $retVal
}

<#$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
   Import-module .\HyperVLibV2Sp1\Hyperv.psd1 
}#>

#New-VMSnapshot -VM $VmName -server $hvServer -wait -Force | Out-Null
$snap = Get-VMSnapshot -ComputerName $hvServer -VMName   $VmName -Name $Snapshot

Restore-VMSnapshot $snap -Confirm:$false -Verbose
if ($? -ne "True")
{
write-host "Error while reverting VM snapshot"
return $False
}
else
{
    Write-Output "VM snapshot reverted"
    $retVal = $true
}

Write-Output $retVal

return $retVal
