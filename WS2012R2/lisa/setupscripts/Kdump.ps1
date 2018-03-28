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
param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false
$TC_COVERED = $null
$sshKey = $null
$ipv4 = $null
$nmi = $null
# variable to define if a NFS location should be used for the crash files
$use_nfs = $null

#
# Check input arguments
#
if ($vmName -eq $null) {
    "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null) {
    "Error: hvServer is null"
    return $retVal
}

if ($testParams -eq $null)
{
    Throw "Error: No test parameters specified"
}

#
# Parse test parameters
#
$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")

    switch ($fields[0].Trim()) {
      "rootDir"       { $rootDir = $fields[1].Trim() }
      "TC_COVERED"    { $TC_COVERED = $fields[1].Trim() }
      "sshKey"        { $sshKey  = $fields[1].Trim() }
      "ipv4"          { $ipv4    = $fields[1].Trim() }
      "crashkernel"   { $crashkernel    = $fields[1].Trim() }
      "TestLogDir"    { $logdir = $fields[1].Trim() }
      "NMI"           { $nmi = $fields[1].Trim() }
      "VM2NAME"       { $vm2Name = $fields[1].Trim() }
      "use_nfs"       { $use_nfs = $fields[1].Trim() }
      "VCPU"          { $vcpu = $fields[1].Trim() }
      default         {}
    }
}

if ($null -eq $sshKey) {
    "Error: Test parameter sshKey was not specified"
    return $false
}

if ($null -eq $ipv4) {
    "Error: Test parameter ipv4 was not specified"
    return $false
}

#
# Change the working directory to where we need to be
#
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist!"
    return $false
}
cd $rootDir

if ($null -eq $crashkernel)
{
    "FAIL: Test parameter crashkernel was not specified"
    return $false
}

#
# Delete any previous summary.log file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Source TCUtils.ps1 for test related functions
#
if (Test-Path ".\setupScripts\TCUtils.ps1")
{
  . .\setupScripts\TCUtils.ps1
}
else
{
  "Error: Could not find setupScripts\TCUtils.ps1"
  return $false
}
$BuildNumber = GetHostBuildNumber $hvServer
$RHEL7_Above = GetVMFeatureSupportStatus $ipv4 $sshKey "3.10.0-123"

# WS2012 does not support Debug-VM NMI injection, skipping
if ( ($BuildNumber -eq "9200") -and ($nmi -eq 1) ) {
    Write-Output "Info: WS2012 does not support Debug-VM NMI injection" | Tee-Object -Append -file $summaryLog
    return $Skipped
}

#
# Confirm the second VM and NFS
#
if ($vm2Name -And $use_nfs -eq "yes")
{
    $checkState = Get-VM -Name $vm2Name -ComputerName $hvServer

    if ($checkState.State -notlike "Running")
    {
        Start-VM -Name $vm2Name -ComputerName $hvServer
        if (-not $?)
        {
            "Error: Unable to start VM ${vm2Name}"
            $error[0].Exception
            return $false
        }

        "Info: Succesfully started dependency VM ${vm2Name}"
    }

    $new_ip = GetIPv4AndWaitForSSHStart $vm2Name $hvServer $sshKey 360
    if ($new_ip) {$vm2ipv4 = $new_ip}
    else {
        Write-Output "Error: Failed to boot up NFS Server $vm2Name" | Tee-Object -Append -file $summaryLog
        return $Failed
    }

    $retVal = SendCommandToVM $ipv4 $sshKey "echo 'vm2ipv4=$vm2ipv4' >> ~/constants.sh"
    if ($retVal -eq $false)
    {
        Write-Output "Error: Failed to echo $vm2ipv4 to constants.sh" | Tee-Object -Append -file $summaryLog
        bin\pscp -q -i ssh\${sshKey} root@${ipv4}:summary.log $logdir/${TC_COVERED}_config_fail_summary.log
        return $false
    }
    # Configure NFS for kdump
    SendFileToVM $vm2ipv4 $sshKey "remote-scripts/ica/utils.sh" "/root/utils.sh"
    SendFileToVM $vm2ipv4 $sshKey "remote-scripts/ica/kdump_nfs_config.sh" "/root/kdump_nfs_config.sh"
    if (-not $?)
    {
        Write-Host "Error: Unable to send NFS config file to $vm2Name" | Tee-Object -Append -file $summaryLog
        return $False
    }

    $retVal = SendCommandToVM $vm2ipv4 $sshKey "cd /root && dos2unix kdump_nfs_config.sh && chmod u+x kdump_nfs_config.sh && ./kdump_nfs_config.sh"
    if ($retVal -eq $false)
    {
        Write-Output "Error: Failed to configure the NFS server!" | Tee-Object -Append -file $summaryLog
        return $false
    }
}

#
# Configure kdump on the VM
#

# Append host build number to constants.sh
$retVal = SendCommandToVM $ipv4 $sshkey "echo BuildNumber=$BuildNumber >> /root/constants.sh"
if (-not $retVal[-1]){
    Write-Output "Error: Could not echo BuildNumber=$BuildNumber to vm's constants.sh."
    return $Failed
}

