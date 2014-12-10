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
    This will script will Add a VMBus NIC to a VM also it will adds the Vlan tag to the VMBus adapter.


.Parameter testParams
    Switch Name

.Example
    
#>

param ([String] $vmName, [String] $hvServer, [String] $testParams)


#############################################################
#
# Main script body
#
#############################################################

$retVal = $False

#
# Check the required input args are present
#
if (-not $vmName)
{o
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
# Display some info for debugging purposes
#
"VM name     : ${vmName}"
"Server      : ${hvServer}"
"Test params : ${testParams}"

#
# Parse the test params
#

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

    if ($tokens[0].Trim() -eq "switchName")
    {
        $switchName = $tokens[1].Trim().ToLower()
    }
}


if (-not $switchName)
{
    "Error: switchName test parameter is missing"
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
# Add the VMBus NIC
#
$newNic = Add-VmNic -vm $vmName -VirtualSwitch $switchName  -Server $hvServer -Force
if ($newNic)
{
    $retVal = $True
}
else
{
    "Error: Unable to add VMBus NIC"
    return $False

}

#
# Add the Vlan ID to the VMBUS adapter
#

Set-VMNetworkAdapterVlan -VMName $vmName  -VMNetworkAdapterName $newNic.ElementName -Trunk -NativeVlanId 1 -AllowedVlanIdList “2,3,4”
if ($? -ne $True)
{
    "Error: Unable to set the Vlan ID to the VMBUS adapter"
    $retVal = $False
}

return $retVal
