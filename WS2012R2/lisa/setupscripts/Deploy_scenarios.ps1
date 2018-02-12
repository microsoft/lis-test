#####################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, current_lis 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache current_lis 2.0 License for specific language governing
# permissions and limitations under the License.
#
#####################################################################
<#
.Synopsis

    Test different scenarios for LIS installation
   .Parameter vmName
    Name of the VM.
    .Parameter hvServer
    Name of the Hyper-V server hosting the VM.
    .Parameter testParams
    Test data for this test case
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

function enable_gsi($vmName, $hvServer){

    # Verify if the Guest services are enabled for this VM
    $gsi = Get-VMIntegrationService -vmName $vmName -ComputerName $hvServer -Name "Guest Service Interface"
    if (-not $gsi) {
        "Error: Unable to retrieve Integration Service status from VM '${vmName}'"
        return $False
    }

    if (-not $gsi.Enabled) {
        # make sure VM is off
        Stop-VM -vmName $vmName -ComputerName $hvServer -force
        $sts = WaitForVMToStop $vmName $hvServer 200
        if (-not $sts[-1]){
             "Error: Unable to shutdown $vmName"
             return $false
        }
        Enable-VMIntegrationService -Name "Guest Service Interface" -vmName $vmName -ComputerName $hvServer
        if (-not $?)
        {
            "Error: Unable to enable Guest Service Interface for $vmName."
            return $false
        }
    }
    return $true
}

function get_logs(){
    # Get test case log files
    $file = GetfileFromVm $ipv4 $sshkey "/root/summary.log" $logdir
    $file = GetfileFromVm $ipv4 $sshkey "/root/summary_scenario_$scenario.log" $logdir
    $file = GetfileFromVm $ipv4 $sshkey "/root/LIS_log_scenario_$scenario.log" $logdir
    $file = GetfileFromVm $ipv4 $sshkey "/root/kernel_install_scenario_$scenario.log" $logdir

}

function install_lis(){
    # Install, upgrade or uninstall LIS
    $remoteScript = "Install_LIS.sh"
    $sts = RunRemoteScript $remoteScript
    if(-not $sts[-1]){
        Write-Output "Error: Install_LIS.sh was not ran on $vmName" | Tee-Object -Append -file $summaryLog
        get_logs
        return $false
    }
}

function verify_daemons_modules(){
    # Verify LIS Modules and daemons
    $remoteScript = "CORE_LISmodules_version.sh"
    $sts = RunRemoteScript $remoteScript
    if(-not $sts[-1]){
        Write-Output "Error: Cannot verify LIS modules version on ${vmName}" | Tee-Object -Append -file $summaryLog
        get_logs
        return $false
    }

    $remoteScript = "check_lis_daemons.sh"
    $sts = RunRemoteScript $remoteScript
    if(-not $sts[-1]){
        Write-Output "Error: Not all deamons are running ${vmName}" | Tee-Object -Append -file $summaryLog
        get_logs
        return $false
    }

    return $true
}

function check_lis_version(){
    $LIS_version = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "modinfo hv_vmbus | grep -w version:  | tr -s [:space:]"
    if (-not $LIS_version) {
        if ($LIS_version_initial -eq $LIS_version){
            Write-Output "Error: modinfo shows that VM is still using built-in drivers"
        }
        else {
            Write-Output "Error: could not get version from modinfo"
        }
        
        get_logs
        return $LIS_version
    }
    else {
        Write-Output "LIS $LIS_version was installed successfully"
        get_logs
        return $LIS_version
    }
}

function daemons_selinux(){
    # Verify if SELinux is blocking LIS daemons.
    $remoteScript = "CORE_LISdaemons_selinux.sh"
    $sts = RunRemoteScript $remoteScript
    if(-not $sts[-1]){
        Write-Output "Error: Check failed. SELinux may prevent daemons from running." | Tee-Object -Append -file $summaryLog
        get_logs
        return $false
    }
    return $true
}

function kernel_upgrade(){
    $completed = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "cat kernel_install_scenario_$scenario.log | grep 'Complete!'"
    if(-not $completed){
        Write-output "Kernel upgrade failed"| Tee-Object -Append -file $summaryLog
        get_logs
        return $false
    }
    return $true
}

