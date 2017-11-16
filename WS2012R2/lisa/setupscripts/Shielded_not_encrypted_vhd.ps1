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
    Test lsvmprep on a test VM that has an unencrypted VHD.

.Description
    Install lsvmtools on a VM that has an unencrypted VHD and check if
    lsvmprep fails

.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParam
    Semicolon separated list of test parameters.

.Example
    .\Shielded_verify_unencrypted_vhd.ps1 "testVM" "localhost" " sshkey= ; ipv4= ; rootDir= ; TC_COVERED= "
#>

param ([String] $vmName, [String] $hvServer, [String] $testParams)

function Cleanup([string]$childVMName, [string]$hvServer)
{
    # Clean up
    $sts = Stop-VM -Name $childVMName -ComputerName $hvServer -TurnOff

    # Delete New VM created
    $sts = Remove-VM -Name $childVMName -ComputerName $hvServer -Confirm:$false -Force
}
#############################################################
#
# Main script body
#
#############################################################

if ($vmName -eq $null) {
    Write-Output"Error: VM name is null"
    return $False
}

if ($hvServer -eq $null) {
    Write-Output "Error: hvServer is null"
    return $False
}

$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")
    
    switch ($fields[0].Trim()) {
        "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
        "rootDir"   { $rootDir = $fields[1].Trim() }
        "sshKey" { $sshKey  = $fields[1].Trim() }
        "ipv4"   {$ipv4 = $fields[1].Trim()}
        "lsvm_folder_path"   {$lsvm_folder = $fields[1].Trim()}
        "rhel_folder_path"   {$rhel_folder = $fields[1].Trim()}
        "sles_folder_path"   {$sles_folder = $fields[1].Trim()}
        "ubuntu_folder_path"   {$ubuntu_folder = $fields[1].Trim()}
        default  {}
    }
}

if ($null -eq $sshKey) {
    Write-Output "Error: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4) {
    Write-Output "Error: Test parameter ipv4 was not specified"
    return $False
}

if (-not $rootDir) {
    Write-Output "Warn : rootdir was not specified"
}
else {
    cd $rootDir
}

# Source TCUitls.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
}
else {
    "ERROR: Could not find setupScripts\TCUtils.ps1"
    return $false
}

$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Copy lsvmtools to root folder
Test-Path $lsvm_folder
if (-not $?) {
    Write-Output "Error: Folder $lsvm_folder does not exist!" | Tee-Object -Append -file $summaryLog
    return $false
}

$rpm = Get-ChildItem $lsvm_folder -Filter *.rpm
$deb = Get-ChildItem $lsvm_folder -Filter *.deb

Copy-Item -Path $rpm.FullName -Destination . -Force
if (-not $?) {
    Write-Output "Error: Failed to copy rpm from $lsvm_folder to $rootDir" | Tee-Object -Append -file $summaryLog
    return $false
}

Copy-Item -Path $deb.FullName -Destination . -Force
if (-not $?) {
    Write-Output "Error: Failed to copy deb from $lsvm_folder to $rootDir" | Tee-Object -Append -file $summaryLog
    return $false
}

# Get distro. Once we know the distro, we can create an unencrypted VM matching that distro
$distro = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "dos2unix utils.sh && . utils.sh && GetDistro && echo `$DISTRO"
$fileExtension = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "dos2unix utils.sh && . utils.sh && GetOSVersion && echo `$os_PACKAGE"

switch -wildcard ($distro)
{
    redhat* {
        Write-Output "RHEL will be tested" | Tee-Object -Append -file $summaryLog
        $vhd_path = $rhel_folder
    }
    centos* {
        Write-Output "RHEL will be tested" | Tee-Object -Append -file $summaryLog
        $vhd_path = $rhel_folder
    }
    suse* {
        Write-Output "SLES will be tested" | Tee-Object -Append -file $summaryLog
        $vhd_path = $sles_folder
    }
    ubuntu* {
        Write-Output "Ubuntu will be tested" | Tee-Object -Append -file $summaryLog
        $vhd_path = $ubuntu_folder
    }
    default {
        Write-output "Error: Could not determine distro" | Tee-Object -Append -file $summaryLog
        return $false
    }
}

# Stopping VM
Write-Host "Waiting for VM $vmName to stop..."
if ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Off") {
    Stop-VM -ComputerName $hvServer -Name $vmName -Force -Confirm:$false
}

# Waiting until the VM is off
if (-not (WaitForVmToStop $vmName $hvServer 300)) {
    Write-Output "Error: Unable to stop VM" | Tee-Object -Append -file $summaryLog
    return $False
}

