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
    Move the VHD to another host, and build a new VM based on this VHD. The SR-IOV should work.

.Description
    Description:  
    Create a new Linux VM from an existing VHDX file that has SR-IOV configured.  
    SR-IOV should be configured correctly and should work when the new VM is booted.
    Steps:
        1.  Configure SR-IOV on a Linux VM and confirm SR-IOV is working.
        2.  Shutdown the VM.
        3.  Make a copy of the VHDX file from this VM.
        4.  Create a second Linux VM using the VHDX file from step 3.
        5.  Boot the second Linux VM.
        6.  Test SR-IOV functionality on the second VM.

.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

.Example
    <test>
        <testName>Move_VHD</testName>
        <testScript>setupscripts\SR-IOV_MoveVHD.ps1</testScript>
        <files>remote-scripts/ica/utils.sh,remote-scripts/ica/SR-IOV_Utils.sh</files> 
        <setupScript>
            <file>setupscripts\RevertSnapshot.ps1</file>
            <file>setupscripts\SR-IOV_enable.ps1</file>
        </setupScript> 
        <noReboot>False</noReboot>
        <testParams>
            <param>NIC=NetworkAdapter,External,SRIOV,001600112800</param>
            <param>TC_COVERED=SRIOV-7</param>
            <param>VF_IP1=10.11.12.31</param>
            <param>VF_IP2=10.11.12.32</param>
            <param>NETMASK=255.255.255.0</param>
            <param>REMOTE_SERVER=hvServer/param>
        </testParams>
        <cleanupScript>setupscripts\SR-IOV_ShutDown_Dependency.ps1</cleanupScript>
        <timeout>2400</timeout>
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
        "REMOTE_SERVER" { $remoteServer = $fields[1].Trim() }
        "VF_IP1" { $vmVF_IP1 = $fields[1].Trim()}
        "VF_IP2" { $vmVF_IP2 = $fields[1].Trim()}
        "NIC"
        {
            $temp = $p.Trim().Split('=')
            if ($temp[0].Trim() -eq "NIC")
            {
                $nicArgs = $temp[1].Split(',')

                $networkName = $nicArgs[2].Trim()
            }
        }
        default   {}  # unknown param - just ignore it
    }
}

$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Check if there are running old child VMs and stop them
Cleanup "SRIOV_Child"

# Get default Hyper-V VHD path; The VHD will be copied there
$hostInfo = Get-VMHost -ComputerName $hvServer
$defaultVhdPath = $hostInfo.VirtualHardDiskPath
if (-not $defaultVhdPath.EndsWith("\")) {
    $defaultVhdPath += "\"
}
$vhd_path_formatted = $defaultVhdPath.Replace(':','$')
$final_vhd_path="\\${hvServer}\${vhd_path_formatted}SRIOV_ChildRemote"

#
# Configure eth1 on test VM
#
Start-Sleep -s 5
$retVal = ConfigureVF $ipv4 $sshKey $netmask
if (-not $retVal)
{
    "ERROR: Failed to configure eth1 on vm $vmName (IP: ${ipv4}), by setting a static IP of $vmVF_IP1 , netmask $netmask"
    return $false
}
Start-Sleep -s 10

#
# Start ping
#
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "echo 'source constants.sh && ping -c 1200 -I eth1 `$VF_IP2 > PingResults.log &' > runPing.sh"
Start-Sleep -s 5
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "bash ~/runPing.sh > ~/Ping.log 2>&1"
Start-Sleep -s 10

[decimal]$initialRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"
if (-not $initialRTT){
    "ERROR: No result was logged! Check if VF is up!" | Tee-Object -Append -file $summaryLog
    .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "ifconfig"
    return $false
}
"The RTT before disabling VF is $initialRTT ms" | Tee-Object -Append -file $summaryLog

# Stop main VM to get the parent VHD
Stop-VM -VMName $vmName -ComputerName $hvServer -Force
if (-not $?) {
    Write-Output "Error: Unable to Shut Down VM" | Tee-Object -Append -file $summaryLog
    return $False
}

Start-Sleep -s 30
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

# Create Child vhd
$ChildVHD = CreateChildVHD $ParentVHD $final_vhd_path $hvServer

# Create the new VM
$newVm = New-VM -Name "SRIOV_Child" -ComputerName $hvServer -VHDPath "${defaultVhdPath}\SRIOV_ChildRemote.vhdx" -MemoryStartupBytes 4096MB -SwitchName "External" -Generation $vm_gen
if (-not $?) {
    Write-Output "Error: Creating New VM SRIOV_Child on $hvServer" | Tee-Object -Append -file $summaryLog
    return $False
} 

# Disable secure boot if Gen2
if ($vm_gen -eq 2) {
    Set-VMFirmware -VMName "SRIOV_Child" -ComputerName $hvServer -EnableSecureBoot Off
    if(-not $?) {
        Write-Output "Error: Unable to disable secure boot" | Tee-Object -Append -file $summaryLog
        Cleanup "SRIOV_Child"
        return $false
    }
}

ConfigureVMandVF "SRIOV_Child" $hvServer $sshKey $vmVF_IP1 $netmask
Write-Output "Child VM Configured and started" | Tee-Object -Append -file $summaryLog

$ipv4_child = GetIPv4 "SRIOV_Child" $hvServer 
Write-Output "SRIOV_Child IP Address: $ipv4_child"
Start-Sleep -s 10

# Run ping from child VM to dependency
.\bin\plink.exe -i ssh\$sshKey root@${ipv4_child} "echo ' ping -c 20 $vmVF_IP2 > PingResults.log &' > runPing.sh"
Start-Sleep -s 5
.\bin\plink.exe -i ssh\$sshKey root@${ipv4_child} "bash ~/runPing.sh > ~/Ping.log 2>&1"
Start-Sleep -s 5
[decimal]$vfEnabledRTT = .\bin\plink.exe -i ssh\$sshKey root@${ipv4_child} "tail -2 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'"

if (-not $vfEnabledRTT){
    Write-Output "ERROR: No result was logged on the Child VM!" | Tee-Object -Append -file $summaryLog
    Cleanup "SRIOV_Child"
    return $false   
}

if ($vfEnabledRTT -le 0.11) {
    Write-Output "VF is up & running, RTT is $vfEnabledRTT ms" | Tee-Object -Append -file $summaryLog
    Cleanup "SRIOV_Child"
    return $True    
} 
else {
    Write-Output "ERROR: RTT value is too high, $vfEnabledRTT ms!" | Tee-Object -Append -file $summaryLog
    Cleanup "SRIOV_Child"
    return $false
}