$retVal = RunRemoteScript "kdump_config.sh"
if ($retVal[-1] -eq $false )
{
    Write-Output "Error: Failed to configure kdump. Check logs for details." | Tee-Object -Append -file $summaryLog
    bin\pscp -q -i ssh\${sshKey} root@${ipv4}:summary.log $logdir/${TC_COVERED}_config_fail_summary.log
    return $Failed
}

if ($Skipped -eq $retVal[-1])
{
    Write-Output "Info: This distro does not support crashkernel=$crashkernel." | Tee-Object -Append -file $summaryLog
    bin\pscp -q -i ssh\${sshKey} root@${ipv4}:summary.log $logdir/${TC_COVERED}_config_skip_summary.log
    return $Skipped
}
bin\pscp -q -i ssh\${sshKey} root@${ipv4}:summary.log $logdir/${TC_COVERED}_config_pass_summary.log

#
# Rebooting the VM in order to apply the kdump settings
#
$retVal = SendCommandToVM $ipv4 $sshKey "reboot"
Write-Output "Rebooting VM $vmName after kdump configuration..."
Start-Sleep 10 # Wait for kvp & ssh services stop

# Wait for VM boot up and update ip address
$new_ip = GetIPv4AndWaitForSSHStart $vmName $hvServer $sshKey 360
if ($new_ip) {$ipv4 = $new_ip}
else{
    Write-Output "Error: VM $vmName failed at reboot after kdump configuration" | Tee-Object -Append -file $summaryLog
    return $Failed
}

#
# Prepare the kdump related
#
$retVal = SendCommandToVM $ipv4 $sshKey "cd /root && dos2unix kdump_execute.sh && chmod u+x kdump_execute.sh && ./kdump_execute.sh"
if ($retVal -eq $false)
{
    Write-Output "Error: Configuration is not correct. Check logs for details." | Tee-Object -Append -file $summaryLog
    bin\pscp -q -i ssh\${sshKey} root@${ipv4}:summary.log $logdir/${TC_COVERED}_execute_fail_summary.log
    return $false
}
bin\pscp -q -i ssh\${sshKey} root@${ipv4}:summary.log $logdir/${TC_COVERED}_execute_pass_summary.log

#
# Trigger the kernel panic
#
Write-Output "Trigger the kernel panic..."
if ($nmi -eq 1){
    # Waiting to kdump_execute.sh to finish execution.
    Start-Sleep -S 100
    Debug-VM -Name $vmName -InjectNonMaskableInterrupt -ComputerName $hvServer -Force
}
else {
    if ($vcpu -eq 4){
        "Kdump will be triggered on VCPU 3 of 4"
        $retVal = SendCommandToVM $ipv4 $sshKey "taskset -c 2 echo c > /proc/sysrq-trigger 2>/dev/null &"
    }
    elseif ($vcpu -eq 1){
        # if vcpu=1, directly use plink to trigger kdump, command fails to exit, so use start-process
        $tmpCmd = "echo c > /proc/sysrq-trigger 2>/dev/null &"
        Start-Process bin\plink -ArgumentList "-i ssh\${sshKey} root@${ipv4} ${tmpCmd}" -NoNewWindow
    }
    else {
        $retVal = SendCommandToVM $ipv4 $sshKey "echo c > /proc/sysrq-trigger 2>/dev/null &"
    }
}

#
# Give the host a few seconds to record the event
#
Write-Output "Waiting seconds to record the event..."
Start-Sleep 10

# Workaround a won't be fixed bug on WS2016 - RHEL6:
# https://bugzilla.redhat.com/show_bug.cgi?id=1383037
if ( (-not $RHEL7_Above) -and ($BuildNumber -eq "14393") ){
    Start-Sleep 120 # Make sure dump completed
    Stop-VM -vmName $vmName -ComputerName $hvServer -TurnOff
    Start-VM -vmName $vmName -ComputerName $hvServer
}

# Wait for VM boot up and update ip address
$new_ip = GetIPv4AndWaitForSSHStart $vmName $hvServer $sshKey 360
if ($new_ip) {$ipv4 = $new_ip}
else{
    Write-Output "Error: VM $vmName failed at reboot after configuration" | Tee-Object -Append -file $summaryLog
    return $Failed
}

#
# Verifying if the kernel panic process creates a vmcore file of size 10M+
#
$retVal = SendCommandToVM $ipv4 $sshKey "cd /root && dos2unix kdump_results.sh && chmod u+x kdump_results.sh && ./kdump_results.sh $vm2ipv4"
if ($retVal -ne $true)
{
    Write-Output "Error: Results are not as expected. Check logs for details." | Tee-Object -Append -file $summaryLog
    bin\pscp -q -i ssh\${sshKey} root@${ipv4}:summary.log $logdir/${TC_COVERED}_results_fail_summary.log
    #
    # Stop NFS server VM
    #
    if ($vm2Name) {
        Stop-VM -vmName $vm2Name -ComputerName $hvServer -Force
    }
    return $false
}
$result = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "find /var/crash/ -name vmcore -type f -size +10M"
Write-Output "Test passed: crash file $result is present"
bin\pscp -q -i ssh\${sshKey} root@${ipv4}:summary.log $logdir/${TC_COVERED}_results_pass_summary.log

#
# Stop NFS server VM
#
if ($vm2Name) {
    Stop-VM -vmName $vm2Name -ComputerName $hvServer -Force
}

return $true
