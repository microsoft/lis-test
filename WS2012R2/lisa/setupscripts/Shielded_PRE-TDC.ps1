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
#
# Linux Shielded VMs PRE-TDC automation functions
#

# Import TCUtils.ps1
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
}
else {
    "ERROR: Could not find setupScripts\TCUtils.ps1"
    return $false
}

# Import NET_Utils.ps1
if (Test-Path ".\setupScripts\NET_UTILS.ps1") {
    . .\setupScripts\NET_UTILS.ps1
}
else {
    "ERROR: Could not find setupScripts\NET_UTILS.ps1"
    return $false
}

# Import Shielded_TDC.ps1
if (Test-Path ".\setupScripts\Shielded_TDC.ps1") {
    . .\setupScripts\Shielded_TDC.ps1
}
else {
    "ERROR: Could not find setupScripts\Shielded_TDC.ps1"
    return $false
}

# Import Shielded_PRO.ps1
if (Test-Path ".\setupScripts\Shielded_PRO.ps1") {
    . .\setupScripts\Shielded_PRO.ps1
}
else {
    "ERROR: Could not find setupScripts\Shielded_PRO.ps1"
    return $false
}

# Import Shielded_DEP.ps1
if (Test-Path ".\setupScripts\Shielded_DEP.ps1") {
    . .\setupScripts\Shielded_DEP.ps1
}
else {
    "ERROR: Could not find setupScripts\Shielded_DEP.ps1"
    return $false
}

# Copy template from share to default VHDx path
function Create_Test_VM ([string] $encrypted_vhd)
{
    # Test dependency VHDx path
    $sts = Test-Path $encrypted_vhd
    if (-not $?) {
        return $false
    }

    # Make a copy of the encypted VHDx for testing only
    $destinationVHD = $defaultVhdPath + "PRE-TDC_test.vhdx"
    Set-Variable -Name 'destinationVHD' -Value $destinationVHD -Scope Global
    Copy-Item -Path $(Get-ChildItem $encrypted_vhd -Filter *.vhdx).FullName -Destination $destinationVHD -Force
    if (-not $?) {
        return $false
    }

    # Make a new VM
    $newVm = New-VM -Name 'Shielded_PRE-TDC' -Generation 2 -VHDPath $destinationVHD -MemoryStartupBytes 4096MB -SwitchName 'External'
    if (-not $?) {
        return $false
    }
    Set-VMProcessor 'Shielded_PRE-TDC' -Count 4 -CompatibilityForMigrationEnabled $true
	Set-VMFirmware -VMName 'Shielded_PRE-TDC' -EnableSecureBoot Off
    return $true
}

# Attach decryption drive to the test VM
function AttachDecryptVHDx ([string] $decrypt)
{
    $rootDir = $pwd.Path
    # Use script to attach decryption VHDx
    $sts = ./setupScripts/Shielded_Add_DecryptVHD.ps1 -vmName 'Shielded_PRE-TDC' -hvServer 'localhost' -testParams "rootDir=${rootDir}; decrypt_vhd_folder=${decrypt}"
    if (-not $sts[-1]) {
        return $false
    }

    # Start VM and get IP
    $ipv4 = StartVM 'Shielded_PRE-TDC' 'localhost'
    if (-not (isValidIPv4 $ipv4)) {
        return $false
    }

    return $ipv4
}

