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

$params = $testParams.Split(";")

foreach ($p in $params) {
    $fields = $p.Split("=")

    switch ($fields[0].Trim()) {
        "rootDir"   { $rootDir = $fields[1].Trim() }
	"TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
        "sshKey" { $sshKey  = $fields[1].Trim() }
        "ipv4"   { $ipv4    = $fields[1].Trim() }
        "crashkernel"   { $crashkernel    = $fields[1].Trim() }
        "TestLogDir" { $logdir = $fields[1].Trim() }
        "NMI" { $nmi = $fields[1].Trim() }
        "VM2NAME" { $vm2Name = $fields[1].Trim() }
		"use_nfs" { $use_nfs = $fields[1].Trim() }
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

# Change the working directory to where we need to be
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist!"
    return $False
}
cd $rootDir

# Delete any previous summary.log file
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

$retVal = $True

# Source TCUtils.ps1 for test related functions
  if (Test-Path ".\setupScripts\TCUtils.ps1")
  {
    . .\setupScripts\TCUtils.ps1
  }
  else
  {
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
  }

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
            return $False
        }
        $timeout = 240 # seconds
        if (-not (WaitForVMToStartKVP $vm2Name $hvServer $timeout))
        {
            "Warning: $vm2Name never started KVP"
        }

       sleep 10

        $vm2ipv4 = GetIPv4 $vm2Name $hvServer

        $timeout = 200 #seconds
        if (-not (WaitForVMToStartSSH $vm2ipv4 $timeout))
        {
            "Error: VM ${vm2Name} never started"
            Stop-VM $vm2Name -ComputerName $hvServer -force | out-null
            return $False
        }

    "Info: Succesfully started dependency VM ${vm2Name}"
    }

    SendFileToVM $vm2ipv4 $sshKey ".\remote-scripts\ica\Kdump_nfs_config.sh" "/root/kdump_nfs_config.sh"
    $retVal = SendCommandToVM $vm2ipv4 $sshKey "cd /root && dos2unix kdump_nfs_config.sh && chmod u+x kdump_nfs_config.sh && ./kdump_nfs_config.sh"
    if ($retVal -eq $False)
    {
        Write-Output "Error: Failed to configure the NFS server!"
        return $false
    }
}

#
# Copying required scripts to VM for generating kernel panic with appropriate permissions
#
$retVal = SendFileToVM $ipv4 $sshKey ".\remote-scripts\ica\kdump_config.sh" "/root/kdump_config.sh"

# check the return Value of SendFileToVM
if (-not $retVal)
{
    Write-Output "Error: Failed to send kdump_config.sh to VM."
    return $false
}
Write-Output "Success: send kdump_config.sh to VM."

$retVal = SendCommandToVM $ipv4 $sshKey "cd /root && dos2unix kdump_config.sh && chmod u+x kdump_config.sh && ./kdump_config.sh $crashkernel $vm2ipv4"
if ($retVal -eq $False)
{
    Write-Output "Error: Failed to configure kdump. Check logs for details."
    return $false
}
#
# Rebooting the VM in order to apply the kdump settings
#

$retVal = SendCommandToVM $ipv4 $sshKey "reboot"
Write-Output "Rebooting the VM."

#
# Waiting the VM to start up
Write-Output "Waiting the VM to have a connection..."
do {
    sleep 5
} until(Test-NetConnection $ipv4 -Port 22 -WarningAction SilentlyContinue | ? { $_.TcpTestSucceeded } )

#
# Copying required scripts to VM for generating kernel panic with appropriate permissions
#
$retVal = SendFileToVM $ipv4 $sshKey ".\remote-scripts\ica\kdump_execute.sh" "/root/kdump_execute.sh"

# check the return Value of SendFileToVM
if (-not $retVal)
{
    Write-Output "Error: Failed to send kdump_execute.sh to VM."
    return $false
}
Write-Output "Success: send kdump_execute.sh to VM."

$retVal = SendCommandToVM $ipv4 $sshKey "cd /root && dos2unix kdump_execute.sh && chmod u+x kdump_execute.sh && ./kdump_execute.sh"
if ($retVal -eq $False)
{
    Write-Output "Error: Configuration is not correct. Check logs for details."
    bin\pscp -q -i ssh\${sshKey} root@${ipv4}:summary.log $logdir
    return $false
}

# Trigger the kernel panic
Write-Output "Trigger the kernel panic..."
if ($nmi -eq 1){
    # Waiting to kdump_execute.sh to finish his activity.
    Start-Sleep -S 70
    Debug-VM -Name $vmName -InjectNonMaskableInterrupt -ComputerName $hvServer -Force
}
else {
    if ($vcpu -eq 4){
        "Kdump will be triggered on VCPU 3 of 4"
        $retVal = SendCommandToVM $ipv4 $sshKey "taskset -c 2 echo c > /proc/sysrq-trigger 2>/dev/null &"
    }
    else {
        $retVal = SendCommandToVM $ipv4 $sshKey "echo c > /proc/sysrq-trigger 2>/dev/null &"
    }
}

#
# Give the host a few seconds to record the event
#
Write-Output "Waiting 200 seconds to record the event..."
Start-Sleep -S 200
if ((Get-VMIntegrationService -VMName $vmName -ComputerName $hvServer | ?{$_.name -eq "Heartbeat"}).PrimaryStatusDescription -eq "Lost Communication") {
    Write-Output "Error : Lost Communication to VM"
    Stop-VM -Name $vmName -ComputerName $hvServer -Force
    return $False
}

Write-Output "Info: VM Heartbeat is OK"

# Waiting the VM to have a connection
Write-Output "Checking the VM connection after kernel panic..."

$sts = WaitForVMToStartSSH $ipv4 100
if (-not $sts[-1]){
    Write-Output "Error: $vmName didn't restart after triggering the crash"
    return $false
}

#
# Verifying if the kernel panic process creates a vmcore file of size 10M+
#
Write-Output "Connection to VM is good. Checking the results..."
$retVal = SendFileToVM $ipv4 $sshKey ".\remote-scripts\ica\kdump_results.sh" "/root/kdump_results.sh"

# check the return Value of SendFileToVM
if (-not $retVal)
{
    Write-Output "Error: Failed to send kdump_results.sh to VM."
    return $false
}
Write-Output "Success: sent kdump_results.sh to VM."

$retVal = SendCommandToVM $ipv4 $sshKey "cd /root && dos2unix kdump_results.sh && chmod u+x kdump_results.sh && ./kdump_results.sh $vm2ipv4"
if ($retVal -eq $False)
{
    Write-Output "Error: Results are not as expected. Check logs for details."
    bin\pscp -q -i ssh\${sshKey} root@${ipv4}:summary.log $logdir
    return $false
}

bin\pscp -q -i ssh\${sshKey} root@${ipv4}:summary.log $logdir
# Stop NFS server
if ($vm2Name)
{
    Stop-VM -vmName $vm2Name -ComputerName $hvServer -Force
}

return $True