function kernel_version(){
	$upgrade = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "cat kernel_install_scenario_$scenario.log | grep 'Installed' -A 1 | tail -1 | cut -d \: -f 2"
	if ($upgrade){
		Write-Output "Kernel version after upgrade: ${upgrade}" | Tee-Object -Append -file $summaryLog
	} else {
		Write-Output "Warn: Cannot find upgraded kernel version" | Tee-Object -Append -file $summaryLog
	}

	$kernel = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "uname -r"
	Write-Output "Previous kernel version: ${kernel}" | Tee-Object -Append -file $summaryLog
	return $true
}

function stop_vm(){
    # Stop VM to attach the ISO
    Stop-VM $vmName  -ComputerName $hvServer -force

    if (-not $?)
    {
        "ERROR: Failed to shut $vmName down (in order to add the ISO file)" | Tee-Object -Append -file $summaryLog
        return $false
    }

    # Wait for VM to finish shutting down
    $timeout = 60
    while (Get-VM -Name $vmName -ComputerName $hvServer |  Where { $_.State -notlike "Off" })
    {
        if ($timeout -le 0)
        {
            "ERROR: Failed to shutdown $vmName" | Tee-Object -Append -file $summaryLog
            return $false
        }

        Start-Sleep -s 5
        $timeout = $timeout - 5
    }

    return $false
}

function check_bonding_errors() {
    $timer = 0
    while(true) {
        SendCommandToVM $ipv4 $sshkey "dmesg | grep -q 'bond0: Error'"
        if($sts[-1]){
            Write-Output "Error: Error found after kernel upgrade" | Tee-Object -Append -file $summaryLog
            return $false
        }

        SendCommandToVM $ipv4 $sshkey "grep -qi 'Call Trace' /var/log/messages"
        if($sts[-1]){
            Write-Output "Error: Call Trace found after kernel upgrade" | Tee-Object -Append -file $summaryLog
            return $false
        }
        $timer = $timer + 5
        Start-Sleep -s 5
        if($timer -gt 300) {
            Write-Output "Info: No errors found after kernel upgrade" | Tee-Object -Append -file $summaryLog
            break
        }
    }
    return $true
}
#######################################################################
#
#   Main body script
#
#######################################################################

# Checking the input arguments
if (-not $vmName) {
    "Error: VM name is null!"
    return $retVal
}

if (-not $hvServer) {
    "Error: hvServer is null!"
    return $retVal
}

if (-not $testParams) {
    "Error: No testParams provided!"
    "This script requires the test case ID and VM details as the test parameters."
    return $retVal
}

#
# Checking the mandatory testParams. New parameters must be validated here.
#
$global_LIS_version = $null
$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")

    if ($fields[0].Trim() -eq "TC_COVERED") {
        $TC_COVERED = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "rootDir") {
        $rootDir = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "TestLogDir") {
        $logdir = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "ipv4") {
        $ipv4 = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "sshkey") {
        $sshkey = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "scenario") {
        $scenario = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "IsoFilename") {
        $IsoFilename = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "IsoFilename2") {
        $isofilename2 = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "lis_network_share") {
        $lis_network_share = $fields[1].Trim()
    }
}

#
# Change the working directory for the log files
# Delete any previous summary.log file, then create a new one
#
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist"
    return $false
}
cd $rootDir

# Source TCUtils.ps1 for test related functions
if (Test-Path ".\setupscripts\TCUtils.ps1")
{
    . .\setupScripts\TCUtils.ps1
}
else
{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}

