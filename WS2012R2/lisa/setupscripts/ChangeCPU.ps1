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
    Modify the number of CPUs a VM has.

.Descriptioin
    Modify the number of CPUs the VM has.

.Parameter vmName
    Name of the VM to modify.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.

.Example
    .\ChangeCPU "testVM" "localhost" "VCPU=2;rootDir=D:\lisa"
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
$numCPUs = 0

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    if ($fields[0].Trim() -eq "VCPU")
    {
        $numCPUs = $fields[1].Trim()
        break
    }
}

if ($numCPUs -eq 0)
{
    "Error: VCPU test parameter not found in testParams"
    return $retVal
}

#
# do a sanity check on the value provided in the testParams
#
$maxCPUs = 2
$procs = get-wmiobject -computername $hvServer win32_processor
if ($procs)
{
    if ($procs -is [array])
    {
        $maxCPUs = $procs[0].NumberOfCores
    }
    else
    {
        $maxCPUs = $procs.NumberOfCores
    }
}

if ($numCPUs -lt 1 -or $numCPUs -gt $maxCPUs)
{
    "Error: Incorrect VCPU value: $numCPUs (max CPUs = $maxCPUs)"
    #return $retVal
}

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
