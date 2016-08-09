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
    This script tests the file copy functionality.

.Description
    The script will copy a random generated 10MB file from a Windows host to
	the Linux VM, and then checks if the size is matching.

    A typical XML definition for this test case would look similar
    to the following:
		<test>
			<testName>FCOPY_basic</testName>
			<testScript>setupscripts\FCOPY_basic.ps1</testScript>
			<timeout>900</timeout>
			<testParams>
				<param>TC_COVERED=FCopy-01</param>
			</testParams>
			<noReboot>True</noReboot>
		</test>

.Parameter vmName
    Name of the VM to test.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case.

.Example
    setupScripts\FCOPY_basic.ps1 -vmName NameOfVm -hvServer localhost -testParams 'sshKey=path/to/ssh;ipv4=ipaddress'
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false
$gsi = $null



################################################
#
#	Main body script
#
#######################################################################

# Checking the input arguments
if (-not $vmName) {
    "Error: VM name is null!"
    return $retVal
}

if (-not $hvServer) {
    "Error: hvServer is null!"
    return $retVal
}

if (-not $testParams) {
    "Error: No testParams provided!"
    "This script requires the test case ID and VM details as the test parameters."
    return $retVal
}

#
# Checking the mandatory testParams. New parameters must be validated here.
#
$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")

    if ($fields[0].Trim() -eq "TC_COVERED") {
        $TC_COVERED = $fields[1].Trim()
    }
	if ($fields[0].Trim() -eq "rootDir") {
        $rootDir = $fields[1].Trim()
    }
	if ($fields[0].Trim() -eq "ipv4") {
		$IPv4 = $fields[1].Trim()
    }
	if ($fields[0].Trim() -eq "sshkey") {
        $sshkey = $fields[1].Trim()
    }
}

#
# Change the working directory for the log files
# Delete any previous summary.log file, then create a new one
#
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist"
    return $retVal
}
cd $rootDir


# Source TCUtils.ps1 for test related functions
if (Test-Path ".\setupscripts\TCUtils.ps1")
{
    . .\setupScripts\TCUtils.ps1
}
else
{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}

# Delete any previous summary.log file, then create a new one
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Verify if the Guest services are enabled for this VM
#
$gsi = Get-VMIntegrationService -vmName $vmName -ComputerName $hvServer -Name "Guest Service Interface"
if (-not $gsi) {
    "Error: Unable to retrieve Integration Service status from VM '${vmName}'" | Tee-Object -Append -file $summaryLog
    return $False
}

if (-not $gsi.Enabled) {
    "Warning: The Guest services are not enabled for VM '${vmName}'" | Tee-Object -Append -file $summaryLog
	if ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Off") {
		Stop-VM -ComputerName $hvServer -Name $vmName -Force -Confirm:$false
	}

	# Waiting until the VM is off
	while ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Off") {
		Start-Sleep -Seconds 5
	}

	Enable-VMIntegrationService -Name "Guest Service Interface" -vmName $vmName -ComputerName $hvServer
	Start-VM -Name $vmName -ComputerName $hvServer

	# Waiting for the VM to run again and respond to SSH - port 22
	do {
		sleep 5
	} until (Test-NetConnection $IPv4 -Port 22 -WarningAction SilentlyContinue | ? { $_.TcpTestSucceeded } )
}
sleep 2
$remoteScript = "Hyperv_Daemons_Files_Status.sh"
$sts = RunRemoteScript $remoteScript
if (-not $sts[-1])
{
		Write-Output "ERROR executing $remoteScript on VM. Exiting test case!" >> $summaryLog
		Write-Output "ERROR: Running $remoteScript script failed on VM!"
		return $False
}


return $True
