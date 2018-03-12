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

function GetLogs() {
    # Get test case log files
    $file = GetfileFromVm $ipv4 $sshkey "/root/summary.log" "${logdir}\summary_$scenario.log"
    $file = GetfileFromVm $ipv4 $sshkey "/root/LIS_scenario_${scenario}.log" $logdir
    $file = GetfileFromVm $ipv4 $sshkey "/root/kernel_install_scenario_$scenario.log" $logdir

    return $true
}

function InstallLIS() {
    # Install, upgrade or uninstall LIS
    $remoteScript = "lis_deploy_scenarios_install.sh"
    $sts = RunRemoteScript $remoteScript
    if (-not $sts[-1]) {
        Write-Output "Error: lis_deploy_scenarios_install.sh was not ran on $vmName" | Tee-Object -Append -file $summaryLog
        GetLogs
        return $false
    }

    return $true
}

function VerifyDaemons() {
    # Verify LIS Modules and daemons
    $remoteScript = "CORE_LISmodules_version.sh"
    $sts = RunRemoteScript $remoteScript
    if(-not $sts[-1]) {
        Write-Output "Error: Cannot verify LIS modules version on ${vmName}" | Tee-Object -Append -file $summaryLog
        GetLogs
        return $false
    }

    $remoteScript = "check_lis_daemons.sh"
    $sts = RunRemoteScript $remoteScript
    if (-not $sts[-1]) {
        Write-Output "Error: Not all daemons are running ${vmName}" | Tee-Object -Append -file $summaryLog
        GetLogs
        return $false
    }

    return $true
}

function CheckLISVersion() {
    $LIS_version = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "modinfo hv_vmbus | grep -w version:  | tr -s [:space:]"
    if (-not $LIS_version) {
        if ($LIS_version_initial -eq $LIS_version){
            Write-Output "Error: modinfo shows that VM is still using built-in drivers"
        } else {
            Write-Output "Error: could not get version from modinfo"
        }
        
        GetLogs
        return $LIS_version
    } else {
        Write-Output "LIS $LIS_version was installed successfully"
        GetLogs
        return $LIS_version
    }
}

function CheckSelinux() {
    # Verify if SELinux is blocking LIS daemons.
    $remoteScript = "CORE_LISdaemons_selinux.sh"
    $sts = RunRemoteScript $remoteScript
    if (-not $sts[-1]) {
        Write-Output "Error: Check failed. SELinux may prevent daemons from running." | Tee-Object -Append -file $summaryLog
        GetLogs
        return $false
    }
    return $true
}

function GetUpgradeKernelLogs() {
    $completed = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "cat kernel_install_scenario_$scenario.log | grep 'Complete!'"
    if(-not $completed) {
        Write-output "Kernel upgrade failed"| Tee-Object -Append -file $summaryLog
        GetLogs
        return $false
    }
    return $true
}

function GetKernelVersion() {
	$upgrade = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "cat kernel_install_scenario_$scenario.log | grep 'Installed' -A 1 | tail -1 | cut -d \: -f 2"
	if ($upgrade) {
		Write-Output "Kernel version after upgrade: ${upgrade}" | Tee-Object -Append -file $summaryLog
	} else {
		Write-Output "Warn: Cannot find upgraded kernel version" | Tee-Object -Append -file $summaryLog
	}

	$kernel = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "uname -r"
	Write-Output "Previous kernel version: ${kernel}" | Tee-Object -Append -file $summaryLog
	return $true
}


function StartRestartVM () {
    param (
        [String] $action
    )

    if ($action -eq "start") {
        Start-VM -VMName $vmName -ComputerName $hvServer
    } else {
        Restart-VM -VMName $vmName -ComputerName $hvServer -Force   
    }
   
    $timeout = 200
    if (-not (WaitForVMToStartKVP $vmName $hvServer $timeout )) {
        return $false
    }

    Start-Sleep -s 15
    # Get the ipv4, maybe it may change after the reboot
    $ipv4 = Getipv4 $vmName $hvServer
    Write-Output "${vmName} IP Address after reboot: ${ipv4}"
    Set-Variable -Name "ipv4" -Value $ipv4 -Scope Global
    return $true
}

