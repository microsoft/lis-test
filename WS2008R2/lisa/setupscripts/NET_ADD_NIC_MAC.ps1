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
      The ICA scripts will always pass the vmName, hvServer, and a
  string of testParams from the test definition separated by
  semicolons. The testParams for this script identify disk
  controllers, hard drives, and .vhd types.  The testParams
  have the format of:

     NIC=NIC type, Network Type, Network Name

  NIC Type can be one of the following:
     NetworkAdapter
     LegacyNetworkAdapter

  Network Type can be one of the following:
     External
     Internal
     Private

  Network Name is the name of a existing netowrk.

  This script will not create the network.  It will make sure the network
  exists.

  The following is an example of a testParam for adding a NIC

    <testParams>
        <param>NIC=NetworkAdapter,External,Corp Ethernet LAN</param>
        <param>NIC=LegacyNetworkAdapter,Internal,InternalNet</param>
    <testParams>

  The above will be parsed into the following string by the ICA scripts and passed
  to the setup script:

      "NIC=NetworkAdapter,External,Corp Ehternet LAN";NIC=LegacyNetworkAdapter,Internal,InternalNet"

  The setup (and cleanup) scripts need to parse the testParam
  string to find any parameters it needs.

  Notes:
    This is a setup script that will run before the VM is booted.
    This script will add a NIC to the VM.

    Setup scripts (and cleanup scripts) are run in a separate
    PowerShell environment, so they do not have access to the
    environment running the ICA scripts.  Since this script uses
    The PowerShell Hyper-V library, these modules must be loaded
    by this startup script.

    The .xml entry for this script could look like either of the
    following:
        <setupScript>SetupScripts\AddNic.ps1</setupScript>

  All setup and cleanup scripts must return a boolean ($true or $false)
  to indicate if the script completed successfully or not.

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false

#
# Check input arguments
#
if (-not $vmName)
{
    "Error: VM name is null. "
    return $retVal
}

if (-not $hvServer)
{
    "Error: hvServer is null"
    return $retVal
}

#
# Note: length 22 is the shortest sting possible
#
if (-not $testParams -or $testParams.Length -lt 22)
{
    "Error: No testParams provided"
    "       The script $MyInvocation.InvocationName requires the Network test parameter"
    return $retVal
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
# Parse the testParams string, then process each parameter
#
#$retVal = $true

"Info : testParams = '${testParams}'"
$params = $testParams.Split(';')
foreach ($p in $params)
{
    $temp = $p.Trim().Split('=')
    
    if ($temp.Length -ne 2)
    {
        # Ignore this parameter and move on to the next
        continue
    }
    
    #
    # Is this a NIC=* parameter
    #
    if ($temp[0].Trim() -eq "NIC")
    {
        $nicArgs = $temp[1].Split(',')
        
        if ($nicArgs.Length -ne 4)
        {
            "Error: Invalid arguments for NIC test parameter: $p"
            return $false
        }
        
        $nicType = $nicArgs[0].Trim()
        $networkType = $nicArgs[1].Trim()
        $networkName = $nicArgs[2].Trim()
        $macAddress = $nicArgs[3].Trim()
        $legacy = $false
        
        #
        # Validate the network adapter type
        #
        if (@("NetworkAdapter", "LegacyNetworkAdapter") -notcontains $nicType)
        {
            "Error: Invalid NIC type: $nicType"
            "       Must be either 'NetworkAdapter' or 'LegacyNetworkAdapter'"
            return $false
        }
        
        if ($nicType -eq "LegacyNetworkAdapter")
        {
            $legacy = $true
        }

        #
        # Validate the Network type
        #
        if (@("External", "Internal", "Private", "None") -notcontains $networkType)
        {
            "Error: Invalid netowrk type: $networkType"
            "       Network type must be either: External, Internal, Private, None"
            return $false
        }

        #
        #
        # Make sure the network exists
        # ToDo: Also check the type of network. This turned out to be more difficult than I thought...
        #
        if ($networkType -notlike "None")
        {
            $vmSwitch = Get-VMSwitch -VirtualSwitchName $networkName -server $hvServer
            if (-not $vmSwitch -or $vmSwitch.__CLASS -ne "Msvm_VirtualSwitch")
            {
                "Error: Invalid network name: $networkName"
                "       The network does not exist"
                return $false
            }
        }

        #
        # Validate the MAC is the correct length
        #
        if ($macAddress.Length -ne 12)
        {
           "Error: Invalid mac address: $p"
           return $false
        }
        
        #
        # Make sure each character is a hex digit
        #
        #$ca = $macAddress.ToCharArray()
        #foreach ($c in $ca)
        #{
        #    if ($c -notmatch "[A-F0-9]")
        #    {
        #        "Error: MAC address contains non hexidecimal characters: $c"
        #        return $false
        #    }
        #}
        
        #
        # Add the NIC to the VM
        #
        #$results = Add-VmNic -VM $vmName -VirtualSwitch $networkName -MAC $macAddress -Legacy:$legacy -server $hvServer
        if ($networkType -notlike "None") {
            $results = Add-VmNic -VM $vmName -VirtualSwitch $networkName -Legacy:$legacy -server $hvServer -MAC $macAddress
            if ($results.__class -ne "Msvm_SyntheticEthernetPortSettingData" -and $results.__class -ne "Msvm_EmulatedEthernetPortSettingData")
            {
                "Error: Add-VmNic failed"
                return $false
            }
        }
        else {
            $results = Add-VmNic -VM $vmName -Legacy:$legacy -server $hvServer -MAC $macAddress
            if ($results.__class -ne "Msvm_SyntheticEthernetPortSettingData" -and $results.__class -ne "Msvm_EmulatedEthernetPortSettingData")
            {
                "Error: Add-VmNic failed"
                return $false
            }
        }

        $retVal = $true
    }
}

return $retVal