# Install lsvm
function Install_lsvm ([string]$sshKey, [string]$ipv4, [string]$lsvm_folder_path)
{
    $rootDir = $pwd.Path

    # Get KVP data
    $Vm = Get-WmiObject -ComputerName 'localhost' -Namespace root\virtualization\v2 -Query "Select * From Msvm_ComputerSystem Where ElementName='Shielded_PRE-TDC'"
	$Kvp = Get-WmiObject -ComputerName 'localhost' -Namespace root\virtualization\v2 -Query "Associators of {$Vm} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent"
	$kvpData = $Kvp.GuestIntrinsicExchangeItems
	$kvpDict = KvpToDict $kvpData
	$kvpDict | Export-CliXml kvp_results.xml -Force
	
    # Install LSVM script
    $sts = ./setupScripts/Shielded_install_lsvm.ps1 -vmName 'Shielded_PRE-TDC' -hvServer 'localhost' -testParams "rootDir=${rootDir}; lsvm_folder_path=${lsvm_folder_path}; ipv4=${ipv4}; sshKey=${sshKey}; snapshotName=ICABase"
    if (-not $sts[-1]) {
        return $false
    }

    return $sts[-1]
}

# Attach decryption drive to the test VM
function DettachDecryptVHDx
{
    $rootDir = $pwd.Path
    # Use script to attach decryption VHDx
    $sts = ./setupScripts/Shielded_Remove_DecryptVHD.ps1 -vmName 'Shielded_PRE-TDC' -hvServer 'localhost' -testParams "rootDir=${rootDir}; decrypt_vhd_folder=${decrypt}"
    if (-not $sts[-1]) {
        return $false
    }

    return $sts[-1]
}

function Verify_script ([string] $ipv4, [string] $sshKey, [string] $scriptName)
{
    # Run test script
    $retVal = SendCommandToVM $ipv4 $sshKey "bash ${scriptName} && cat state.txt"
    if (-not $retVal) {
        return $false
    }
    # Check status
    $state = .\bin\plink.exe -i ssh\$sshKey root@$ipv4 "cat state.txt"
    if ($state -ne "TestCompleted") {
        return $false
    }

    # Stop VM
    StopVM 'Shielded_PRE-TDC' "localhost"

    return $true
}

function Verify_not_encrypted ([string]$ipv4, [string]$sshKey, [string]$rhel_folder_path, [string]$sles_folder_path, [string]$ubuntu_folder_path, [string]$lsvm_folder_path)
{
    $rootDir = $pwd.Path
    # Run test script
    $sts = ./setupScripts/Shielded_not_encrypted_vhd.ps1 -vmName 'Shielded_PRE-TDC' -hvServer 'localhost' `
        -testParams "rootDir=${rootDir}; lsvm_folder_path=${lsvm_folder_path}; ipv4=${ipv4}; sshKey=${sshKey}; sles_folder_path=${sles_folder_path}; ubuntu_folder_path=${ubuntu_folder_path}; rhel_folder_path={$rhel_folder_path}"
    if (-not $sts[-1]) {
        return $false
    }

    return $sts[-1]    
}

function Verify_passphrase_noSpace ([string] $ipv4, [string] $sshKey, [string] $scriptName, [string] $change_passphrase, [string] $fill_disk)
{
    # Append data to constants.sh
    $retVal = SendCommandToVM $ipv4 $sshKey "echo 'change_passphrase=${change_passphrase}' >> constants.sh"
    $retVal = SendCommandToVM $ipv4 $sshKey "echo 'fill_disk=${fill_disk}' >> constants.sh "

    # Run test script
    $retVal = SendCommandToVM $ipv4 $sshKey "bash ${scriptName} && cat state.txt"
    if (-not $retVal) {
        return $false
    }
    # Check status
    $state = .\bin\plink.exe -i ssh\$sshKey root@$ipv4 "cat state.txt"
    if ($state -ne "TestCompleted") {
        return $false
    }

    # Stop VM
    StopVM 'Shielded_PRE-TDC' "localhost"

    return $true
}

function Prepare_VM ([string] $ipv4, [string] $sshKey)
{
	$rootDir = $pwd.Path
	
    # Run test script
    $sts = ./setupScripts/Shielded_template_prepare.ps1 -vmName 'Shielded_PRE-TDC' -hvServer 'localhost' `
        -testParams "rootDir=${rootDir}; sshKey=${sshKey}; snapshotName=ICABase"
    if (-not $sts[-1]) {
        return $false
    }

    return $sts[-1]    
}