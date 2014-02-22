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
    Reset a VMs CPU count to 1.

.Description
    Reset a VMs CPU count to 1.

.Parameter vmName
    Name of the VM to modify.

.Parameter hvServer
    Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.
    This cleanup script does not require any testParams.

.Example
    .\ResetCPU.ps1 "testVM" "localhost" "rootDir=D:\lisa"
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
    "Error: No testParams provided"
    "       The script $MyInvocation.InvocationName requires the VCPU test parameter"
    return $retVal
}

#
# for debugging - to be removed
#
"ChangeCPU.ps1 -vmName $vmName -hvServer $hvServer -testParams $testParams"

#
# Find the testParams we require.  Complain if not found
#
$numCPUs = 1

#
# HyperVLib version 2
# Note: For V2, the module can only be imported once into powershell.
#       If you import it a second time, the Hyper-V library function
#       calls fail.
#
<#$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2Sp1\Hyperv.psd1
}#>

#
# Update the CPU count on the VM
#
#$cpu = Set-VMCPUCount $vmName -CPUCount $numCPUs -server $hvServer
$cpu = Set-VM -Name $vmName -ComputerName $hvServer -ProcessorCount $numCPUs

if ($? -eq "True")
{
    write-host "CPU count updated to $numCPUs"
    $retVal = $true
}
else
{
    write-host "Error: Unable to update CPU count"
}

return $retVal
