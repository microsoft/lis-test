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
    Install LSVM on a test VM

.Description
    On CentOS, RHEL and SLES: a rpm file will be uploaded and installed
    On Ubuntu a deb file will be uploaded an installed

.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParam
    Semicolon separated list of test parameters.

.Example
    .\Shielded_install_lsvm.ps1 "testVM" "localhost" " sshkey= ; ipv4= ; rootDir= ; TC_COVERED= "
#>

param ([String] $vmName, [String] $hvServer, [String] $testParams)
#############################################################
#
# Main script body
#
#############################################################

$retVal = $false
if ($vmName -eq $null) {
    "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null) {
    "Error: hvServer is null"
    return $retVal
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
        "snapshotName" { $snapshot = $fields[1].Trim() }
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

# Send lsvmtools to VM
$fileExtension = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "dos2unix utils.sh && . utils.sh && GetOSVersion && echo `$os_PACKAGE"
Write-Output "$fileExtension file will be sent to VM" | Tee-Object -Append -file $summaryLog

$filePath = Get-ChildItem * -Filter *.${fileExtension}
SendFileToVM $ipv4 $sshKey $filePath.FullName "/tmp/"

# Install lsvmtools
if ($fileExtension -eq "deb") {
    SendCommandToVM $ipv4 $sshKey "cd /tmp && dpkg -i lsvm*"    
}
if ($fileExtension -eq "rpm") {
    SendCommandToVM $ipv4 $sshKey "cd /tmp && rpm -ivh lsvm*"    
}

if (-not $?) {
    Write-Output "Error: Failed to install $fileExtension file" | Tee-Object -Append -file $summaryLog
    return $false
} 
else {
    Write-Output "lsvmtools was successfully installed!" | Tee-Object -Append -file $summaryLog
}

Start-sleep -s 3

# Stopping VM to take a checkpoint
Write-Host "Waiting for VM $vmName to stop..."
if ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Off") {
    Stop-VM -ComputerName $hvServer -Name $vmName -Force -Confirm:$false
}

# Waiting until the VM is off
if (-not (WaitForVmToStop $vmName $hvServer 300)) {
    Write-Output "Error: Unable to stop VM"
    return $False
}

# Remove Passthrough disk
Remove-VMHardDiskDrive -ComputerName $hvServer -VMName $vmName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1

# Take checkpoint
Checkpoint-VM -Name $vmName -SnapshotName $snapshot -ComputerName $hvServer
if (-not $?) {
    Write-Output "Error taking snapshot!" | Out-File -Append $summaryLog
    return $False
}
else {
    Write-Output "Checkpoint was created"
    return $true
}