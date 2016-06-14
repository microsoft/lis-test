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
 Add a new virtual switch.

 Description:
   Add a new virtual switch.
   The testParams have the format of:

      switch=virtual switch type, switch name

  Virtual switch Type can be one of the following:
      External
      Internal
      Private

   Switch Name is the name of new added swtich.

   This script only supports Internal and Private virtual switch creation.

   The following is an example of a testParam for adding a NIC

       "switch=Internal,InternalNet"

   All setup and cleanup scripts must return a boolean ($true or $false)
   to indicate if the script completed successfully or not.

   .Parameter vmName
	Name of the VM to add NIC to .

	.Parameter hvServer
	Name of the Hyper-V server hosting the VM.

	.Parameter testParams
	Test data for this test case.

	.Example
	setupScripts\NET_ADD_Switch -vmName sles11sp3x64 -hvServer localhost -testParams "switch=Internal,InternalNet"
#>

param( [string] $hvServer, [string] $testParams)

$retVal = $false

#
# Check input arguments
#
if (-not $hvServer)
{
    "Error: hvServer is null."
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
    # Is this a switch=* parameter
    #
    if ($temp[0].Trim() -eq "switch")
    {
        $switchArgs = $temp[1].Split(',')

        if ($switchArgs.Length -lt 2)
        {
            "Error: Incorrect number of arguments for NIC test parameter: $p"
            return $false

        }

        $switchType = $switchArgs[0].Trim()
        $switchName = $switchArgs[1].Trim()

        #
        # Validate the virtual switch type
        #
        if (@("External", "Internal", "Private") -notcontains $switchType)
        {
            "Error: Invalid virtual switch type: $switchType"
            "       Must be either 'External', 'Internal' or 'Private'"
            return $false
        }
    }
}

#
# Add a new switch if there's no this kind of switch with the same name
#
$vmSwitch = Get-VMSwitch -SwitchType $switchType
if (-not $vmSwitch)
{
    New-VMSwitch -name $switchName -SwitchType $switchType
    if ($? -ne "True")
    {
        "Error: New-VMSwitch failed"
        return $false
    }
    else
    {
        $retVal = $True
        Write-Output $retVal
        return $retVal
    }
}
if ($vmSwitch -is [system.array])
{
    $findSwitch = $False
    foreach ($s in $vmSwitch)
    {
        if ($s.name -eq $switchName)
        {
            $findSwitch = $True
        }
    }
    if ($findSwitch)
    {
        $retVal = $True
        Write-Output $retVal
        return $retVal
    }
    else
    {
        New-VMSwitch -name $switchName -SwitchType $switchType
        if ($? -ne "True")
        {
            "Error: New-VMSwitch failed"
            return $false
        }
        else
        {
            $retVal = $True
            Write-Output $retVal
            return $retVal
        }
    }
}
else
{
    if ($vmSwitch.name -eq $switchName)
    {
        $retVal = $True
        Write-Output $retVal
        return $retVal
    }
    else
    {
        New-VMSwitch -name $switchName -SwitchType $switchType
        if ($? -ne "True")
        {
            "Error: New-VMSwitch failed"
            return $false
        }
        else
        {
            $retVal = $True
            Write-Output $retVal
            return $retVal
        }
    }
}
