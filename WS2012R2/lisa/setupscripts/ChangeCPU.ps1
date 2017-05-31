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

.Description
    Modify the number of CPUs the VM has.

.Parameter vmName
    Name of the VM to modify.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.

.Example
    .\ChangeCPU "testVM" "localhost" "VCPU=2"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$numCPUs = 0
$maxCPUs = 0
$numaNodes = 8
$sockets = 1
$mem = $null
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
$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    if ($fields[0].Trim() -eq "VCPU")
    {
        $numCPUs = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "NumaNodes")
    {
        $numaNodes = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "Sockets")
    {
        $sockets = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "MemSize")
    {
        $mem = $fields[1].Trim()
    }
}

# Source TCUtils.ps1 for common functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
    "Info: Sourced TCUtils.ps1"
}
else {
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}

$staticMemory = ConvertStringToDecimal $mem

if ($numCPUs -eq 0)
{
    "Error: VCPU test parameter not found in testParams"
    return $retVal
}

#
# do a sanity check on the value provided in the testParams
#
$procs = get-wmiobject -computername $hvServer win32_processor
if ($procs)
{
    if ($procs -is [array])
    {
        foreach ($n in $procs)
        {
            $maxCPUs += $n.NumberOfLogicalProcessors
        }
    }
    else
    {
        $maxCPUs = $procs.NumberOfLogicalProcessors
    }
}

# If 'max' parameter was specified, will try to add the maximum vCPU allowed
if ($numCPUs -eq "max") 
{
    $vm = Get-VM -Name $vmName -ComputerName $hvServer

    # Depending on generation, the maximum allowed vCPU varies
    # On gen1 is 64 vCPU, on gen2 is 240 vCPU
    if ($vm.generation -eq 1) {
        [int]$maxAllowed = 64
    }
    else {
        [int]$maxAllowed = 240
    }

    if ($maxCPUs -gt $maxAllowed) {
        $numCPUs = $maxAllowed
    } 
    else {
        $numCPUs = $maxCPUs   
    }

}
else 
{
   [int]$numCPUs = $numCPUs
}

if ($numCPUs -lt 1 -or $numCPUs -gt $maxCPUs)
{
    "Error: Incorrect VCPU value: $numCPUs (max CPUs = $maxCPUs)"
}

#
# Update the CPU count on the VM
#
$cpu = Set-VM -Name $vmName -ComputerName $hvServer -ProcessorCount $numCPUs

if ($? -eq "True")
{
    Write-output "Info: CPU count updated to $numCPUs"
    $retVal = $true
}
else
{
    write-host "Error: Unable to update CPU count to $numCPUs"
    return $retVal
}

Set-VMProcessor -VMName $vmName -ComputerName $hvServer -MaximumCountPerNumaNode $numaNodes -MaximumCountPerNumaSocket $sockets
if ($? -eq "True")
{
    Write-output "Info: NUMA Nodes updated"
    $retVal = $true
}
else
{
    $retVal = $false
    write-host "Error: Unable to update NUMA nodes!"
}

if ($mem -ne $null)
{
    Set-VMMemory $vmName -ComputerName $hvServer -MaximumAmountPerNumaNodeBytes $staticMemory
    if ($? -eq "True")
    {
        Write-output "Info: NUMA memory updated"
        $retVal = $true
    }
    else
    {
        Write-output "Error: Unable to update NUMA memory $mem"
        $retVal = $false
    }
}

return $retVal