function RevertSnapshot () {
    param (
        [String] $snapName 
    )
    # Stop VM
    Stop-VM -Name $vmName -ComputerName $hvServer -Confirm:$false -TurnOff
    Start-Sleep -s 5

    # Revert snapshot
    $snap = Get-VMSnapshot -VMName $vmName -Name $snapName
    Restore-VMSnapshot $snap -Confirm:$false
    
    # Start VM and wait for it to boot
    StartRestartVM "start"


    $sts = SendCommandToVM $ipv4 $sshkey "sed -i 's/TC_COVERED=\S*/TC_COVERED=$TC_COVERED/g' constants.sh"
    $sts = SendCommandToVM $ipv4 $sshkey "sed -i 's/scenario=\S*/scenario=$scenario/g' constants.sh"
    return $true 
}

function CheckBondingErrors() {
    $timer = 0
    while(true) {
        SendCommandToVM $ipv4 $sshkey "dmesg | grep -q 'bond0: Error'"
        if($sts[-1]) {
            Write-Output "Error: Error found after kernel upgrade" | Tee-Object -Append -file $summaryLog
            return $false
        }

        SendCommandToVM $ipv4 $sshkey "grep -qi 'Call Trace' /var/log/messages"
        if($sts[-1]) {
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

function UpgradeLIS() {
    param (
        [string] $runBond
    )
    # Mount and install LIS
    $sts = SendCommandToVM $ipv4 $sshkey "echo -e 'action=install\nlis_folder=OLD_LISISO' >> ~/constants.sh"
    if(-not $sts[-1]){
        Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
        return $false
    }

    $sts = InstallLIS
    if( -not $sts[-1]){
        Write-Output "Error: Cannot install LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
        return $false
    }
    $sts = SendCommandToVM $ipv4 $sshkey "sync"
    Start-Sleep -s 20
    # Reboot the VM and check LIS
    StartRestartVM "restart"

    $sts = VerifyDaemons
    if( -not $sts[-1]){
        Write-Output "Error: Daemons/Modules verification failed for ${vmName}" | Tee-Object -Append -file $summaryLog
        return $false
    }

    $LIS_version_old = CheckLISVersion
    $LIS_version_old = $LIS_version_old[($LIS_version_old.count -1)] -split " " | Select-Object -Last 1
    Write-Output "LIS version with previous LIS drivers: $LIS_version_old" | Tee-Object -Append -file $summaryLog
    if ($LIS_version_old -eq $LIS_version_initial) {
        Write-Output "Error: LIS version has not changed on ${vmName}" | Tee-Object -Append -file $summaryLog
        return $false     
    }

    if ($runBond -eq "yes") {
        # Run bonding script
        $sts = SendCommandToVM $ipv4 $sshkey "~/bondvf.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Bonding script exited with error code" | Tee-Object -Append -file $summaryLog
            return $false
        }

    }

    $sts = SendCommandToVM $ipv4 $sshkey "sed -i 's/lis_folder=\S*/lis_folder=NEW_LISISO/g' constants.sh"
    $sts = SendCommandToVM $ipv4 $sshkey "sed -i 's/action=\S*/action=upgrade/g' constants.sh"
    if(-not $sts[-1]){
        Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
        return $false
    }

    $sts = InstallLIS
    if( -not $sts[-1]){
        Write-Output "Error: Cannot upgrade LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
        return $false
    }
    Write-Output "Successfully upgraded LIS"

    # Reboot the VM and check LIS
    StartRestartVM "restart"
    $sts = VerifyDaemons
    if( -not $sts[-1]){
        Write-Output "Error: Daemons/Modules verification failed for ${vmName}" | Tee-Object -Append -file $summaryLog
        return $false
    }

    $LIS_version_final = CheckLISVersion
    $LIS_version_final = $LIS_version_final[($LIS_version_final.count -1)] -split " " | Select-Object -Last 1

    Write-Output "LIS version after installing latest drivers: $LIS_version_final" | Tee-Object -Append -file $summaryLog
    if ($LIS_version_final -eq $LIS_version_old) {
        Write-Output "Error: LIS version has not changed after upgrading!" | Tee-Object -Append -file $summaryLog
        return $false     
    }
    return $true
}

function UpgradeKernel() {
    $LIS_version_beforeUpgrade = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} " modinfo hv_vmbus | grep  -w version: | cut -d ':' -f 2 | tr -d ' \t' "
    Write-output "LIS before kernel upgrade: $LIS_version_beforeUpgrade "| Tee-Object -Append -file $summaryLog
    Set-Variable -Name "LIS_version_beforeUpgrade" -Value $LIS_version_beforeUpgrade -Scope Global

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

    # Write kernel version in summaryLog
    GetKernelVersion

    $sts = SendCommandToVM $ipv4 $sshkey "sync"
    Start-Sleep -s 30
    # Check if kernel was upgraded
    $sts = GetUpgradeKernelLogs
    if(-not $sts[-1]){
        Write-Output  "Error: Kernel was not upgraded" | Tee-Object -Append -file $summaryLog
        return $false
    }
    Write-Output "Successfully upgraded kernel."

    # Reboot the VM and check LIS version
    StartRestartVM "restart"

    SendCommandToVM $ipv4 $sshkey "echo `"---kernel version after upgrade:`$(uname -r)---`" >> kernel_install_scenario_$scenario.log"
    if(-not $sts[-1]){
        Write-Output "Error: Unable to add kernel version after upgrade to log on ${vmName}" | Tee-Object -Append -file $summaryLog
        return $false
    }
}

#######################################################################
#
#   Main body script
#
#######################################################################
# Checking the input arguments
if (-not $vmName) {
    Write-Host "Error: VM name is null!"
    return $retVal
}

if (-not $hvServer) {
    Write-Host "Error: hvServer is null!"
    return $retVal
}

if (-not $testParams) {
    Write-Host "Error: No testParams provided!"
    Write-Host "This script requires the test case ID and VM details as the test parameters."
    return $retVal
}

# Checking the mandatory testParams. New parameters must be validated here.
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
    if ($fields[0].Trim() -eq "sshKey") {
        $sshkey = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "scenario") {
        $scenario = $fields[1].Trim()
    }
}

