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
   Upload files in VM
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$summaryLog = ("{0}_summary.log" -f @($vmName))
Remove-Item -Force $summaryLog -ErrorAction SilentlyContinue

Write-Output "TEST PARAMS: ${testParams}" `
        | Tee-Object -Append -file $summaryLog

if ($vmName -eq $null) {
    "Error: VM name is null"
    return $False
}

if ($hvServer -eq $null) {
    "Error: hvServer is null"
    return $False
}

$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")

    switch ($fields[0].Trim()) {
        "rootDir" { $rootDir = $fields[1].Trim() }
        "sshKey" { $sshKey  = $fields[1].Trim() }
        "ipv4" { $ipv4 = $fields[1].Trim() }
        "distro" { $distro = $fields[1].Trim() }
        "ARTIFACTS_DIR" { $localPath = $fields[1].Trim() }
        "REMOTE_DIR" { $remoteDir = $fields[1].Trim() }
        default  {}
    }
}

if ($null -eq $sshKey) {
    "Error: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4) {
    "Error: Test parameter ipv4 was not specified"
    return $False
}

if (-not $rootDir) {
    "Warn : rootdir was not specified"
} else {
    Set-Location $rootDir
}

if (-not $remoteDir) {
    $remoteDir = "/tmp/kernel"
} 


# Source TCUtils.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
} else {
    "ERROR: Could not find setupScripts\TCUtils.ps1"
    return $false
}

if (Test-Path $localPath) {
    $files = Get-ChildItem $localPath
} else {
    Write-Output "Error: $fileExtension files are not present! $test" `
        | Tee-Object -Append -file $summaryLog
    return $false
}

SendCommandToVM $ipv4 $sshKey "mkdir $remoteDir"
foreach ($file in $files) {
    $filePath = $file.FullName

    # Copy file to VM
    SendFileToVM $ipv4 $sshKey $filePath "$remoteDir"

    Start-Sleep -s 1
}

Write-Output "All files have been sent to VM. Will proceed with installing the new kernel" `
    | Tee-Object -Append -file $summaryLog

return $true