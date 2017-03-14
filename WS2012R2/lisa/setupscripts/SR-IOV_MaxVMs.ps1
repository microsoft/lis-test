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
    Limit test – 32* VMs, one SR-IOV device each

.Description
    Description:  
    Create 32 Linux VMs on a single Hyper-V host.  Configure each VM to have a single SR-IOV device.
    Verify network connectivity for each VM.
    Steps:
        1.  Create 32 Linux VMs and configure each Linux VM to have a single SR-IOV device.
        2.  Using one of the Linux VMs as the client, use a network file protocol (SCP, NFS, etc) 
        to transfer a small file to each of the remaining VMs.
 
.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

.Example
    <test>
        <testName>Max_VMs</testName>
        <testScript>setupscripts\SR-IOV_MaxVMs.ps1</testScript>
        <files>remote-scripts/ica/utils.sh,remote-scripts/ica/SR-IOV_Utils.sh</files> 
        <setupScript>
            <file>setupscripts\RevertSnapshot.ps1</file>
        </setupScript> 
        <noReboot>False</noReboot>
        <testParams>
            <param>TC_COVERED=SRIOV-22</param>
            <param>REMOTE_USER=root</param>
            <param>VM_NUMBER=32</param>
        </testParams>
        <timeout>10800</timeout>
    </test>
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

function Cleanup($childVMName)
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
#
# Check the required input args are present
#
$netmask = "255.255.255.0"

# Write out test Params
$testParams

if ($hvServer -eq $null) {
    "ERROR: hvServer is null"
    return $False
}

if ($testParams -eq $null) {
    "ERROR: testParams is null"
    return $False
}

#change working directory to root dir
$testParams -match "RootDir=([^;]+)"
if (-not $?) {
    "Mandatory param RootDir=Path; not found!"
    return $false
}

$rootDir = $Matches[1]
if (Test-Path $rootDir) {
    Set-Location -Path $rootDir
    if (-not $?) {
        "ERROR: Could not change directory to $rootDir !"
        return $false
    }
    "Changed working directory to $rootDir"
}
else {
    "ERROR: RootDir = $rootDir is not a valid path"
    return $false
}

# Source TCUitls.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
}
else {
    "ERROR: Could not find setupScripts\TCUtils.ps1"
    return $false
}

# Source NET_UTILS.ps1 for network functions
if (Test-Path ".\setupScripts\NET_UTILS.ps1") {
    . .\setupScripts\NET_UTILS.ps1
}
else {
    "ERROR: Could not find setupScripts\NET_Utils.ps1"
    return $false
}

# Process the test params
$params = $testParams.Split(';')
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {
        "SshKey" { $sshKey = $fields[1].Trim() }
        "ipv4" { $ipv4 = $fields[1].Trim() }   
        "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
        "VM_NUMBER" { $vmNumber = $fields[1].Trim() }
        "REMOTE_USER" { $remoteUser = $fields[1].Trim() }
    }
}

$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Check if there are running old child VMs and stop them
for($i=0; $i -lt $vmNumber; $i++){
    Cleanup "SRIOV_Child${i}"
}

#
# Start creating the 32 child VMs
#
# First, we'll check for the partition with the most resources
$biggestPartition = Get-Partition | Sort-Object "Size" -Descending | Select-Object -First 1
$driveLetter = $biggestPartition.DriveLetter
$folderPath = "${driveLetter}:\SRIOV_ChildVMs"

# Make a new directory on the biggest partition. Here will be copied all child VHDs
If (Test-Path $folderPath){
    Remove-Item $folderPath -Force -Recurse
}
New-Item $folderPath -ItemType Directory

# Stop main VM to get the parent VHD
# Shutdown gracefully so we dont corrupt VHD.
Stop-VM -Name $vmName -ComputerName $hvServer
if (-not $?) {
    Write-Output "Error: Unable to Shut Down VM" | Tee-Object -Append -file $summaryLog
    return $False
}

Start-Sleep -s 10
# Get Parent VHD
$ParentVHD = GetParentVHD $vmName $hvServer
if(-not $ParentVHD) {
    Write-Output "Error getting Parent VHD of VM $vmName" | Tee-Object -Append -file $summaryLog
    return $False
}

# Get information about the main VM
$vm = Get-VM -Name $vmName -ComputerName $hvServer
# Get VM Generation
$vm_gen = $vm.Generation

$VMNetAdapter = Get-VMNetworkAdapter $vmName -ComputerName $hvServer
if (-not $?) {
    Write-Output "Error: Get-VMNetworkAdapter for $vmName failed" | Tee-Object -Append -file $summaryLog
    return $false
}

