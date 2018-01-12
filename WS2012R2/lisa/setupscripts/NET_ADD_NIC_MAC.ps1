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
 Add NIC with a specified or automatically generated MAC address.

 Description:
   Add NIC with the specific MAC address.
   The testParams have the format of:

      NIC=NIC type, Network Type, Network Name, MAC Address

  NIC Type can be one of the following:
      NetworkAdapter
      LegacyNetworkAdapter

   Network Type can be one of the following:
      External
      Internal
      Private
      None

   Network Name is the name of a existing network. If Network Type is set to None however, the NIC is not connected to any switch.

   This script will make sure the network switch exists before adding the NIC (test is disabled in case of None switch type).

   The following is an example of a testParam for adding a NIC

       "NIC=NetworkAdapter,Internal,InternalNet,001600112200"

   All setup and cleanup scripts must return a boolean ($true or $false)
   to indicate if the script completed successfully or not.

   .Parameter vmName
	Name of the VM to add NIC to .

	.Parameter hvServer
	Name of the Hyper-V server hosting the VM.

	.Parameter testParams
	Test data for this test case.

	.Example
	setupScripts\NET_ADD_NIC_MAC -vmName vmName -hvServer localhost -testParams "NIC=NetworkAdapter,Internal,InternalNet,001600112200"
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
$isDynamic = $false

# If dynamic MAC is needed, do necessary operations
$params = $testParams.Split(';')
foreach ($p in $params) {
    $fields = $p.Split("=")
    switch ($fields[0].Trim()) {
        "NIC"
        {
            $nicArgs = $fields[1].Split(',')
            if ($nicArgs.Length -eq 3) {
                $isDynamic = $true
            }
        }
        "rootDIR"   { $rootDir = $fields[1].Trim() }
    }
}


if (-not $rootDir){
    "Error: no rootdir was specified"
    return $False
}

cd $rootDir
# Source TCUtils.ps1
if (Test-Path ".\setupScripts\TCUtils.ps1"){
    . .\setupScripts\TCUtils.ps1
}
else{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}

if ($isDynamic -eq $true) {
    $CurrentDir= "$pwd\"
    $testfile = "macAddress.file"
    $pathToFile="$CurrentDir"+"$testfile"
    $streamWrite = [System.IO.StreamWriter] $pathToFile
    $macAddress = $null
}

#
# Parse the testParams string, then process each parameter
#

foreach ($p in $params)
{
    $temp = $p.Trim().Split('=')

    if ($temp.Length -ne 2)
    {
        # Ignore and move on to the next parameter
        continue
    }

    #
    # Is this a NIC=* parameter
    #
    if ($temp[0].Trim() -eq "NIC")
    {
        $nicArgs = $temp[1].Split(',')

        if ($nicArgs.Length -lt 3)
        {
            "Error: Incorrect number of arguments for NIC test parameter: $p"
            return $false

        }

        $nicType = $nicArgs[0].Trim()
        $networkType = $nicArgs[1].Trim()
        $networkName = $nicArgs[2].Trim()
        if ($nicArgs.Length -eq 4) {
            $macAddress = $nicArgs[3].Trim()
        }
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
            $vmGeneration = GetVMGeneration $vmName $hvServer
            if ($vmGeneration -eq 2 )
            {
                LogMsg 0 "Warning: Generation 2 VM does not support LegacyNetworkAdapter, please skip this case in the test script"
                return $True
            }
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

    			# make sure network is of stated type
    			if ($vmSwitch.SwitchType -notlike $networkType)
    			{
    				"Error: Switch $networkName is type $vmSwitch.SwitchType (not $networkType)"
    				return $false
    			}

    		}


        if ($isDynamic -eq $true){
          # Source NET_UTILS.ps1 for network functions
          if (Test-Path ".\setupScripts\NET_UTILS.ps1")
          {
              . .\setupScripts\NET_UTILS.ps1
          }
          else
          {
              "ERROR: Could not find setupScripts\NET_Utils.ps1"
              return $false
          }
          $macAddress = getRandUnusedMAC $hvServer
          "Info: Generated MAC address: $macAddress"

          $streamWrite.WriteLine($macAddress)
        }
        else {
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
        }

    #
    # Add NIC with given MAC Address
    #
		if ($networkType -notlike "None")
		{
			Add-VMNetworkAdapter -VMName $vmName -SwitchName $networkName -StaticMacAddress $macAddress -IsLegacy:$legacy -ComputerName $hvServer
		}
		else
		{
			Add-VMNetworkAdapter -VMName $vmName -StaticMacAddress $macAddress -IsLegacy:$legacy -ComputerName $hvServer
		}

        if ($? -ne "True")
        {
            "Error: Add-VmNic failed"
            $retVal = $False
        }
		else
		{
            if($networkName -like '*SRIOV*') {
                $(get-vm -name $vmName -ComputerName $hvServer).NetworkAdapters | Where-Object { $_.SwitchName -like 'SRIOV' }  | Set-VMNetworkAdapter -IovWeight 1
                if($? -ne $True) {
                    "Error: Unable to enable SRIOV"
                    $retVal = $False
                } else {
                    $retVal = $True
                }
            } else {
				$retVal = $True
			}
		}
    }
}

if ($isDynamic -eq $true){
    $streamWrite.close()
}
Write-Output $retVal
return $retVal
