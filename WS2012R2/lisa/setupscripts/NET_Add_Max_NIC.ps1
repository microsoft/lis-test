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
Add the maximum amount of synthetic and legacy NICs supported by a linux VM
.Description
This test script will add the maximum amount of synthetic and legacy NICs supported by a linux VM

The logic of the script is:
Process the test parameters.
Ensure required test parameters were provided.
Ensure the target VM exists
Add 7 synthetic and 4 legacy NICs to the VM, based on test parameters

A sample LISA test case definition would look similar to the following:

<test>
<testName>MaxNIC</name>
<setupScript>
<file>setupscripts\RevertSnapshot.ps1</file>
<file>setupscripts\NET_ADD_MAX_NIC.ps1</file>
</setupScript>
<testParams>
<param>TC_COVERED=NET-22</param>
<param>TEST_TYPE=synthetic, legacy</param>
<param>NETWORK_TYPE=external</param>
</testParams>
<testScript>setupscripts\NET_MAX_NIC.ps1</testScript>
<files>remote-scripts/ica/NET_MAX_NIC.sh,remote-scripts/ica/utils.sh</files>
<timeout>800</timeout>
</test>
#>

param( [String] $vmName, [String] $hvServer, [String] $testParams )

function AddNICs([string] $vmName, [string] $hvServer, [string] $type, [string] $network_type, [int] $nicsAmount)
{
	if ($type -eq "legacy")
	{
		$isLegacy = $True
	}
	else
	{
		$isLegacy = $False
	}

	for($i=0; $i -lt $nicsAmount; $i++)
	{
		LogMsg 5 "Info : Attaching NIC '${network_type}' to '${vmName}'"
		Add-VMNetworkAdapter -VMName $vmName -SwitchName $network_type -ComputerName $hvServer -IsLegacy $isLegacy #-ErrorAction SilentlyContinue
	}
}
########################################################################
#
# Main script body
#
########################################################################

#
# Make sure all command line arguments were provided
#
if (-not $vmName)
{
	LogMsg 0 "Error: vmName argument is null"
}

if (-not $hvServer)
{
	LogMsg 0 "Error: hvServer argument is null"
}

if (-not $testParams)
{
	LogMsg 0 "Error: testParams argument is null"
}

#
# Parse the testParams string
#
LogMsg 3 "Info : Parsing test parameters"
$params = $testParams.Split(";")
foreach($p in $params)
{
	$temp = $p.Trim().Split('=')
	if ($temp.Length -ne 2)
	{
		continue   # Just ignore the parameter
	}

	if ($temp[0].Trim() -eq "NETWORK_TYPE")
	{
		$network_type = $temp[1]
		#
		# Validate the Network type
		#
		if (@("External", "Internal", "Private", "None") -notcontains $network_type)
		{
			LogMsg 0 "Error: Invalid netowrk type"
			return $false
		}
	}

	if ($temp[0].Trim() -eq "TEST_TYPE")
	{
		$test_type = $temp[1].Split(',')

		if ($test_type.Length -eq 2)
		{
			if ($test_type[0] -notlike 'legacy' -and $test_type[0] -notlike 'synthetic')
			{
				LogMsg 0 "Error: Incorrect test type - $test_type[0]"
				return $false
			}

			if ($test_type[1] -notlike 'legacy' -and $test_type[1] -notlike 'synthetic')
			{
				LogMsg 0 "Error: Incorrect test type - $test_type[1]"
				return $false
			}
		}
		elseif ($test_type -notlike 'legacy' -and $test_type -notlike 'synthetic')
		{
			LogMsg 0 "Error: Incorrect test type - $test_type"
			return $false
		}
	}

	if ($temp[0].Trim() -eq "SYNTHETIC_NICS")
	{
		$syntheticNICs = $temp[1] -as [int]
		[int]$hostBuildNumber = (Get-WmiObject -class Win32_OperatingSystem -ComputerName $hvServer).BuildNumber
		if ($hostBuildNumber -le 9200) {
			[int]$syntheticNICs  = 2
		}
	}
	elseif ($temp[0].Trim() -eq "LEGACY_NICS")
	{
		$legacyNICs = $temp[1] -as [int]
	}
}

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
"Info : Covers ${tcCovered}" >> $summaryLog

#
# Source the utility functions so we have access to them
#
#. .\setupscripts\TCUtils.ps1

#
# Verify the target VM exists
#
LogMsg 3  "Info : Verify the SUT VM exists"
$vm = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $?)
{
	LogMsg 0 "Error: Unable to find VM '${vmName}' on server '${hvServer}'"
	return $false
}

# Check if legacy test is run for gen 2 vm
if ($vm.Generation -eq 2)
{
	if ($test_type.Length -eq 2)
	{
		if ($test_type[0] -eq "legacy" -or $test_type[1] -eq "legacy")
		{
			LogMsg 0 "Error: Unable to add legacy NIC to Gen 2 VM"
			return $false
		}
	}
	else
	{
		if ($test_type -eq "legacy")
		{
			LogMsg 0 "Error: Unable to add legacy NIC to Gen 2 VM"
			return $false
		}
	}
}

#
# Hot Add a Synthetic NIC to the SUT VM.  Specify a NIC name of "Hot Add NIC".
# This will make it easy to later identify the NIC to remove.
#
if ($test_type.Length -eq 2)
{
	foreach ($test in $test_type)
	{
		if ($test -eq "legacy")
		{
			AddNICs $vmName $hvServer $test $network_type $legacyNICs
		}
		else
		{
			AddNICs $vmName $hvServer $test $network_type $syntheticNICs
		}
	}
}
else
{
	if ($test_type -eq "legacy")
	{
		AddNICs $vmName $hvServer $test_type $network_type $legacyNICs
	}
	else
	{
		AddNICs $vmName $hvServer $test_type $network_type $syntheticNICs
	}
}

if (-not $?)
{
	LogMsg 0 "Error: Unable to add multiple NICs on VM '${vmName}' on server '${hvServer}'"
	return $false
}


return $True
