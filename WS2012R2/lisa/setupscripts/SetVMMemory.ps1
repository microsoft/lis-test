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
    Sets the VMs RAM memory
.Description
    This is a Powershell script that sets the RAM memory of a VM
.Parameter vmName
    Name of the VM to migrate.
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
.Parameter testParams
    The amount of RAM to be set
.Example

.Link
    None.
#>

param(
      [string] $vmName,
      [string] $hvServer,
      [string] $testParams
      )

$retVal        = $False
$VMMemory      = $null
$startupMemory = $null

if (-not $vmName -or $vmName.Length -eq 0)
{
    "Error: vmName is null"
    return $False
}

if (-not $hvServer -or $hvServer.Length -eq 0)
{
    "Error: hvServer is null"
    return $False
}

if (Test-Path ".\setupScripts\TCUtils.ps1"){
  . .\setupScripts\TCUtils.ps1
}
else
{
  "Error: Could not find setupScripts\TCUtils.ps1"
  return $false
}

if (-not $testParams)
{
    "Error: testParams is null"
    return $False
}

$params = $testParams.TrimEnd(";").Split(";")
foreach ($param in $params)
{
    $fields = $param.Split("=")

    switch ($fields[0].Trim())
    {
        "VMMemory"      { $VMMemory    = $fields[1].Trim() }
        default         {} #unknown param - just ignore it
    }
}

$startupMemory = ConvertStringToDecimal $VMMemory
$availableMemory = [string](Get-Counter -Counter "\Memory\Available MBytes" -ComputerName $hvServer).CounterSamples[0].CookedValue + "MB"
$availableMemory = ConvertStringToDecimal $availableMemory

if ($startupMemory -gt $availableMemory)
{
    "Error: Not enough available memory on the system. startupMemory: $startupMemory, free space: $availableMemory"
    return $False
}

$vm = Get-VM -VMName $vmName -ComputerName $hvServer

if ($vm.DynamicMemoryEnabled)
{
	Set-VMMemory -VMName $vmName -ComputerName $hvServer -StartupBytes $startupMemory -MaximumBytes $startupMemory -MinimumBytes $startupMemory -Confirm:$False
}
else
{
	Set-VMMemory -VMName $vmName -ComputerName $hvServer -StartupBytes $startupMemory
}

if(-not $?)
{
    "Error: Unable to set ${VMMemory} of RAM for ${vmName}"
    return $retVal
}

"Success: Setting $VMMemory of RAM for $vmName updated successful"
$retVal = $True

return $retVal