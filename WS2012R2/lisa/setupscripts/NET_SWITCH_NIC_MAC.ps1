#####################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
#####################################################################


<#
.Synopsis
 Switch an existing NIC (with a certain MAC address) to a different network.

 Description:
   Switch an existing NIC (with a certain MAC address) to a different network.
   The testParams have the format of:

      NIC=NIC type, Network Type, Network Name, MAC Address

  NIC and SWITCH type can be one of the following:
      NetworkAdapter
      LegacyNetworkAdapter

   Network Type can be one of the following:
      External
      Internal
      Private
      None

     The Network Type is ignored by this script, but is still necessary, in order to have the same 
      parameters as the NET_ADD_NIC_MAC script.
      
      
   Network Name is the name of a existing network.

   This script will not create the network.  It will connect the NIC to the specified network.

   The following is an example of a testParam for switching a NIC

       "SWITCH=NetworkAdapter,Internal,InternalNet,001600112200"

   All setup and cleanup scripts must return a boolean ($true or $false)
   to indicate if the script completed successfully or not.
   
   .Parameter vmName
    Name of the VM to remove NIC from.

    .Parameter hvServer
    Name of the Hyper-V server hosting the VM.

    .Parameter testParams
    Test data for this test case.

    .Example
    setupScripts\SwitchNic_Mac -vmName VM -hvServer localhost -testParams "SWITCH=NetworkAdapter,Internal,Internal,001600112200,NIC=NetworkAdapter,External,External,001600112200"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false

# Source TCUitls.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1")
{
. .\setupScripts\TCUtils.ps1
}
else
{
"Error: Could not find setupScripts\TCUtils.ps1"
return $false
}

# Source NET_UTILS.ps1 for network functions
if (Test-Path ".\setupScripts\NET_UTILS.ps1")
{
    . .\setupScripts\NET_UTILS.ps1
}
else
{
    "Error: Could not find setupScripts\NET_Utils.ps1"
    return $false
}

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
# Parse the testParams string, then process each parameter
#
$params = $testParams.Split(';')
foreach ($p in $params)
{
    $temp = $p.Trim().Split('=')
    
    if ($temp.Length -ne 2)
    {
        # Ignore and move on to the next parameter
        continue
    }
    
    #
    # Is this a SWITCH=* parameter
    #
    if ($temp[0].Trim() -eq "SWITCH")
    {
        $nicArgs = $temp[1].Split(',')
        
        if ($nicArgs.Length -lt 4)
        {
            "Error: Incorrect number of arguments for SWITCH test parameter: $p"
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
        #

        if ($networkType -notlike "None")
        {
            $vmSwitch = Get-VMSwitch -Name $networkName -ComputerName $hvServer
            if (-not $vmSwitch)
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
        $ca = $macAddress.ToCharArray()
        foreach ($c in $ca)
        {
            if ($c -notmatch "[A-Fa-f0-9]")
            {
                "Error: MAC address contains non hexidecimal characters: $c"
               return $false
            }
        }
        
        #
        # Get Nic with given MAC Address
        #
        $nic = Get-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer -IsLegacy:$legacy | where {$_.MacAddress -eq $macAddress }
        if ($nic)
        {
            if ($networkType -like "None")
            {
                Disconnect-VMNetworkAdapter $nic
            }
            else 
            {
                Connect-VMNetworkAdapter $nic -SwitchName $networkName -Confirm:$False

            }
            
            $retVal = $?
        }
        else
        {
            "$vmName - No NIC found with MAC $macAddress ."
        }
    }

}

Write-Output $retVal
return $retVal