# Get information about the main VM
$vm = Get-VM -Name $vmName -ComputerName $hvServer

$VMNetAdapter = Get-VMNetworkAdapter $vmName -ComputerName $hvServer
if (-not $?) {
    Write-Output "Error: Get-VMNetworkAdapter for $vmName failed" | Tee-Object -Append -file $summaryLog
    return $false
}

# Copy VHD to default VHD path
# Get default vhd path
$hostInfo = Get-VMHost -ComputerName $hvServer
if (-not $hostInfo) {
    Write-Output "ERROR: Unable to collect Hyper-V settings for ${hvServer}" | Tee-Object -Append -file $summaryLog
    return $false
}

$defaultVhdPath = $hostInfo.VirtualHardDiskPath
if (-not $defaultVhdPath.EndsWith("\")) {
    $defaultVhdPath += "\"
}
$secondary_vhd = $defaultVhdPath + $vmName + "_notEncrypted.vhdx"

# Test path of vhd that will be copied
Test-Path $vhd_path
if (-not $?) {
    Write-Output "Error: Folder $vhd_path does not exist! " | Tee-Object -Append -file $summaryLog
    return $false
}

# Copy VHD
$vhd_path = Get-ChildItem $vhd_path
Copy-Item -Path $vhd_path.FullName -Destination $secondary_vhd -Force
if (-not $?) {
    Write-Output "Error: Failed to copy $vhd_path to $defaultVhdPath" | Tee-Object -Append -file $summaryLog
    return $false
}
Write-Output "VHD will be copied to $secondary_vhd"

# Create VM
$newVm = New-VM -Name 'TestVM_Not_Encrypted' -ComputerName $hvServer -VHDPath $secondary_vhd -MemoryStartupBytes 2048MB -SwitchName $VMNetAdapter[0].SwitchName -Generation 2
if (-not $?) {
   Write-Output "Error: Creating New VM $childVMName" | Tee-Object -Append -file $summaryLog
   return $False
}

# Disable secure boot
Set-VMFirmware -VMName 'TestVM_Not_Encrypted' -ComputerName $hvServer -EnableSecureBoot Off
if(-not $?) {
    Write-Output "Error: Unable to disable secure boot" | Tee-Object -Append -file $summaryLog
    Cleanup 'TestVM_Not_Encrypted' $hvServer
    return $false
}

# Start non-encrypted VM
if (Get-VM -Name 'TestVM_Not_Encrypted' -ComputerName $hvServer |  Where { $_.State -notlike "Running" }) {
    Start-VM -Name 'TestVM_Not_Encrypted' -ComputerName $hvServer
    if (-not $?) {
        "Error: Failed to start VM ${vmName}" | Tee-Object -Append -file $summaryLog
        Cleanup 'TestVM_Not_Encrypted' $hvServer
        return $False
    }
}

$timeout = 200 # seconds
if (-not (WaitForVMToStartKVP 'TestVM_Not_Encrypted' $hvServer $timeout)) {
    "Warning: TestVM_Not_Encrypted never started KVP" | Tee-Object -Append -file $summaryLog
    Cleanup 'TestVM_Not_Encrypted' $hvServer
    return $False
}

# Get IP from VM2
$vm2ipv4 = GetIPv4 'TestVM_Not_Encrypted' $hvServer
"TestVM_Not_Encrypted IP address: $vm2ipv4"

# Send lsvmtools to the secondary VM
$filePath = Get-ChildItem * -Filter *.${fileExtension}
SendFileToVM $vm2ipv4 $sshKey $filePath.FullName "/tmp/"

# Install lsvmtools
if ($fileExtension -eq "deb") {
    SendCommandToVM $vm2ipv4 $sshKey "cd /tmp && dpkg -i lsvm*"    
}
if ($fileExtension -eq "rpm") {
    SendCommandToVM $vm2ipv4 $sshKey "cd /tmp && rpm -ivh lsvm*"    
}

# Run lsvmprep
$sts = SendCommandToVM $vm2ipv4 $sshKey "cd /opt/lsvm* && yes YES | ./lsvmprep"
Cleanup 'TestVM_Not_Encrypted' $hvServer

if (-not $sts) {
    Write-Output 'lsvmprep failed as expected!' | Tee-Object -Append -file $summaryLog
    return $true  
}
else {
    Write-Output 'Error: lsvmprep was successful and should have failed!' | Tee-Object -Append -file $summaryLog
    return $false    
}