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
	Setup script that will enable event logging for a set of Hyper-V channels defined below.

.Description
	When the script is called the first time, it will enable logging for a set of event channels.
	On the next call of the script, it will stop the logging and export the event logs to a file.

	You only have to parse the vmName to the script, and modify the set of event channels to log below.
	The script is meant to be called out from an xml file that defines the tests.
	Before a test or on the first test in the suite, define the script to run first:
	<setupScript>SetupScripts\log_hyperv_channels.ps1</setupScript>
	
	At the end of any test or when event logging is no longer required, call the script to export
	the log events and do the clean-up:
	<cleanupScript>SetupScripts\log_hyperv_channels.ps1</cleanupScript>

	The log file called [vmName]_SavedEventChannels.evtx is found in the lisa main folder.

	Refer to the link for more details.

.Link
	https://blogs.technet.microsoft.com/virtualization/2017/10/27/a-great-way-to-collect-logs-for-troubleshooting/
#>

param([string] $vmName)

# Valid sets can be any of the following:
# "None,All,Compute,Config,High-Availability,Hypervisor,StorageVSP,VID,VMMS,VmSwitch,Worker,
# SMB,FailoverClustering,HostGuardian,GuestDrivers,StorageSpaces,SharedVHDX,VMSP,VfpExt"
[string]$hyperv_channels = "VMMS,Config,Worker,Compute,VID"

# evtx extension is added by the module
$log_file = "${vmName}_SavedEventChannels"

# if we detect a previous run that enabled channels logging, then the script will:
# 1. save event logs to an evdx file
# 2. disable logging
# 3. clean-up for future script runs
if ($global:channels_enabled) {

	# Write events that happened after "startTime" for the defined channels to a 
	# single file in the current directory.
	Save-EventChannels -DestinationFileName $log_file -HyperVChannels $hyperv_channels.Split(',') $global:startTime 

	# Disable the analytical and operational logs -- by default admin logs are left enabled
	Disable-EventChannels -HyperVChannels $hyperv_channels.Split(',')

	# clean-up for this script for next runs
	$global:channels_enabled = $false
	return $True
	exit 1
}

# Download the current module from GitHub
Invoke-WebRequest "https://github.com/MicrosoftDocs/Virtualization-Documentation/raw/live/hyperv-tools/HyperVLogs/HyperVLogs.psm1" `
-OutFile "HyperVLogs.psm1"

#
# Load the PowerShell HyperVLogs module
#
$sts = get-module | select-string -pattern HyperVLogs -quiet
if (! $sts) {
	$hypervlogs_module = ".\HyperVLogs.psm1"
	if ( (Test-Path $hypervlogs_module) ) {
		# Import the module
		Import-Module .\HyperVLogs.psm1
	} 
	else {
		"Error: The PowerShell HyperVLogs module HyperVLogs.psm1 is not present!"
		return $False
	}
}

# Enable a set of Windows event channels
Enable-EventChannels -HyperVChannels $hyperv_channels.Split(',')

# Write the current time to a variable to limit the number of events later on
$global:startTime = [System.DateTime]::Now
$global:channels_enabled = $true

return $True
