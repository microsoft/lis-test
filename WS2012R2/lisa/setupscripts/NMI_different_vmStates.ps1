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
	Attempts to send NMI type interrupts to a VM in various states.

.Description
	The script will try to send a NMI to a given VM. Interrupts are successful
	only if the VM is running. Other VM states - Stopped, Saved and Paused must fail. 
	This is the expected behavior and the test case will return the results as such.

    The definition for this test case would look similar to:
        <test>
            <testName>NMI_different_vmStates</testName>
            <testScript>setupscripts\NMI_different_vmStates.ps1</testScript>
            <timeout>600</timeout>
            <onError>Continue</onError>
			<testParams>
                <param>TC_COVERED=NMI-02</param>
            </testParams>
            <noReboot>False</noReboot>
        </test>

.Parameter vmName
    Name of the VM to perform the test with.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters, including the IPv4 address of the VM.

.Example
    .\NMI_different_vmStates.ps1 -vmName "MyVM" -hvServer "localhost" -testParams "TC_COVERED=NMI-02;IPv4=VM_IPaddress"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false
$TC_COVERED = $null
$rootDir = $null
$ipv4 = $null
$errorstr = "Cannot inject a non-maskable interrupt into the virtual machine"

#######################################################################
#
# function StoppedState ()
# This function will try to send an NMI when the VM is stopped
#
#######################################################################
function StoppedState()
{
	# Shutting down the VM and waiting until the operation is done
	if ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Off") {
	Stop-VM -ComputerName $hvServer -Name $vmName -Force -Confirm:$false
	}

	while ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Off") {
	Start-Sleep -Seconds 5
	}

	#
	# Attempting to send the NMI, which must fail in order for the test to be valid
	#
	$nmistatus = Debug-VM -Name $vmName -InjectNonMaskableInterrupt -ComputerName $hvServer -Confirm:$False -Force 2>&1

	if (($nmistatus | select-string -Pattern $errorstr -Quiet) -eq "True") {
		return $True
	}
	else {
		return $retVal
	}
}

#######################################################################
#
# function SavedState ()
# This function will try to send an NMI when the VM is in a saved state
#
#######################################################################
function SavedState()
{
	# Checking first if the VM is running
	if ((Get-VM -ComputerName $hvServer -Name $vmName).State -eq "Off") {
		Start-VM -ComputerName $hvServer -Name $vmName
	}

	# Waiting for the VM to run again by checking the heartbeat
	while ((Get-VM -ComputerName $hvServer -Name $vmName).State -eq "On") {
		Write-Host "." -NoNewLine
		Start-Sleep -Seconds 5
	}
	do { 
		Start-Sleep -Seconds 5 } 
	until ((Get-VMIntegrationService $vmName | ?{$_.name -eq "Heartbeat"}).PrimaryStatusDescription -eq "OK")
	
	try {
		Save-VM -Name $vmName -ComputerName $hvServer
	}
	catch [system.exception] {
		Write-Host "Error: VM $vmName could not be saved!" | Tee-Object -Append -file $summaryLog
		return $False
	}

	#
	# Attempting to send the NMI, which must fail in order for the test to be valid
	#
	if ((Get-VM -ComputerName $hvServer -Name $vmName).State -eq "Saved") {
	$nmistatus = Debug-VM -Name $vmName -InjectNonMaskableInterrupt -ComputerName $hvServer -Confirm:$False -Force 2>&1

	if (($nmistatus | select-string -Pattern $errorstr -Quiet) -eq "True") {
		return $True
	}
	else {
		return $False
		}
	}
}

#######################################################################
#
# function PausedState ()
# This function will try to send an NMI with the VM in a paused state
#
#######################################################################
function PausedState()
{
	# First we need to pause the VM
	try {
		Suspend-VM -Name $vmName -ComputerName $hvServer
	}
	catch [system.exception] {
		Write-host "Error: VM $vmName could not be paused!" | Tee-Object -Append -file $summaryLog
		return $False
	}

	#
	# Attempting to send the NMI, which must fail in order for the test to be valid
	#
	if ((Get-VM -ComputerName $hvServer -Name $vmName).State -eq "Paused") {
	$nmistatus = Debug-VM -Name $vmName -InjectNonMaskableInterrupt -ComputerName $hvServer -Confirm:$False -Force 2>&1

	if (($nmistatus | select-string -Pattern $errorstr -Quiet) -eq "True") {
		return $True
	}
	else {
		return $False
		}
	}
}

#######################################################################
#
# Main body script
#
#######################################################################
#
# Checking the input arguments
#
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
    "This script requires the test case ID as the test parameter."
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
	if ($fields[0].Trim() -eq "ipv4") {
		$IPv4 = $fields[1].Trim()
    }
	if ($fields[0].Trim() -eq "rootDir")
    {
        $rootDir = $fields[1].Trim()
    }
}

if (-not $TC_COVERED) {
    "Error: Missing testParam TC_COVERED!"
    return $retVal
}

if (-not $IPv4) {
    "Error: Missing testParam ipv4!"
    return $retVal
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

#
# Delete any previous summary.log file, then create a new one
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Running all functions - StopState, SavedState and PausedState
#
"Info: 1st test - attempting to send an NMI while the VM is stopped"
$stopts= stoppedSTATE
if($stopts[-1] -eq $False) {
    Write-Output "Test Failed! Error: NMI has been sent when VM is stopped." | Tee-Object -Append -file $summaryLog
    return $retVal
}
elseif ($stopts[0] -eq $True) {
    Write-Output "Test Passed! NMI could not be sent when VM is stopped." | Tee-Object -Append -file $summaryLog
    $retval = $True
}

# Continuing with saving the VM state
"Info: 2nd test - attempting to send an NMI while the VM is in a saved state"
$savedts= savedSTATE
if($savedts[-1] -eq $False) {
    Write-Output "Test Failed! Error: NMI has been sent when VM is saved." | Tee-Object -Append -file $summaryLog
    return $False
}
elseif ($savedts[0] -eq $True) {
    Write-Output "Test Passed! NMI could not be sent when VM is saved." | Tee-Object -Append -file $summaryLog
    $retval = $True
}

# Starting the VM
Start-VM $vmName -ComputerName $hvServer

# Waiting for the VM to run again and respond to SSH - port 22
do {
	sleep 5
} until(Test-NetConnection $ipv4 -Port 22 -WarningAction SilentlyContinue | ? { $_.TcpTestSucceeded } )

# Testing the NMI with the VM paused
"Info: 3rd test - attempting to send an NMI while the VM is paused"
$pausedts= pausedSTATE
if($pausedts[-1] -eq $False) {
    Write-Output "Test Failed! Error: NMI has been sent when VM is paused." | Tee-Object -Append -file $summaryLog
    return $False
}
elseif ($pausedts[0] -eq $True) {
    Write-Output "Test Passed! NMI could not be sent when VM is paused." | Tee-Object -Append -file $summaryLog
    $retval = $True
}

# Resuming the VM from paused state
try {
	Resume-VM -Name $vmName -ComputerName $hvServer
}
catch [system.exception] {
    Write-host "Error: VM $vmName could not be paused!" | Tee-Object -Append -file $summaryLog
}

# Validating that all 3 VM states passes were successful for the end result
if (($stopts[0]) -and ($savedts[0]) -and ($pausedts[0])) {
$retval = $True
}
else {
    Write-Output "Test Failed! At least one or more tests have failed." | Tee-Object -Append -file $summaryLog
    return $False
}

return $retval
