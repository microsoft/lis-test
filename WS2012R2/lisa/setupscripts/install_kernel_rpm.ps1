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
    Install MSFT kernel on a RHEL or Ubuntu
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

#
# Main script
#
# Check input arguments
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
        "rootDir"   { $rootDir = $fields[1].Trim() }
        "sshKey" { $sshKey  = $fields[1].Trim() }
        "ipv4"   {$ipv4 = $fields[1].Trim()}
        "distro"   {$distro = $fields[1].Trim()}
		"localPath"   {$localPath = $fields[1].Trim()}
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

$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue

# Source TCUtils.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1")
{
    . .\setupScripts\TCUtils.ps1
}
else
{
    "ERROR: Could not find setupScripts\TCUtils.ps1"
    return $false
}
$kernel = "test-artifacts"
# Send files to VM
if ($distro -eq "rhel" -or $distro -eq "centos") {
    $fileExtension = "rpm"
}
if ($distro -eq "ubuntu") {
    $fileExtension = "deb"
}
if (Test-Path $localPath\*.$fileExtension)
{
    $files = Get-ChildItem $localPath -Filter *.${fileExtension}
}
else {
    $test = (ls $localPath) #########
    Write-Output "Error: $fileExtension files are not present! $test" | Tee-Object -Append -file $summaryLog
    return $false
}

SendCommandToVM $ipv4 $sshKey "mkdir /tmp/$kernel/"
foreach ($file in $files){
    $filePath = $file.FullName

    # Copy file to VM
    SendFileToVM $ipv4 $sshKey $filePath "/tmp/$kernel/"

    Start-Sleep -s 1
}
Write-Output "All files have been sent to VM. Will proceed with installing the new kernel" | Tee-Object -Append -file $summaryLog

if ($distro -eq "rhel" -or $distro -or $distro -eq "centos") {
    # Install RPMs
    SendCommandToVM $ipv4 $sshKey "yum localinstall -y /tmp/$kernel/kernel-*"
	SendCommandToVM $ipv4 $sshKey "yum localinstall -y /tmp/$kernel/msft-daemons-*"
    Start-Sleep -s 100

    # Update daemon startup paths
    SendCommandToVM $ipv4 $sshKey "sed -i 's,ExecStart=/usr/sbin/hypervkvpd,ExecStart=/usr/sbin/hypervkvpd -n,' /usr/lib/systemd/system/hypervkvpd.service"
    SendCommandToVM $ipv4 $sshKey "sed -i 's,ExecStart=/usr/sbin/hypervvssd,ExecStart=/usr/sbin/hypervvssd -n,' /usr/lib/systemd/system/hypervvssd.service"
    SendCommandToVM $ipv4 $sshKey "sed -i 's,ExecStart=/usr/sbin/hypervfcopyd,ExecStart=/usr/sbin/hypervfcopyd -n,' /usr/lib/systemd/system/hypervfcopyd.service"

    # Modify GRUB2
    SendCommandToVM $ipv4 $sshKey "grub2-mkconfig -o /boot/grub2/grub.cfg ; grub2-set-default 0"

    # Modify GRUB
    Start-Sleep -s 20
}
if ($distro -eq "ubuntu") {
    # Install deb packages & extract source files
    SendCommandToVM $ipv4 $sshKey "apt -y remove linux-cloud-tools-common"
    SendCommandToVM $ipv4 $sshKey "dpkg -i /tmp/$kernel/linux-*image-*"
	SendCommandToVM $ipv4 $sshKey "dpkg -i /tmp/$kernel/*hyperv-daemons*"
    Start-Sleep -s 120
}

# Restart VM and check daemons
Start-Sleep -s 10
Restart-VM -VMName $vmName -ComputerName $hvServer -Force
$sts = WaitForVMToStartKVP $vmName $hvServer 100
if( -not $sts[-1]){
    "Error: VM $vmName has not booted after the restart" | Tee-Object -Append -file $summaryLog
    return $False
}
