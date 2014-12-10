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
# ChangeCPU.ps1
#
# Description:
#     This is a setup script that will run before the VM is booted.
#     This script will change the number of CPUs on the specified
#     virtual machine, hosted on the specified Hyper-V server.
#
#     Setup scripts (and cleanup scripts) are run in a separate
#     PowerShell environment, so they do not have access to the
#     environment running the ICA scripts.  Since this script uses
#     The PowerShell Hyper-V library, these modules must be loaded
#     by this startup script.
#
#     The .xml entry for this script could look like either of the
#     following:
#
#         <setupScript>SetupScripts\ChangeCPU.ps1</setupScript>
#
#   The ICA scripts will always pass the vmName, hvServer, and a
#   string of testParams from the test definition separated by
#   semicolons.  For example, an example would be:
#
#         "SLEEP_TIME=5; VCPU=2;"
#
#   The setup (and cleanup) scripts need to parse the testParam
#   string to find any parameters it needs.
#
#   All setup and cleanup scripts must return a boolean ($true or $false)
#   to indicate if the script completed successfully or not.
#
############################################################################
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
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2Sp1\Hyperv.psd1
}

#
# Update the CPU count on the VM
#
$cpu = Set-VMCPUCount $vmName -CPUCount $numCPUs -server $hvServer

if ($cpu -is [System.Management.ManagementObject])
{
    write-host "CPU count reset to $numCPUs"
    $retVal = $true
}
else
{
    write-host "Error: Unable to update CPU count"
}

return $retVal
