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
 This script will gather information about the Mellanox driver from the host.

.Description
 This script will use the MLNXProvider module to collect information about the
 Mellanox driver installed on the host and will output it to HostMellanoxInfo.log

 .Parameter vmName
     Name of the test VM.

 .Parameter hvServer
     Name of the Hyper-V server hosting the VM.

.Parameter testParams
 Test data for this test case

.Example
 setupScripts\SR-IOV_GetMLNXInfo.ps1 -vmName vmNmae -hvServer hvserver -testParams "rootDir=C:\myFolder\"
#>

param ([String] $vmName, [String] $hvServer, [string] $testParams)

$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")
    if ($fields[0].Trim() -eq "rootDir") {
        $rootDir = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "TestLogDir") {
        $logPath = $fields[1].Trim()
    }
}

# Change directory
cd $rootDir

$summaryLog = $logPath + "\" + "HostMellanoxInfo.log"
if (Test-Path $summaryLog) {
    del $summaryLog
}

# Work around "Kerberos Double Hop" issue
# Use fresh identity (if defined in environment) instead of delegation
if($env:HostUser -and $env:HostPassword){
    $SecurePass = $env:HostPassword| ConvertTo-SecureString -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $env:HostUser, $SecurePass
    $remoteSession = New-PSSession -ComputerName $hvServer -Credential $cred
}
else{
    $remoteSession = New-PSSession -ComputerName $hvServer
}

$checkModule = Get-Module -ListAvailable -PSSession $remoteSession | Select-String -Pattern MLNXProvider -quiet
if ($checkModule) {
    Import-Module MLNXProvider -PSSession $remoteSession
} else {
    Write-Output "Error: No Mellanox module found."
    Remove-PSSession $remoteSession -ErrorAction SilentlyContinue
    Exit 0
}

# After import-module, the imported commands run implicitly in the current session
$driverVersion = (Get-MLNXPCIDevice).DriverVersion
if ($? -ne "True") {
    $driverVersion = "Error: Cannot get driver version."
}

$firmwareVersion = (Get-MlnxFirmwareIdentity).VersionString
if ($? -ne "True") {
    $firmwareVersion = "Error: Cannot get firmware version."
}

$linkSpeed = (Get-MlnxNetAdapter | where {$_.Status -eq 'IfOperStatusUp'}).Speed
if ($? -ne "True") {
    $linkSpeed = "Error: Cannot get link speed."
}

$port1NumVFS = (Get-MlnxPCIDeviceSriovSetting).SriovPort1NumVFs
if ($? -ne "True") {
    $port1NumVFS = "Error: Cannot get SriovPort1NumVFs."
}

Write-Output "Driver Version: $driverVersion" | Tee-Object -Append -file $summaryLog
Write-Output "Firmware Version: $firmwareVersion" | Tee-Object -Append -file $summaryLog
Write-Output "Link Speed: $linkSpeed" | Tee-Object -Append -file $summaryLog
Write-Output "SriovPort1NumVFs: $port1NumVFS" | Tee-Object -Append -file $summaryLog

# If no VM has SR-IOV enabled, the following will return NULL
Get-NetAdapterSriovVf | Select-Object name,FunctionID,VPortID,VmFriendlyName | Format-Table | Tee-Object -Append -file $summaryLog
if ($? -ne "True") {
    $vmFriendlyName = "Error: Cannot get VM Friendly name."
}

Remove-PSSession $remoteSession -ErrorAction SilentlyContinue
return $true
