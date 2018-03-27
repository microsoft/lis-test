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
    Uploads a VHD from a VM to a specified store. This will also handle cleanup of older VHDs from the store.
    Note: This script should only be run if the VHD has passed basic tests to ensure that it's a stable build.

.Description
    Reads test params from XML file as follows:

    <param>vhdStore=\\myVhdShare\latestVhds</param>
    <param>uploadName=SLES_12_x64.vhdx</param>

.Parameter vmName
    Name of the test VM on which the VHD resides

.Parameter hvServer
    Name of the Hyper-V server hosting the test VM.

.Parameter testParams
    Test parameters are a way of passing variables into the test case script.
#>

param( [String] $vmName, [String] $hvServer, [String] $testParams )

#######################################################################
#
# Main
#
#######################################################################
$params = $testParams.Split(";")
$vhdStore = ""
$customPrefix = ""
$uploadName = ""
foreach ($p in $params) {
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {
    "vhdStore" { $vhdStore = $fields[1].Trim() }  
    "customPrefix" { $customPrefix = $fields[1].Trim() }
    "uploadName" { $uploadName = $fields[1].Trim() }
    default    {}
    }
}

if (-not (Test-Path $vhdStore)) {
    Write-Error "Could not access VHD store at $vhdStore"
    return $false
}

# Copy VHD to given store
$disk = Get-VMHardDiskDrive -VMName $vmName -ComputerName $hvServer -ControllerLocation 0 -ControllerNumber 0
if (!$disk) {
    Write-Error "Could not find a boot disk at controller 0, number 0"
    return $false
}

$vhdName = $(Get-Item $disk.Path).Name
if ($uploadName) {
    $vhdName = $uploadName
}

$date = Get-Date
$prefix = $date.ToString("yyyy-MM-dd")
if ($customPrefix) { $prefix += "_$customPrefix" }
$vhdName = "$($prefix)_$vhdName"
$destination = Join-Path $vhdStore $vhdName

Write-Host "Uploading VHD $($disk.Path) to $destination ..."
Copy-Item -Path $disk.Path -Destination $destination -Force

if (Test-Path $destination) {
    # Remove any VHDs from the store that are older than a month
    $filesToRemove = Get-ChildItem $vhdStore | 
        Where-Object { ($_.Extension -eq ".vhd" -or $_.Extension -eq ".vhdx") -and $_.LastWriteTime -lt $date.AddDays(-20) }

    $filesToRemove | ForEach-Object {
        Write-Host "Removing old VHD file: $($_.FullName) ..."
        Remove-Item $_.FullName -Force
    }

    $latestFile = Join-Path $vhdStore "latest"
    $vhdName | Out-File -FilePath $latestFile -Force
}

return $true
