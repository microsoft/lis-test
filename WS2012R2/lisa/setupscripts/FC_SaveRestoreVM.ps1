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
    Saves and restores a VM while the fibre channel is connected.

.Description
    This is a postTest script to check for save/restore VM operation 
    functionality.

.Parameter vmName
    Name of the VM to perform the test with.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.

.Example
	.\FC_SaveRestoreVM.ps1 -vmName "MyVM" -hvServer "localhost"
#>

param ([String] $vmName, [String] $hvServer, [String] $testParams)
$retVal = $False

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

#############################################################
#
# Main body script
#
#############################################################

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
	Start-Sleep -Seconds 5 
}
until ((Get-VMIntegrationService $vmName | ?{$_.name -eq "Heartbeat"}).PrimaryStatusDescription -eq "OK")

try {
	# Saving the VM
	Save-VM -Name $vmName -ComputerName $hvServer
    if (-not $?) {
        write-output "Error: Unable to save VM $vmName"
        return $False
    }

    # Waiting for the VM to enter saved state
    while ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Saved") {
        Start-Sleep -Seconds 5
    }
}
catch [system.exception] 
{
       Write-Host "Error: VM $vmName could not be saved!" | Tee-Object -Append -file $summaryLog
       return $False
}

if ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "On") {
    #Resuming VM from saved state
    Start-VM -ComputerName $hvServer -Name $vmName 
    if (-not $?) {
        write-output "Error: Unable to resume VM $vmName"
        return $False
    }
}

# Waiting for the VM to run again by checking the heartbeat
while ((Get-VM -ComputerName $hvServer -Name $vmName).State -eq "On") {
   Write-Host "." -NoNewLine
   Start-Sleep -Seconds 5
}
do {
    Start-Sleep -Seconds 5 
}
until ((Get-VMIntegrationService $vmName | ?{$_.name -eq "Heartbeat"}).PrimaryStatusDescription -eq "OK")
Write-Output "Machine successfully resumed."
return $True
