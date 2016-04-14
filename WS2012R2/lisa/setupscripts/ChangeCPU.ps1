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
    .\ChangeCPU "testVM" "localhost" "VCPU=2"
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
$numCPUs = 0
$numaNodes = 8
$sockets = 1
$mem = $null

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
        $maxCPUs = $procs[0].NumberOfLogicalProcessors *2
    }
    else
    {
        $maxCPUs = $procs.NumberOfLogicalProcessors *2
    }
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
    Write-output "CPU count updated to $numCPUs"
    $retVal = $true
}
else
{
    return $retVal
    write-host "Error: Unable to update CPU count"
}

Set-VMProcessor $vmName -MaximumCountPerNumaNode $numaNodes -MaximumCountPerNumaSocket $sockets
if ($? -eq "True")
{
    Write-output "Numa Nodes updated"
    $retVal = $true
}
else
{
    $retVal = $false
    write-host "Error: Unable to update Numa Nodes"
}
if ($mem -ne $null)
{
    Set-VMMemory $vmName -MaximumAmountPerNumaNodeBytes 1024MB
    if ($? -eq "True")
    {
        Write-output "Numa memory updated"
        $retVal = $true
    }
    else
    {
        Write-output "Error: Unable to update Numa memory $mem"
        $retVal = $false
    }
}

return $retVal
