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
    Mount an ISO file in the VM default DVD drive.

.Description
    Mount a .iso in the default DVD drive.

.Parameter vmName
    Name of the VM with the DVD drive to mount.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParam
    Semicolon separated list of test parameters.

.Example
    .\InsertIsoInDvd.ps1 "testVM" "localhost"
#>

param ([String] $vmName, [String] $hvServer, [String] $testParams)

# any small ISO file URL can be used
# using a PowerPC ISO, which does not boot on Gen1/Gen2 VMs
# For other bootable media must ensure that boot from CD is not the first option
$url = "http://ports.ubuntu.com/dists/trusty/main/installer-powerpc/current/images/powerpc/netboot/mini.iso"
$retVal = $False
$hotAdd = $False

#######################################################################
#
# Main script body
#
#######################################################################

# Check arguments
if (-not $vmName) {
    "Error: Missing vmName argument"
    return $False
}

if (-not $hvServer) {
    "Error: Missing hvServer argument"
    return $False
}

if (-not $testParams) {
    "Error: Missing testParams argument"
    return $False
}

# Source TCUtils.ps1 for common functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
    "Info: Sourced TCUtils.ps1"
}
else {
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}

#
# Extract the testParams
#
$params = $testParams.Split(';')
foreach ($p in $params) {
    if ($p.Trim().Length -eq 0) {
        continue
    }
    $tokens = $p.Trim().Split('=')

    if ($tokens.Length -ne 2) {
    # Just ignore it
    continue
    }

    $lValue = $tokens[0].Trim()
    $rValue = $tokens[1].Trim()

    if ($lValue -eq "HotAdd") {
        $hotAdd = $rValue
    }
}

$error.Clear()

$vmGen = GetVMGeneration $vmName $hvServer
if ( $hotAdd -eq "True" -and $vmGen -eq 1) {
    "Info: Generation 1 VM does not support hot add DVD, please skip this case in the test script"
    return $True
}

#
# There should be only one DVD unit by default
#
$dvd = Get-VMDvdDrive $vmName -ComputerName $hvServer
if ( $dvd ) {
    try {
        Remove-VMDvdDrive $dvd -Confirm:$False
    } catch {
        "Error: Cannot remove DVD drive from ${vmName}"
        $error[0].Exception
        return $False
    }
}

#
# Get Hyper-V VHD path
#
$obj = Get-WmiObject -ComputerName $hvServer -Namespace "root\virtualization\v2" -Class "MsVM_VirtualSystemManagementServiceSettingData"
$defaultVhdPath = $obj.DefaultVirtualHardDiskPath
if (-not $defaultVhdPath) {
    "Error: Unable to determine VhdDefaultPath on Hyper-V server ${hvServer}"
    $error[0].Exception
    return $False
}
if (-not $defaultVhdPath.EndsWith("\")) {
    $defaultVhdPath += "\"
}
$isoPath = $defaultVhdPath + "${vmName}_CDtest.iso"

$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("$url","$isoPath")

try {
    GetRemoteFileInfo $isoPath $hvServer
} catch {
    "Error: The .iso file $isoPath could not be found!"
    return $False
}

#
# Insert the .iso file into the VMs DVD drive
#
if ($vmGen -eq 1) {
    Add-VMDvdDrive -VMName $vmName -Path $isoPath -ControllerNumber 1 -ControllerLocation 1 -ComputerName $hvServer -Confirm:$False
} else {
    Add-VMDvdDrive -VMName $vmName -Path $isoPath -ControllerNumber 0 -ControllerLocation 1 -ComputerName $hvServer -Confirm:$False
}

if ($? -ne "True") {
    "Error: Unable to mount the ISO file!"
    $error[0].Exception
    return $False
} else {
    $retVal = $True
}

return $retVal
