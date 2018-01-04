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
    Setup script that will add the Decryption VHD to VM.

.Description
    This is a setup script that will run before the encrypted VM 
    is booted.
    The script will check if the VHD is already initialized in the
    host. If it's already initialized, it will just proceed with add
    the passthrough disk to the VM.

    A typical XML definition for this test case would look similar
    to the following:
    <test>
        <testName>Install_lsvm</testName>
        <setupScript>setupScripts\Shielded_Add_DecryptVHD.ps1</setupScript>
        <testScript>setupscripts\Shielded_install_lsvm.ps1</testScript>
        <files>remote-scripts/ica/utils.sh</files>
        <testParams>
            <param>TC_COVERED=LSVM-INSTALL</param>
        </testParams>
        <cleanupScript>setupScripts\Shielded_Remove_DecryptVHD.ps1</cleanupScript>
        <timeout>600</timeout>
        <onError>Abort</onError>
        <noReboot>True</noReboot>
    </test>
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

############################################################################
#
# Main script
#
############################################################################

# Check input arguments
if ($vmName -eq $null -or $vmName.Length -eq 0) {
    "Error: VM name is null"
    return $false
}

if ($hvServer -eq $null -or $hvServer.Length -eq 0) {
    "Error: hvServer is null"
    return $false
}

if ($testParams -eq $null -or $testParams.Length -lt 3) {
    "Error: No testParams provided"
    "Shielded_Add_decryptVHD.ps1 requires test params"
    return $false
}

# Source TCUtils
. .\setupScripts\TCUtils.ps1

# Parse the testParams string
$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")
    
    switch ($fields[0].Trim()) {
        "rootDir"   { $rootDir = $fields[1].Trim() }
        "sshKey" { $sshKey  = $fields[1].Trim() }
        "ipv4"   {$ipv4 = $fields[1].Trim()}
        "decrypt_vhd_folder"  {$decrypt_vhd = $fields[1].Trim()}
        default  {}
    }
}

# Check if the Decrypt VHD is already mounted
Test-Path $decrypt_vhd
if (-not $?) {
    Write-Output "Error: Folder $decrypt_vhd does not exist!"
    $retVal = $false
}

$vhd_name = (Get-ChildItem $decrypt_vhd).Name
$sts = $(get-disk).Location -match "${vhd_name}"

# If it's not mounted, add it to the host
if ([string]::IsNullOrEmpty($sts)) {
    # Get default VHD path
    $hostInfo = Get-VMHost -ComputerName $hvServer
    if (-not $hostInfo) {
        Write-Output "ERROR: Unable to collect Hyper-V settings for ${hvServer}"
        return $false
    }

    $defaultVhdPath = $hostInfo.VirtualHardDiskPath
    if (-not $defaultVhdPath.EndsWith("\")) {
        $defaultVhdPath += "\"
    }

    # Copy Decrypt VHD to the default VHD path
    $decrypt_vhd_path = Get-ChildItem $decrypt_vhd

    Copy-Item -Path $decrypt_vhd_path.FullName -Destination $defaultVhdPath -Force
    if (-not $?) {
        Write-Output "Error: Failed to copy $decrypt_vhd.Name from $lsvm_folder to $rootDir"
        return $false
    }

    Write-Output "Sucessfully copied $decrypt_vhd to $defaultVhdPath"

    # Mount the vhd
    $local_decrypt_vhd = $defaultVhdPath + $decrypt_vhd_path.Name
    $decrypt_vhd_mounted = Get-VHD $local_decrypt_vhd | Mount-VHD -Passthru
    if (-not $?) {
        Write-Output "Error: Failed to mount VHD"
        return $false
    }

    Get-Disk $decrypt_vhd_mounted.Number | Set-Disk -IsOffline $true
    if (-not $?) {
        Write-Output "Error: Failed to set the VHD offline"
        return $false
    }
}

$disks = Get-Disk
foreach ($disk in $disks) {
    $sts = $disk.Location -match "${vhd_name}"
    if ($sts) {
        $disk_number = $disk.number
        Write-Output "Decryption VHD Number is $disk_number"
    }
}

if ([string]::IsNullOrEmpty($disk_number)) {
    Write-Output "Error: A decryption VHD was not found mounted in the host. Aborting test"
    return $false 
}
else {
    Get-Disk $disk_number | Add-VMHardDiskDrive -VMName $vmName
    if (-not $?) {
        Write-Output "Failed to add Passthrough Decrypt VHD to $vmName" 
        return $false 
    }
    else {
        Write-Output "Successfully added Passthrough Decrypt VHD to $vmName" 
        return $true
    }
}