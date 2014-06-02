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

<#
.Synopsis
    Verify that the VM export and import operations are working.

.Description
    This script exports the VM, imports it back, verifies that the imported 
    VM has the snapshots also. Finally it deletes the imported VM.

    A typical test case definition for this test script would look
    similar to the following:
        <test>
            <testName>ExportImportVM</testName>
            <testScript>setupScripts\STOR_ExportImportVM.ps1</testScript>
            <timeout>2400</timeout>
            <testParams>
                <param>SnapshotName=ICABase</param>
                <param>TC_COVERED=STOR-58</param>
            </testParams>
            <onError>Continue</onError>
            <noReboot>False</noReboot>
        </test>

.Parameter vmName
    Name of the VM to perform the test with.
    
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
    
.Parameter testParams
    Test data for this test case
    
.Example
    setupScripts\STOR_ExportImportVM.ps1 -vmName "myVm" -hvServer "localhost" -TestParams "TC_COVERED=STOR-58"
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
    "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null) {
    "Error: hvServer is null"
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
# Check that the VM is present on the server and it is in running state.
#
$vm = Get-VM -Name $vmName -ComputerName $hvServer
if (-not $vm) {
    "Error: Cannot find VM ${vmName} on server ${hvServer}"
    Write-Output "VM ${vmName} not found" | Out-File -Append $summaryLog
    return $False
}


Write-Output "VM ${vmName} is present on server and running"

#
# Stop the VM to export it.
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
    Write-Output "Error: Test case timed out waiting for VM to stop" | Out-File -Append $summaryLog
    return $False
}

Write-Output "VM ${vmName} has stopped successfully"

#
# Create a Snapshot before exporting the VM
#
Checkpoint-VM -Name $vmName -ComputerName $hvServer -SnapshotName "TestExport" -Confirm:$False
if ($? -ne "True") {
    Write-Output "Error while creating the snapshot" | Out-File -Append $summaryLog
    return $false
}

Write-Output "Successfully created a new snapshot before exporting the VM"


$exportPath = (Get-VMHost).VirtualMachinePath + "\ExportTest\" 

$vmPath = $exportPath + $vmName +"\"

#
# Delete existing export, if any.
#
Remove-Item -Path $vmPath -Recurse -Force -ErrorAction SilentlyContinue

#
# Export the VM.
#
Export-VM -Name $vmName -ComputerName $hvServer -Path $exportPath -Confirm:$False -Verbose
if ($? -ne "True") {
    Write-Output "Error while exporting the VM" | Out-File -Append $summaryLog
    return $false
}

Write-Output "VM ${vmName} exported successfully"

#
# Before importing the VM from exported folder, Delete the created snapshot from the orignal VM.
#
Get-VMSnapshot -VMName $vmName -ComputerName $hvServer -Name "TestExport" | Remove-VMSnapshot -Confirm:$False

#
# Save the GUID of exported VM.
#
$ExportedVM = Get-VM -Name $vmName -ComputerName $hvServer
$ExportedVMID = $ExportedVM.VMId

#
# Import back the above exported VM.
#
$vmConfig = Get-Item "$vmPath\Virtual Machines\*.xml"

Write-Output $vmConfig.fullname

Import-VM -Path $vmConfig -ComputerName $hvServer -Copy "${vmPath}\Virtual Hard Disks" -Verbose -Confirm:$False   -GenerateNewId
if ($? -ne "True") {
    Write-Output "Error while importing the VM" | Out-File -Append $summaryLog
    return $false
}

Write-Output "VM ${vmName} has imported back successfully"

#
# Check that the imported VM has a snapshot 'TestExport', apply the snapshot and start the VM.
#
$VMs = Get-VM -Name $vmName -ComputerName $hvServer

$newName = "Imported_" + $vmName

foreach ($Vm in $VMs) {
   if ($ExportedVMID -ne $($Vm.VMId)) {
       $ImportedVM = $Vm.VMId
       Get-VM -Id $Vm.VMId | Rename-VM -NewName $newName
       break
   }
}

Get-VMSnapshot -VMName $newName -ComputerName $hvServer -Name "TestExport" | Restore-VMSnapshot -Confirm:$False -Verbose
if ($? -ne "True") {
    Write-Output "Error while applying the snapshot to imported VM $ImportedVM" | Out-File -Append $summaryLog
    return $false
}

#
# Verify that the imported VM has started successfully
#
Write-Host "Starting the VM $newName and waiting for the heartbeat..."

if ((Get-VM -ComputerName $hvServer -Name $newName).State -eq "Off") {
    Start-VM -ComputerName $hvServer -Name $newName
}

While ((Get-VM -ComputerName $hvServer -Name $newName).State -eq "On") {
    Write-Host "." -NoNewLine
    Start-Sleep -Seconds 5
}

do { 
    Start-Sleep -Seconds 5 
} until ((Get-VMIntegrationService $newName | ?{$_.name -eq "Heartbeat"}).PrimaryStatusDescription -eq "OK")

Write-Output "Imported VM ${newName} has a snapshot TestExport, applied the snapshot and VM started successfully"


Stop-VM -Name $newName -ComputerName $hvServer -Force -Verbose
if ($? -ne "True") {
    Write-Output "Error while stopping the VM" | Out-File -Append $summaryLog
    return $false
}

Write-Output "VM exported with a new snapshot and imported back successfully" | Out-File -Append $summaryLog

#
# Cleanup - stop the imported VM, remove it and delete the export folder.
#
Remove-VM -Name $newName -ComputerName $hvServer -Force -Verbose
if ($? -ne "True") {
    Write-Output "Error while removing the Imported VM" | Out-File -Append $summaryLog
    return $false
}
else {
    Write-Output "Imported VM Removed, test completed" | Out-File -Append $summaryLog
    $retVal = $True
}

Remove-Item -Path "${vmPath}" -Recurse -Force
if ($? -ne "True") {
    Write-Output "Error while deleting the export folder trying again"
    del -Recurse -Path "${vmPath}" -Force
}

return $retVal