# Delete any previous summary.log file, then create a new one
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Get default Hyper-V VHD path; The drivers will be copied here
$hostInfo = Get-VMHost -ComputerName $hvServer
$defaultVhdPath = $hostInfo.VirtualHardDiskPath
if (-not $defaultVhdPath.EndsWith("\")) {
    $defaultVhdPath += "\"
}

#
# Copy LIS ISOs to the default VHD path
#
# First, build the paths
if (-not $lis_network_share.EndsWith("\")) {
    $lis_network_share += "\"
}

$latest_lis_iso_path = $lis_network_share + $IsoFilename
$previous_lis_iso_path = $lis_network_share + $IsoFilename2

# Check if the path is correct for both ISOs
$sts = Get-ChildItem -Name $latest_lis_iso_path
if (-not $sts) {
    Write-Output "Error: The path for the latest LIS ISO file is incorrect. 
    Please check the network share or ISO name in the XML file" | Tee-Object -Append -file $summaryLog
    return $false
}

$sts = Get-ChildItem -Name $previous_lis_iso_path
if (-not $sts) {
    Write-Output "Error: The path for the previous LIS ISO file is incorrect. 
    Please check the network share or ISO name in the XML file" | Tee-Object -Append -file $summaryLog
    return $false
}

# Copy both files
$sts = Copy-Item -Path $previous_lis_iso_path -Destination $defaultVhdPath -Force
$sts = Copy-Item -Path $latest_lis_iso_path -Destination $defaultVhdPath -Force

# Attach ISO accordingly to deploy scenario
stop_vm
if (($scenario -eq 2) -or ($scenario -eq 3) -or  ($scenario -eq 6) -or ($scenario -eq 10)) {
    .\setupscripts\InsertIsoInDvd.ps1 $vmName $hvServer "isofilename=$IsoFilename2"
}
else {
    .\setupscripts\InsertIsoInDvd.ps1 $vmName $hvServer "isofilename=$IsoFilename"
}

#
# Enable Guest Service Interface
#
$sts = enable_gsi $vmName $hvServer
if( -not $sts){
    Write-Output "Error: Cannot enable Guest Service Interface for ${vmName}" | Tee-Object -Append -file $summaryLog
    return $false
}

#
# Start VM
#
if ((Get-VM -ComputerName $hvServer -Name $vmName).State -eq "Off") {
    Start-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
    $sts = WaitForVMToStartSSH $ipv4 200
    if( -not $sts){
        Write-Output "Error: Cannot start $vmName" | Tee-Object -Append -file $summaryLog
        return $false
    }
}

Start-Sleep -s 10
# Check if the VM is clean (no external LIS installed already)
$LIS_version_initial = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "modinfo hv_vmbus | grep -w version:"
$LIS_version_initial = $LIS_version_initial -split " " | Select-Object -Last 1

if (-not $LIS_version_initial -or ($LIS_version_initial -eq "3.1")) {
    Write-Output "VM is clean, will proceed with LIS Deploy scenario $scenario"   
}
else {
    Write-Output "Error: VM already has LIS $LIS_version_initial installed"  | Tee-Object -Append -file $summaryLog
    return $false
}

switch ($scenario){
    "1" {
        # Mount and install LIS
        Write-Output "Starting LIS installation"
        $sts = SendCommandToVM $ipv4 $sshkey "echo 'action=install' >> ~/constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = install_lis
        if( -not $sts[-1]){
            Write-Output "Error: Cannot install LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-output "Successfully installed LIS"

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: ${vmName} failed to restart after installing the latest LIS drivers"
            return $false
        }
        Write-Output "Successfully rebooted VM"

        $sts = daemons_selinux
        if(-not $sts[-1]){
            Write-Output "Error: Check failed. SELinux may prevent daemons from running." | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = verify_daemons_modules
        if( -not $sts[-1]){
            Write-Output "Error: Daemons/Modules verification failed for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_final = check_lis_version
        $LIS_version_final = $LIS_version_final[($LIS_version_final.count -1)] -split " " | Select-Object -Last 1

        Write-Output "LIS version after installing latest drivers: $LIS_version_final" | Tee-Object -Append -file $summaryLog
        if ($LIS_version_final -eq $LIS_version_initial) {
            Write-Output "Error: LIS version has not changed on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false     
        }
    }

    "2" {
        # Mount and install LIS
        $sts = SendCommandToVM $ipv4 $sshkey "echo 'action=install' >> ~/constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = install_lis
        if( -not $sts[-1]){
            Write-Output "Error: Cannot install LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: ${vmName} failed to restart after installing the previous LIS drivers" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = verify_daemons_modules
        if( -not $sts[-1]){
            Write-Output "Error: Daemons/Modules verification failed for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_old = check_lis_version
        $LIS_version_old = $LIS_version_old[($LIS_version_old.count -1)] -split " " | Select-Object -Last 1

        Write-Output "LIS version with previous LIS drivers: $LIS_version_old" | Tee-Object -Append -file $summaryLog
        if ($LIS_version_old -eq $LIS_version_initial) {
            Write-Output "Error: LIS version has not changed on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false     
        }

        # Attach the new iso.
        stop_vm
        $sts = .\setupscripts\InsertIsoInDvd.ps1 -vmName $vmName -hvServer $hvServer -testParams "isofilename=$IsoFilename"
        if( -not $sts[-1]){
            Write-Output "Error: Cannot attach $isofilename to ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        Start-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: Cannot start ${vmName}"
            return $false
        }

        $sts = SendCommandToVM $ipv4 $sshkey "sed -i 's/action=\S*/action=upgrade/g' constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = install_lis
        if( -not $sts[-1]){
            Write-Output "Error: Cannot upgrade LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-Output "Successfully upgraded LIS"

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: ${vmName} failed to restart after installing the latest LIS drivers" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = verify_daemons_modules
        if( -not $sts[-1]){
            Write-Output "Error: Daemons/Modules verification failed for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_final = check_lis_version
        $LIS_version_final = $LIS_version_final[($LIS_version_final.count -1)] -split " " | Select-Object -Last 1

        Write-Output "LIS version after installing latest drivers: $LIS_version_final" | Tee-Object -Append -file $summaryLog
        if ($LIS_version_final -eq $LIS_version_old) {
            Write-Output "Error: LIS version has not changed after upgrading!" | Tee-Object -Append -file $summaryLog
            return $false     
        }
    }

    "3" {
        # Mount and install LIS
        $sts = SendCommandToVM $ipv4 $sshkey "echo 'action=install' >> ~/constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = install_lis
        if( -not $sts[-1]){
            Write-Output "Error: Cannot install LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: ${vmName} failed to restart after installing the previous LIS drivers" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = verify_daemons_modules
        if( -not $sts[-1]){
            Write-Output "Error: Daemons/Modules verification failed for ${vmName} after installing previous LIS" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_old = check_lis_version
        $LIS_version_old = $LIS_version_old[($LIS_version_old.count -1)] -split " " | Select-Object -Last 1

        Write-Output "LIS version with previous LIS drivers: $LIS_version_old" | Tee-Object -Append -file $summaryLog
        if ($LIS_version_old -eq $LIS_version_initial) {
            Write-Output "Error: LIS version has not changed on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false     
        }

        # Attach the new iso.
        stop_vm
        .\setupscripts\InsertIsoInDvd.ps1 $vmName $hvServer "isofilename=$IsoFilename"

        Start-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: Cannot start ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Mount and upgrade LIS
        $sts = SendCommandToVM $ipv4 $sshkey "sed -i 's/action=\S*/action=upgrade/g' constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = install_lis
        if( -not $sts[-1]){
            Write-Output "Error: Cannot upgrade LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: ${vmName} failed to restart after installing the latest LIS drivers" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = verify_daemons_modules
        if( -not $sts[-1]){
            Write-Output "Error: Daemons/Modules verification failed for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_upgraded = check_lis_version
        $LIS_version_upgraded = $LIS_version_upgraded[($LIS_version_upgraded.count -1)] -split " " | Select-Object -Last 1

        Write-Output "LIS version after upgrade: $LIS_version_upgraded" | Tee-Object -Append -file $summaryLog
        if ($LIS_version_upgraded -eq $LIS_version_old) {
            Write-Output "Error: LIS version has not changed after upgrading!" | Tee-Object -Append -file $summaryLog
            return $false     
        }

        # Unstall LIS
        $sts = SendCommandToVM $ipv4 $sshkey "sed -i 's/action=\S*/action=uninstall/g' constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = install_lis
        if( -not $sts[-1]){
            Write-Output "Error: Cannot uninstall LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-Output "Successfully uninstalled $current_lis."

        # Attach the new iso.
        stop_vm
        $sts = .\setupscripts\InsertIsoInDvd.ps1 $vmName $hvServer "isofilename=$IsoFilename2"
        if( -not $sts[-1]){
            Write-Output "Error: Cannot attach LIS iso on ${vmName}"
            return $false
        }

        Start-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: Cannot start ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Mount and install LIS
        $sts = SendCommandToVM $ipv4 $sshkey "sed -i 's/action=\S*/action=install/g' constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = install_lis
        if( -not $sts[-1]){
            Write-Output "Error: Cannot install LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: ${vmName} failed to restart after installing the previous LIS drivers" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = verify_daemons_modules
        if( -not $sts[-1]){
            Write-Output "Error: Daemons/Modules verification failed for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_final = check_lis_version
        $LIS_version_final = $LIS_version_final[($LIS_version_final.count -1)] -split " " | Select-Object -Last 1

        Write-Output "LIS version final: $LIS_version_final" | Tee-Object -Append -file $summaryLog
        if ($LIS_version_final -eq $LIS_version_upgraded) {
            Write-Output "Error: LIS version has not changed after downgrading!" | Tee-Object -Append -file $summaryLog
            return $false     
        }
    }

    "4"{
        # Upgrade kernel
        $sts = SendCommandToVM $ipv4 $sshkey "yum install -y kernel >> ~/kernel_install_scenario_$scenario.log"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to upgrade kernel on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        SendCommandToVM $ipv4 $sshkey "echo `"---kernel version before upgrade:`$(uname -r)---`" >> kernel_install_scenario_$scenario.log"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add kernel version before upgrade to log on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        #write kernel version in summaryLog
        kernel_version

        $sts = SendCommandToVM $ipv4 $sshkey "sync"
        Start-Sleep -s 30
        # Check if kernel was upgraded
        $sts = kernel_upgrade
        if(-not $sts[-1]){
            Write-Output "Error: Kernel was not upgraded" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-Output "Successfully upgraded kernel."

        # Mount and install LIS
        $sts = SendCommandToVM $ipv4 $sshkey "echo 'action=install' >> ~/constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Mount and install LIS
        $sts = install_lis
        if($sts[-1]){
            Write-Output "Error: LIS installation succeded ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-Output "Installation failed as expected." | Tee-Object -Append -file $summaryLog
    }

    "5"{
        # Mount and install LIS
        $sts = SendCommandToVM $ipv4 $sshkey "echo 'action=install' >> ~/constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = install_lis
        if( -not $sts[-1]){
            Write-Output "Error: Cannot install LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-output "Successfully installed LIS $current_lis" | Tee-Object -Append -file $summaryLog

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: ${vmName} failed to restart after installing the latest LIS drivers" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-output "Rebooted VM"

        # validate install
        $sts = verify_daemons_modules
        if( -not $sts[-1]){
            Write-Output "Error: Daemons/Modules verification failed for ${vmName} after install." | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_beforeUpgrade = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} " modinfo hv_vmbus | grep  -w version: | cut -d ':' -f 2 | tr -d ' \t' "
        Write-output "LIS version before kernel upgrade: $LIS_version_beforeUpgrade "| Tee-Object -Append -file $summaryLog

        # Upgrade kernel
        $sts = SendCommandToVM $ipv4 $sshkey "yum install -y kernel >> ~/kernel_install_scenario_$scenario.log"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to upgrade kernel on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        SendCommandToVM $ipv4 $sshkey "echo `"---kernel version before upgrade:`$(uname -r)---`" >> kernel_install_scenario_$scenario.log"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add kernel version before upgrade to log on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        #write kernel version in summaryLog
        kernel_version

        $sts = SendCommandToVM $ipv4 $sshkey "sync"
        Start-Sleep -s 30
        # Check if kernel was upgraded
        $sts = kernel_upgrade
        if(-not $sts[-1]){
            Write-Output "Error: Kernel was not upgraded" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-Output "Successfully upgraded kernel."

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: ${vmName} has not started after upgrading the kernel" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-output "Rebooted VM"

        SendCommandToVM $ipv4 $sshkey "echo `"---kernel version after upgrade:`$(uname -r)---`" >> kernel_install_scenario_$scenario.log"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add kernel version after upgrade to log on on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_afterUpgrade = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "modinfo hv_vmbus | grep -w version:"
        if ($LIS_version_afterUpgrade -eq $LIS_version_beforeUpgrade){
            Write-Output "Error: After upgrading the kernel, VM booted with LIS drivers $LIS_version_afterUpgrade " | Tee-Object -Append -file $summaryLog    
        }
        else{
            Write-Output "VM booted with built-in LIS drivers after kernel upgrade" | Tee-Object -Append -file $summaryLog   
        }
    }

    "6" {
        # Mount and install LIS
        $sts = SendCommandToVM $ipv4 $sshkey "echo 'action=install' >> ~/constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = install_lis
        if( -not $sts[-1]){
            Write-Output "Error: Cannot install LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: Cannot restart ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # validate install
        $sts = verify_daemons_modules
        if( -not $sts[-1]){
            Write-Output "Error: Daemons/Modules verification failed for ${vmName} after install." | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_old = check_lis_version
        $LIS_version_old = $LIS_version_old[($LIS_version_old.count -1)]
        $LIS_version_old = $LIS_version_old -split "\s+"
        $LIS_version_old = $LIS_version_old[1]

        Write-Output "LIS version with previous LIS drivers: $LIS_version_old" | Tee-Object -Append -file $summaryLog
        if ($LIS_version_old -eq $LIS_version_initial) {
            Write-Output "Error: LIS version has not changed on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false     
        }

        # Attach the new iso.
        Stop-VM -vmName $vmName -ComputerName $hvServer -force
        .\setupscripts\InsertIsoInDvd.ps1 $vmName $hvServer "isofilename=$IsoFilename"

        Start-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: Cannot start ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Mount and upgrade LIS
        $sts = SendCommandToVM $ipv4 $sshkey "sed -i 's/action=\S*/action=upgrade/g' constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = install_lis
        if( -not $sts[-1]){
            Write-Output "Error: Cannot upgrade LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: Cannot restart ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # validate upgrade
        $sts = verify_daemons_modules
        if( -not $sts[-1]){
            Write-Output "Error: Daemons/Modules verification failed for ${vmName} after upgrade." | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_beforeUpgrade = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} " modinfo hv_vmbus | grep  -w version: | cut -d ':' -f 2 | tr -d ' \t' "
        Write-output "LIS before kernel upgrade: $LIS_version_beforeUpgrade "| Tee-Object -Append -file $summaryLog

        # Upgrade kernel
        $sts = SendCommandToVM $ipv4 $sshkey "yum install -y kernel >> ~/kernel_install_scenario_$scenario.log"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to upgrade kernel on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Upgrade kernel

        $sts = SendCommandToVM $ipv4 $sshkey "yum install -y kernel >> ~/kernel_install_scenario_$scenario.log"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to upgrade kernel on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        SendCommandToVM $ipv4 $sshkey "echo `"---kernel version before upgrade:`$(uname -r)---`" >> kernel_install_scenario_$scenario.log"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add kernel version before upgrade to log on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        #write kernel version in summaryLog
        kernel_version

        $sts = SendCommandToVM $ipv4 $sshkey "sync"
        Start-Sleep -s 30
        # Check if kernel was upgraded
        $sts = kernel_upgrade
        if(-not $sts[-1]){
            Write-Output  "Error: Kernel was not upgraded" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-Output "Successfully upgraded kernel."

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: Cannot restart ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        SendCommandToVM $ipv4 $sshkey "echo `"---kernel version after upgrade:`$(uname -r)---`" >> kernel_install_scenario_$scenario.log"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add kernel version after upgrade to log on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_afterUpgrade = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "modinfo hv_vmbus | grep -w version:"
        if ($LIS_version_afterUpgrade -eq $LIS_version_beforeUpgrade){
            Write-Output "Error: After upgrading the kernel, VM booted with LIS drivers $LIS_version_afterUpgrade " | Tee-Object -Append -file $summaryLog    
        }
        else{
            Write-Output "VM booted with built-in LIS drivers after kernel upgrade" | Tee-Object -Append -file $summaryLog   
        }
    }

    "8"{
        # Mount and install LIS
        $sts = SendCommandToVM $ipv4 $sshkey "echo 'action=install' >> ~/constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = install_lis
        if( -not $sts[-1]){
            Write-Output "Error: Cannot install LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-output "Successfully installed LIS $current_lis"

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: Cannot restart ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Uninstall lis
        $sts = SendCommandToVM $ipv4 $sshkey "sed -i 's/action=\S*/action=uninstall/g' constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = install_lis
        if( -not $sts[-1]){
            Write-Output "Error: Cannot uninstall LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $count=.\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "ls /lib/modules/`$(uname -r)/extra/microsoft-hyper-v | wc -l"
        if ($count -ge 1) {
            Write-Output "Error: LIS modules from the LIS RPM's were't removed." | Tee-Object -Append -file $summaryLog
            return $false
        }

        Write-Output "Successfully removed LIS" | Tee-Object -Append -file $summaryLog
    }

    "9" {
        # Run bonding script
        $sts = SendCommandToVM $ipv4 $sshkey "~/bondvf.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Bonding script exited with error code" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: ${vmName} failed to restart after installing the latest LIS drivers" | Tee-Object -Append -file $summaryLog
            return $false
        }
        
        Write-output "Rebooted VM"

        # Mount and install LIS
        $sts = SendCommandToVM $ipv4 $sshkey "echo 'action=install' >> ~/constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = install_lis
        if( -not $sts[-1]){
            Write-Output "Error: Cannot install LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-output "Successfully installed LIS $current_lis" | Tee-Object -Append -file $summaryLog

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: ${vmName} failed to restart after installing the latest LIS drivers" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-output "Rebooted VM"

        # validate install
        $sts = verify_daemons_modules
        if( -not $sts[-1]){
            Write-Output "Error: Daemons/Modules verification failed for ${vmName} after install." | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: ${vmName} failed to restart after installing the latest LIS drivers" | Tee-Object -Append -file $summaryLog
            return $false
        }
        
        Write-output "Rebooted VM"
        
        $sts = check_bonding_errors
        if( -not $sts[-1]) {
            Write-Output "Error: Bond errors found after LIS install." | Tee-Object -Append -file $summaryLog
            return $false
        } else {
            Write-Output "No errors found after LIS install" | Tee-Object -Append -file $summaryLog
        }

        $LIS_version_beforeUpgrade = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} " modinfo hv_vmbus | grep  -w version: | cut -d ':' -f 2 | tr -d ' \t' "
        Write-output "LIS version before kernel upgrade: $LIS_version_beforeUpgrade "| Tee-Object -Append -file $summaryLog

        # Upgrade kernel
        $sts = SendCommandToVM $ipv4 $sshkey "yum install -y kernel >> ~/kernel_install_scenario_$scenario.log"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to upgrade kernel on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        SendCommandToVM $ipv4 $sshkey "echo `"---kernel version before upgrade:`$(uname -r)---`" >> kernel_install_scenario_$scenario.log"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add kernel version before upgrade to log on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        #write kernel version in summaryLog
        kernel_version

        $sts = SendCommandToVM $ipv4 $sshkey "sync"
        Start-Sleep -s 30
        # Check if kernel was upgraded
        $sts = kernel_upgrade
        if(-not $sts[-1]){
            Write-Output "Error: Kernel was not upgraded" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-Output "Successfully upgraded kernel."

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: ${vmName} has not started after upgrading the kernel" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-output "Rebooted VM"

        SendCommandToVM $ipv4 $sshkey "echo `"---kernel version after upgrade:`$(uname -r)---`" >> kernel_install_scenario_$scenario.log"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add kernel version after upgrade to log on on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_afterUpgrade = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "modinfo hv_vmbus | grep -w version:"
        if ($LIS_version_afterUpgrade -eq $LIS_version_beforeUpgrade){
            Write-Output "Error: After upgrading the kernel, VM booted with LIS drivers $LIS_version_afterUpgrade " | Tee-Object -Append -file $summaryLog    
        }
        else{
            Write-Output "VM booted with built-in LIS drivers after kernel upgrade" | Tee-Object -Append -file $summaryLog   
        }

        $sts = check_bonding_errors
        if( -not $sts[-1]) {
            Write-Output "Error: Bond errors found after kernel upgrade." | Tee-Object -Append -file $summaryLog
            return $false
        } else {
            Write-Output "No errors found after kernel upgrade" | Tee-Object -Append -file $summaryLog
        }
    }
    "10" {
        # Mount and install LIS
        $sts = SendCommandToVM $ipv4 $sshkey "echo 'action=install' >> ~/constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = install_lis
        if( -not $sts[-1]){
            Write-Output "Error: Cannot install LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: Cannot restart ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # validate install
        $sts = verify_daemons_modules
        if( -not $sts[-1]){
            Write-Output "Error: Daemons/Modules verification failed for ${vmName} after install." | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_old = check_lis_version
        $LIS_version_old = $LIS_version_old[($LIS_version_old.count -1)]
        $LIS_version_old = $LIS_version_old -split "\s+"
        $LIS_version_old = $LIS_version_old[1]

        Write-Output "LIS version with previous LIS drivers: $LIS_version_old" | Tee-Object -Append -file $summaryLog
        if ($LIS_version_old -eq $LIS_version_initial) {
            Write-Output "Error: LIS version has not changed on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false     
        }
        
        # Run bonding script
        $sts = SendCommandToVM $ipv4 $sshkey "~/bondvf.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Bonding script exited with error code" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Attach the new iso.
        Stop-VM -vmName $vmName -ComputerName $hvServer -force
        .\setupscripts\InsertIsoInDvd.ps1 $vmName $hvServer "isofilename=$IsoFilename"

        Start-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: Cannot start ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Mount and upgrade LIS
        $sts = SendCommandToVM $ipv4 $sshkey "sed -i 's/action=\S*/action=upgrade/g' constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = install_lis
        if( -not $sts[-1]){
            Write-Output "Error: Cannot upgrade LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: Cannot restart ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # validate upgrade
        $sts = verify_daemons_modules
        if( -not $sts[-1]){
            Write-Output "Error: Daemons/Modules verification failed for ${vmName} after upgrade." | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_beforeUpgrade = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} " modinfo hv_vmbus | grep  -w version: | cut -d ':' -f 2 | tr -d ' \t' "
        Write-output "LIS before kernel upgrade: $LIS_version_beforeUpgrade "| Tee-Object -Append -file $summaryLog
        
        $sts = check_bonding_errors
        if( -not $sts[-1]) {
            Write-Output "Error: Bond errors found after lis upgrade" | Tee-Object -Append -file $summaryLog
            return $false
        } else {
            Write-Output "No errors found after lis upgrade" | Tee-Object -Append -file $summaryLog
        }
        
        # Upgrade kernel
        $sts = SendCommandToVM $ipv4 $sshkey "yum install -y kernel >> ~/kernel_install_scenario_$scenario.log"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to upgrade kernel on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Upgrade kernel

        $sts = SendCommandToVM $ipv4 $sshkey "yum install -y kernel >> ~/kernel_install_scenario_$scenario.log"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to upgrade kernel on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        SendCommandToVM $ipv4 $sshkey "echo `"---kernel version before upgrade:`$(uname -r)---`" >> kernel_install_scenario_$scenario.log"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add kernel version before upgrade to log on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        #write kernel version in summaryLog
        kernel_version

        $sts = SendCommandToVM $ipv4 $sshkey "sync"
        Start-Sleep -s 30
        # Check if kernel was upgraded
        $sts = kernel_upgrade
        if(-not $sts[-1]){
            Write-Output  "Error: Kernel was not upgraded" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-Output "Successfully upgraded kernel."

        # Reboot the VM
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force
        $sts = WaitForVMToStartSSH $ipv4 200
        if( -not $sts[-1]){
            Write-Output "Error: Cannot restart ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        SendCommandToVM $ipv4 $sshkey "echo `"---kernel version after upgrade:`$(uname -r)---`" >> kernel_install_scenario_$scenario.log"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add kernel version after upgrade to log on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_afterUpgrade = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "modinfo hv_vmbus | grep -w version:"
        if ($LIS_version_afterUpgrade -eq $LIS_version_beforeUpgrade){
            Write-Output "Error: After upgrading the kernel, VM booted with LIS drivers $LIS_version_afterUpgrade " | Tee-Object -Append -file $summaryLog    
        }
        else{
            Write-Output "VM booted with built-in LIS drivers after kernel upgrade" | Tee-Object -Append -file $summaryLog   
        }

        $sts = check_bonding_errors
        if( -not $sts[-1]) {
            Write-Output "Error: Bond errors found after kernel upgrade." | Tee-Object -Append -file $summaryLog
            return $false
        } else {
            Write-Output "No errors found after kernel upgrade" | Tee-Object -Append -file $summaryLog
        }
    }
}

get_logs

return $True