#
# Change the working directory for the log files
# Delete any previous summary.log file, then create a new one
#
if (-not (Test-Path $rootDir)) {
    Write-Host "Error: The directory `"${rootDir}`" does not exist"
    return $false
}
cd $rootDir

# Source TCUtils.ps1 for test related functions
if (Test-Path ".\setupscripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
} else {
    Write-Host "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}

# Delete any previous summary.log file, then create a new one
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Check if the VM is clean (no external LIS installed already)
$LIS_version_initial = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "modinfo hv_vmbus | grep -w version:"
$LIS_version_initial = $LIS_version_initial -split " " | Select-Object -Last 1

switch ($scenario) {
    "1" {
        # Append variables to constants.sh
        Write-Output "Starting LIS installation"
        $sts = SendCommandToVM $ipv4 $sshkey "echo -e 'action=install\nlis_folder=NEW_LISISO' >> ~/constants.sh"
        if(-not $sts[-1]) {
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Install LIS
        $sts = InstallLIS
        if( -not $sts[-1]) {
            Write-Output "Error: Cannot install LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-output "Successfully installed LIS"

        # Reboot the VM and check LIS
        StartRestartVM "restart"
        $sts = CheckSelinux
        if(-not $sts[-1]) {
            Write-Output "Error: Check failed. SELinux may prevent daemons from running." | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = VerifyDaemons
        if( -not $sts[-1]) {
            Write-Output "Error: Daemons/Modules verification failed for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_final = CheckLISVersion
        $LIS_version_final = $LIS_version_final[($LIS_version_final.count -1)] -split " " | Select-Object -Last 1

        Write-Output "LIS version after installing latest drivers: $LIS_version_final" | Tee-Object -Append -file $summaryLog
        if ($LIS_version_final -eq $LIS_version_initial) {
            Write-Output "Error: LIS version has not changed on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false     
        }

        # Stop VM and take a checkpoint
        Stop-VM -Name $vmName -ComputerName $hvServer -Confirm:$false
        Start-Sleep -s 5
        Checkpoint-VM -Name $vmName -ComputerName $hvServer -SnapshotName 'LIS_INSTALLED'
    }

    "2" {
        # Upgrade LIS
        $sts = UpgradeLIS "no"
        if( -not $sts[-1]){
            Write-Output "Error: Upgrading LIS on ${vmName} failed" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Stop VM and take a checkpoint
        Stop-VM -Name $vmName -ComputerName $hvServer -Confirm:$false
        Start-Sleep -s 5
        Checkpoint-VM -Name $vmName -ComputerName $hvServer -SnapshotName 'LIS_UPGRADE'
    }

    "3" {
        # Stop VM and revert checkpoint
        RevertSnapshot "LIS_UPGRADE"

        # Uninstall LIS
        $LIS_version_upgraded = CheckLISVersion
        $LIS_version_upgraded = $LIS_version_old[($LIS_version_old.count -1)] -split " " | Select-Object -Last 1
        $sts = SendCommandToVM $ipv4 $sshkey "sed -i 's/action=\S*/action=uninstall/g' constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = InstallLIS
        if( -not $sts[-1]){
            Write-Output "Error: Cannot uninstall LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-Output "Successfully uninstalled $current_lis."

        # Install LIS
        $sts = SendCommandToVM $ipv4 $sshkey "sed -i 's/lis_folder=\S*/lis_folder=OLD_LISISO/g' constants.sh"
        $sts = SendCommandToVM $ipv4 $sshkey "sed -i 's/action=\S*/action=install/g' constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = InstallLIS
        if( -not $sts[-1]){
            Write-Output "Error: Cannot install LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # Reboot the VM and check LIS
        StartRestartVM "restart"
        $sts = VerifyDaemons
        if( -not $sts[-1]){
            Write-Output "Error: Daemons/Modules verification failed for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_final = CheckLISVersion
        $LIS_version_final = $LIS_version_final[($LIS_version_final.count -1)] -split " " | Select-Object -Last 1

        Write-Output "LIS version after downgrade: $LIS_version_final" | Tee-Object -Append -file $summaryLog
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
        GetKernelVersion

        $sts = SendCommandToVM $ipv4 $sshkey "sync"
        Start-Sleep -s 30

        # Check if kernel was upgraded
        $sts = GetUpgradeKernelLogs
        if(-not $sts[-1]){
            Write-Output "Error: Kernel was not upgraded" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-Output "Successfully upgraded kernel."

        # Try to install LIS. It is expected to fail
        $sts = SendCommandToVM $ipv4 $sshkey "echo -e 'action=install\nlis_folder=NEW_LISISO' >> ~/constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = InstallLIS
        if($sts[-1]){
            Write-Output "Error: LIS installation succeded ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-Output "Installation failed as expected." | Tee-Object -Append -file $summaryLog
    }

    "5"{
        # Stop VM and revert checkpoint
        RevertSnapshot "LIS_INSTALLED"

        # Upgrade kernel
        $sts = UpgradeKernel
        if( -not $sts[-1]){
            Write-Output "Error: Upgrading kernel on ${vmName} failed" | Tee-Object -Append -file $summaryLog
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
        # Stop VM and revert checkpoint
        RevertSnapshot "LIS_UPGRADE"

        # Upgrade kernel
        $sts = UpgradeKernel
        if( -not $sts[-1]){
            Write-Output "Error: Upgrading kernel on ${vmName} failed" | Tee-Object -Append -file $summaryLog
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

    "7" {
        # If it's an Oracle distro, skip the test
        $is_oracle = SendCommandToVM $ipv4 $sshKey "cat /etc/os-release | grep -i oracle"
        if ($is_oracle) {
            Write-Output "Skipped: Oracle not suported on this TC"
            return $Skipped
        }

        # Upgrade to a minor kernel
        Write-Output "Upgrading minor kernel"
        $initial_kernel_version = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "uname -r"
        $sts = SendCommandToVM $ipv4 $sshkey "dos2unix utils.sh && . utils.sh && UpgradeMinorKernel >> kernel_install_scenario_$scenario.log"
        if(-not $sts[-1]) {
            Write-Output "Error: Unable to upgrade the kernel on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }
        $sts = SendCommandToVM $ipv4 $sshkey "sync"
        Start-Sleep -s 60

        # Reboot the VM and check kernel
        StartRestartVM "restart"
        $final_kernel_version = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "uname -r"
        if ($initial_kernel_version -eq $final_kernel_version) {
            Write-Output "Aborting: Kernel was not upgraded on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $aborted   
        }

        # Upgrade LIS
        $sts = UpgradeLIS "no"
        if( -not $sts[-1]){
            Write-Output "Error: Upgrading LIS on ${vmName} failed" | Tee-Object -Append -file $summaryLog
            return $false
        }
    }

    "8"{
        # Stop VM and revert checkpoint
        RevertSnapshot "LIS_INSTALLED"

        # Uninstall lis
        $sts = SendCommandToVM $ipv4 $sshkey "sed -i 's/action=\S*/action=uninstall/g' constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = InstallLIS
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
        # This TC is only supported for 7.3 and 7.4
        [string]$os_version = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "sed -e 's/^.* \([0-9].*\) (\(.*\)).*$/\1/' /etc/redhat-release"
        if ($os_version -lt "7.3") {
            Write-Output "Skipped: $os_version not suported on this TC"
            return $Skipped   
        }
        
        # Run bonding script and install LIS
        $sts = SendCommandToVM $ipv4 $sshkey "~/bondvf.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Bonding script exited with error code" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = SendCommandToVM $ipv4 $sshkey "echo -e 'action=install\nlis_folder=NEW_LISISO' >> ~/constants.sh"
        if(-not $sts[-1]){
            Write-Output "Error: Unable to add action in constants.sh on ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = InstallLIS
        if( -not $sts[-1]){
            Write-Output "Error: Cannot install LIS for ${vmName}" | Tee-Object -Append -file $summaryLog
            return $false
        }
        Write-output "Successfully installed LIS $current_lis" | Tee-Object -Append -file $summaryLog

        # Reboot the VM and check LIS
        StartRestartVM "restart"
        $sts = VerifyDaemons
        if( -not $sts[-1]){
            Write-Output "Error: Daemons/Modules verification failed for ${vmName} after install." | Tee-Object -Append -file $summaryLog
            return $false
        }

        $sts = CheckBondingErrors
        if( -not $sts[-1]) {
            Write-Output "Error: Bond errors found after LIS install." | Tee-Object -Append -file $summaryLog
            return $false
        } else {
            Write-Output "No errors found after LIS install" | Tee-Object -Append -file $summaryLog
        }

        $LIS_version_beforeUpgrade = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "modinfo hv_vmbus | grep  -w version: | cut -d ':' -f 2 | tr -d ' \t' "
        Write-output "LIS version before kernel upgrade: $LIS_version_beforeUpgrade"| Tee-Object -Append -file $summaryLog

        # Upgrade kernel
        $sts = UpgradeKernel
        if( -not $sts[-1]){
            Write-Output "Error: Upgrading kernel on ${vmName} failed" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_afterUpgrade = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "modinfo hv_vmbus | grep -w version:"
        if ($LIS_version_afterUpgrade -eq $LIS_version_beforeUpgrade){
            Write-Output "Error: After upgrading the kernel, VM booted with LIS drivers $LIS_version_afterUpgrade " | Tee-Object -Append -file $summaryLog    
        }
        else{
            Write-Output "VM booted with built-in LIS drivers after kernel upgrade" | Tee-Object -Append -file $summaryLog   
        }

        $sts = CheckBondingErrors
        if(-not $sts[-1]) {
            Write-Output "Error: Bond errors found after kernel upgrade." | Tee-Object -Append -file $summaryLog
            return $false
        } else {
            Write-Output "No errors found after kernel upgrade" | Tee-Object -Append -file $summaryLog
        }
    }
    "10" {
        # This TC is only supported for 7.3 and 7.4
        [string]$os_version = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "sed -e 's/^.* \([0-9].*\) (\(.*\)).*$/\1/' /etc/redhat-release"
        if ($os_version -lt "7.3") {
            Write-Output "Skipped: $os_version not suported on this TC"
            return $Skipped   
        }

        # Upgrade LIS
        $sts = UpgradeLIS "yes"
        if( -not $sts[-1]){
            Write-Output "Error: Upgrading LIS on ${vmName} failed" | Tee-Object -Append -file $summaryLog
            return $false
        }
        
        $sts = CheckBondingErrors
        if( -not $sts[-1]) {
            Write-Output "Error: Bond errors found after lis upgrade" | Tee-Object -Append -file $summaryLog
            return $false
        } else {
            Write-Output "No errors found after lis upgrade" | Tee-Object -Append -file $summaryLog
        }
        
        # Upgrade kernel
        $sts = UpgradeKernel
        if( -not $sts[-1]){
            Write-Output "Error: Upgrading kernel on ${vmName} failed" | Tee-Object -Append -file $summaryLog
            return $false
        }

        $LIS_version_afterUpgrade = .\bin\plink.exe -i ssh\${sshkey} root@${ipv4} "modinfo hv_vmbus | grep -w version:"
        if ($LIS_version_afterUpgrade -eq $LIS_version_beforeUpgrade){
            Write-Output "Error: After upgrading the kernel, VM booted with LIS drivers $LIS_version_afterUpgrade " | Tee-Object -Append -file $summaryLog    
        }
        else{
            Write-Output "VM booted with built-in LIS drivers after kernel upgrade" | Tee-Object -Append -file $summaryLog   
        }

        $sts = CheckBondingErrors
        if( -not $sts[-1]) {
            Write-Output "Error: Bond errors found after kernel upgrade." | Tee-Object -Append -file $summaryLog
            return $false
        } else {
            Write-Output "No errors found after kernel upgrade" | Tee-Object -Append -file $summaryLog
        }
    }
}

GetLogs

return $True