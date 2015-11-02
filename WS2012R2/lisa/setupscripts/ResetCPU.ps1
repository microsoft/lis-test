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
    Reset a VMs CPU count to 3.

.Description
    Reset a VMs CPU count to 3.

.Parameter vmName
    Name of the VM to modify.

.Parameter hvServer
    Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.
    This cleanup script does not require any testParams.

.Example
    .\ResetCPU.ps1 "testVM" "localhost" -testparams ""
#>


param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false

#
# Check input arguments
#
if ($vmName -eq $null)
{
    "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null)
{
    "Error: hvServer is null"
    return $retVal
}

if ($testParams -eq $null -or $testParams.Length -lt 3)
{
    "The script $MyInvocation.InvocationName requires the VCPU test parameter"
    return $retVal
}

#
# Find the testParams we require.  Complain if not found
#
$numCPUs = 4

#
# Update the CPU count on the VM
#
$cpu = Set-VM -Name $vmName -ComputerName $hvServer -ProcessorCount $numCPUs

if ($? -eq "True")
{
    Write-output "CPU count updated to $numCPUs"
    $retVal = $true
}
else
{
    Write-host "Error: Unable to update CPU count"
}

return $retVal
