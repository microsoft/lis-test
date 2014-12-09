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
# Shutdown a Virtual Machine (requires Integration Components) 
# ShutDown.ps1
#
# Description:
#     Shutdown the VM using Integration Component
#         <setupScript>SetupScripts\ShutDown.ps1</setupScript>
#
#	Modified by : v-vyadav@microsoft.com
#
######################################################################
param([string] $vmName, [string] $hvServer)

write-host "Host is $hvServer"
write-host "Guest is $vmName"
#param(
#    [string]$vmName = $(throw "Must specify virtual machine name")
#) 

$timeout = 300
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

# Load the HyperVLib version 2 modules
#
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2\Hyperv.psd1
}

# Check if VM is in running state or not, test to be performed only if its in running state.

$v = Get-VM $vmName -server $hvServer 
$hvState = $v.EnabledState
if ($hvState -eq 2)
{

	# Get the VM by name and request state to change to Enabled
	$vm = gwmi -namespace root\virtualization Msvm_ComputerSystem -computername $hvServer -filter "ElementName='$vmName'" 

	# Get the associated Shutdown Component
	$shutdown = gwmi -namespace root\virtualization `
	    -query "Associators of {$vm} where ResultClass=Msvm_ShutdownComponent" 

	# Initiate a forced shutdown with simple reason string, return 	resulting error code
	#return $shutdown.InitiateShutdown($true,"System Maintenance")

	$sts = $shutdown.InitiateShutdown($true,"Test shutdown IC")
	if ($sts.ReturnValue -eq 0)
	{
	    write-host "Shutdown Initiated without any error through 		Intergration Services "

		$elapsedTime=0
		while ($elapsedTime -lt $timeout)
		{
			# Check if VM reached Stopped state or not
			$v = Get-VM $vmName -server $hvServer 
			$hvState = $v.EnabledState
			if ($hvState -eq 3)
			{
				write-host "Shutdown Success without any error  through Intergration Services "
				$retVal = $true
				break
			}
	
			#sleep for 1 second
			start-sleep -seconds 1
	
			$elapsedTime += 1
		}	

		if ($elapsedTime -ge $timeout)
		{
			write-host "Shutdown Failed through Intergration 			Services "
		}
	}
	else 
	{
		write-host "Error Occured while shutDown through  Intergration Services "
	}
}

else
{
	write-host "Error : VM is not in running state, aborting Test"
}

return $retVal












