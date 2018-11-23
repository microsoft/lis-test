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
# PURPOSE, MERCHANTABILITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################

<#
.Synopsis
    This script handles pretest item copy to the specified vm.

.Description
    The script will copy a the latest item at a specific location to the test vm.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\copyLatestItem.ps1 -testParams testParams
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

if (-not $testParams) {
    "Error: No testParams provided!"
    return $False
}

#
# Find the testParams required
#
$itemLoc = $null
$item = $null
$localDest = $null
$sshKey = $null

$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")

    if ($fields[0].Trim() -eq "sshKey") {
        $sshKey = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "itemLoc") {
        $itemLoc = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "item") {
        $item = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "localDest") {
        $localDest = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "RootDir") {
        $rootDir = $fields[1].Trim()
    }
}

$vmName
$sshKey
$hvServer
$rootDir
$localDest
$item
$itemLoc

# Checking the required arguments
if (-not $vmName) {
    "Error: vmName is null!"
    return $False
}
if (-not $sshKey) {
    "Error: sshKey is null!"
    return $False
}
if ($hvServer -eq $null) {
    "Error: hvServer is null"
    return $retVal
}
if (-not $itemLoc) {
    "Error: itemLoc is null!"
    return $False
}
if (-not $item) {
    "Error: item is null!"
    return $False
}
if (-not $localDest) {
    "Error: localDest is null!"
    return $False
}
if (-not $rootDir) {
    "Error: rootDir is null!"
    return $False
}
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

Set-Location $rootDir
# Cleanup leftover items
Remove-Item -Path (join-path $localDest $item) -Force

$latest_item = Get-ChildItem -path $itemLoc -Filter "$item"

if (-not $latest_item) {
    "Error: No new item found. Exiting."
    return $False
}

Copy-Item $latest_item.FullName -Destination (join-path $rootDir $localDest)
if (-not $?) {
    "Error: Could not copy the latest item."
    return $False
}
# Source TCUitls.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
}
else {
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}

$vm_ip = GetIPv4 $vmName $hvServer
$itemName = (Get-ChildItem -path $localDest -Filter "$item" |
        Where-Object { -not $_.PSIsContainer } |
        Sort-Object -Property $_.CreationTime |
        Select-Object -last 1).Name

if (-not (Test-Path $localDest\$itemName)) {
    "Error: Could not find $localDest\$itemName"
}
$retVal = SendFileToVM $vm_ip $sshKey ".\$localDest\$itemName" "/root/$tarName"
# check the return Value of SendFileToVM
if (-not $retVal) {
    Write-Output "Error: Failed to send $item to $vmName."
    return $false
}

return $True
