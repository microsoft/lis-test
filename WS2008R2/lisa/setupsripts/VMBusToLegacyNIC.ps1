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
#############################################################
#
# RevertNIC.ps1
#
# Description:
#    Remove a Legacy NIC and add a VMBus NIC to a VM, while
#    keeping the same MAC address.  This way, the VM will
#    be assigned the same IP address by the DHCP server.
#
# Test Params:
#    MAC=001122334455
#
#############################################################
param ([String] $vmName, [String] $hvServer, [String] $testParams)


#############################################################
#
# Main script body
#
#############################################################

$retVal = $False

if (-not $vmName)
{
    "Error: null vmName argument"
    return $False
}

if (-not $hvServer)
{
    "Error: null hvServer argument"
    return $False
}

if (-not $testParams)
{
    "Error: null testParams argument"
    return $False
}

#
#
#
"VM name     : ${vmName}"
"Server      : ${hvServer}"
"Test params : ${testParams}"

#
# Parse the test params
#
$MAC = $null

$params = $testParams.Split(';')
foreach ($p in $params)
{
    if ($p.Trim().Length -eq 0)
    {
        continue
    }

    $tokens = $p.Trim().Split('=')
    
    if ($tokens.Length -ne 2)
    {
	    "Warn : test parameter '$p' appears malformed, ignoring"
         continue
    }

    if ($tokens[0].Trim() -eq "MAC")
    {
        $mac = $tokens[1].Trim().ToLower()
    }
}

if (-not $MAC)
{
    "Error: MAC test parameter is missing"
    return $False
}

#
# Load the HyperVLib version 2 modules
#
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2SP1\Hyperv.psd1
}

#
# Find the VMBus NIC with the specific MAC address
#
$vmBusNICs = @(Get-VmNic -vm $vmName -server $hvServer -VMBus)
if (-not $vmBusNICs)
{
    "Error: VM does not have any vmBus NICs"
    return $False
}

$vmBusNIC = $null
$switchName = $null

foreach ($nic in $vmBusNICs)
{
    if ($nic.Address -eq $MAC)
    {
        $vmBusNIC = $nic
        $switchName = $nic.SwitchName.Trim()
        break
    }
}

if (-not $vmBusNic)
{
    "Error: Unable to find NIC with MAC=${MAC}"
    return $False
}

if (-not $switchName -or $switchName.Length -eq 0)
{
    "Error: switch not found, or has a name of zero characters"
    return $False
}

#
# Remove the VMBus NIC
#
$sts = ($vmBusNic | Remove-VMNic -VM $vmName -Server $hvServer -Force)
if (-not $sts -or $sts.ToString() -ne "OK")
{
    "Error: Unable to remove the VMBus NIC from the VM"
    return $False
}

#
# Add the Legacy NIC
#
$newNic = Add-VmNic -vm $vmName -VirtualSwitch $switchName -MAC $MAC -Legacy -Server $hvServer -Force
if ($newNic)
{
    $retVal = $True
}
else
{
    "Error: Unable to add Legacy NIC"
}

return $retVal
