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
    Enables all the integration services for specified VM.

.Description
    This setup script enables all the integration services for specified VM.
    A typical test case definition for this test script would look
    similar to the following: 
    <test>
        <testName>StressReloadModules</testName>
        <setupscript>setupscripts\CORE_EnableIntegrationServices.ps1</setupscript>
        <testScript>setupscripts\CORE_reload_modules.ps1</testScript>
        <timeout>10600</timeout>
        <testParams>
                <param>TC_COVERED=CORE-18</param>
        </testParams>
            <onError>Continue</onError>
            <noReboot>False</noReboot>
        </test>
.Parameter vmName
    Name of the VM to read intrinsic data from.
    
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
    
.Parameter testParams
    Test data for this test case
    
.Example
    setupScripts\CORE_EnableIntegrationServices.ps1 -vmName "myVm" -hvServer "localhost" -TestParams "TC_COVERED=CORE-18"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $False
$testCaseTimeout = 600


#####################################################################
#
# Check VM current state
#
#####################################################################
function CheckCurrentStateFor([String] $vmName, $newState)
{
    $stateChanged = $False
    $vm = Get-VM -Name $vmName -ComputerName $hvServer

    if ($($vm.State) -eq $newState) {
        $stateChanged = $True
    }

    return $stateChanged
}


#####################################################################
#
# Main script body
#
#####################################################################

# Check input arguments
if ($vmName -eq $null) {
    "Error: VM name is null!"
    return $retVal
}

if ($hvServer -eq $null) {
    "Error: hvServer name is null!"
    return $retVal
}

#
# Parse the testParams string
#
$params = $testParams.Split(';')
foreach ($p in $params) {
    if ($p.Trim().Length -eq 0) {
        continue
    }

    $tokens = $p.Trim().Split('=')

    if ($tokens.Length -ne 2) {
		"Warn : test parameter '$p' is being ignored because it appears to be malformed"
		continue
    }

    if ($tokens[0].Trim() -eq "RootDir") {
		$rootDir = $tokens[1].Trim()
    }
    
	if ($tokens[0].Trim() -eq "tc_covered") {
		$tc_covered = $tokens[1].Trim()
    }
}

# Change the working directory for the log files
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist"
    return $retVal
}
cd $rootDir

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Source the TCUtils.ps1 file
. .\setupscripts\TCUtils.ps1

#
# Check that the VM is present on the server.
#
$vm = Get-VM -Name $vmName -ComputerName $hvServer
if (-not $vm) {
    "Error: Cannot find VM ${vmName} on server ${hvServer}"
    Write-Output "VM ${vmName} not found" | Tee-Object -Append -file $summaryLog
    return $False
}

#
# Stop the VM.
#
while ($testCaseTimeout -gt 0) {
    Stop-VM -Name $vmName -ComputerName $hvServer -Force -Verbose

    if ( (CheckCurrentStateFor $vmName ("Off"))) {
        break
    }
    Start-Sleep -seconds 2
    $testCaseTimeout -= 2
}

if ($testCaseTimeout -eq 0) {
    Write-Output "Error: Test case timed out waiting for VM to stop" | Tee-Object -Append -file $summaryLog
    return $False
}

Write-Output "Info: VM ${vmName} has been stopped successfully."

#
# Start all integration services.
#
Get-VMIntegrationService -VMName $vmName | ForEach-Object { 
    Enable-VMIntegrationService -Name $_.Name -VMName $vmName;
    if ($? -ne "True") {
        Write-Output "Error while enabling integration services" | Tee-Object -Append -file $summaryLog
        return $False
    }
    Write-Output "Started $($_.Name)"  
}

Write-Output "Info: Successfully enabled all integration services for VM ${vmName}" 
$retVal = $True

return $retVal