# Make a specified number of childs from the parent VHD
for($i=0; $i -lt $vmNumber; $i++) {
    $childName = "${folderPath}\SR-IOV_Child_${i}"
    $ChildVHD = CreateChildVHD $ParentVHD $childName $hvServer
    New-Variable -Name "ChildVHD${i}" -Value $ChildVHD

    $childVMName = "SRIOV_Child${i}"
    New-Variable -Name "ChildVM${i}" -Value $childVMName

    $childBondIP = "10.11.12.1${i}"
    New-Variable -Name "ChildBondIP${i}" -Value $childBondIP

    $newVm = New-VM -Name $childVMName -ComputerName $hvServer -VHDPath $ChildVHD -MemoryStartupBytes 1024MB -SwitchName $VMNetAdapter[0].SwitchName -Generation $vm_gen
    if (-not $?) {
       Write-Output "Error: Creating New VM $childVMName" | Tee-Object -Append -file $summaryLog
       return $False
    }

    # Disable secure boot if Gen2
    if ($vm_gen -eq 2) {
        Set-VMFirmware -VMName $childVMName -ComputerName $hvServer -EnableSecureBoot Off
        if(-not $?) {
            Write-Output "Error: Unable to disable secure boot" | Tee-Object -Append -file $summaryLog
            Cleanup $childVMName
            return $false
        }
    }

    ConfigureVMandBond $childVMName $hvServer $sshKey $childBondIP $netmask
}

Write-Output "Child VMs were started and configured " | Tee-Object -Append -file $summaryLog

# Start again main VM and configure it
ConfigureVMandBond $vmName $hvServer $sshKey "10.11.12.1" $netmask

$ipv4 = GetIPv4 $vmName $hvServer 
Write-Output "$vmName IPADDRESS: $ipv4"

#
# Create an 128MB file on test VM
#
Start-Sleep -s 3
$retVal = CreateFileOnVM $ipv4 $sshKey 128
if (-not $retVal)
{
    Write-Output "ERROR: Failed to create a file on vm $vmName (IP: ${ipv4})" | Tee-Object -Append -file $summaryLog
    return $false
}

# For SRIOV_SendFile function to work, constants.sh needs to contain specific information
# This info is appended to constants.sh from here
SendCommandToVM "$ipv4" "$sshKey" "echo 'BOND_IP1=10.11.12.1' >> constants.sh"
SendCommandToVM "$ipv4" "$sshKey" "echo 'sshKey=$sshKey' >> constants.sh"
SendCommandToVM "$ipv4" "$sshKey" "sed -i 's/.ppk//' constants.sh"
SendCommandToVM "$ipv4" "$sshKey" "echo 'REMOTE_USER=$remoteUser' >> constants.sh"

# Send the file to all Child VMs
Start-Sleep -s 10
$failedToSendCount = 0
for($i=0; $i -lt $vmNumber; $i++) {
    $transferStatus = $null
    $childBondIP = Get-Variable -Name "ChildBondIP${i}" -ValueOnly

    SendCommandToVM "$ipv4" "$sshKey" "echo 'BOND_IP2=$childBondIP' >> constants.sh"
    $retVal = SRIOV_SendFile $ipv4 $sshKey 1400
    if (-not $retVal)
    {
        "ERROR: Failed to send the file from vm $vmName to SRIOV_Child${i} after changing state"
        SendCommandToVM $ipv4 $sshKey "head -n -1 constants.sh > temp.txt ; mv temp.txt constants.sh"
        $failedToSendCount++
    }
    else {
        SendCommandToVM $ipv4 $sshKey "head -n -1 constants.sh > temp.txt ; mv temp.txt constants.sh -f"
    }  
}

# Clean all Child VMs
for($i=0; $i -lt $vmNumber; $i++){
    Write-Output "Starting cleanup"
    Cleanup "SRIOV_Child${i}"
}
Remove-Item $folderPath -Force -Recurse

# Check results
Start-Sleep -s 10
if ($failedToSendCount -gt 0) {
    Write-Output "File was not sent to ${failedToSendCount} VMs"
    if ($failedToSendCount -eq $vmNumber){
        Write-Output "ERROR: File was not sent to any of the $vmNumber Child VMs" | Tee-Object -Append -file $summaryLog  
        return $false
    }
}
else {
    Write-Output "File was sent to all ${vmNumber} VMs" | Tee-Object -Append -file $summaryLog
}

return $True