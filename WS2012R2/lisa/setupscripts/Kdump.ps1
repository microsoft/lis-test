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

function CheckResults(){
    #
    # Checking test results
    #
    $stateFile = "state.txt"

    bin\pscp -q -i ssh\${1} root@${2}:${stateFile} .
    $sts = $?

    if ($sts) {
        if (test-path $stateFile){
            $contents = Get-Content $stateFile
            if ($null -ne $contents){
                if ($contents.Contains('TestCompleted') -eq $True) {                    
                    Write-Output "Info: Test ended successfully"
                    $retVal = $True
                }
                if ($contents.Contains('TestAborted') -eq $True) {
                    Write-Output "Info: State file contains TestAborted failed"
                    $retVal = $False                           
                }
                if ($contents.Contains('TestFailed') -eq $True) {
                    Write-Output "Info: State file contains TestFailed failed"
                    $retVal = $False                           
                }
            }    
            else {
                Write-Output "ERROR: state file is empty!"
                $retVal = $False    
            }
        }
    }
    return $retval
}

#
# MAIN SCRIPT
#
$retVal = $false
$sshKey = $null
$ipv4 = $null
$nmi = $null

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
        "sshKey" { $sshKey  = $fields[1].Trim() }
        "ipv4"   { $ipv4    = $fields[1].Trim() }
        "crashkernel"   { $crashkernel    = $fields[1].Trim() }
        "TestLogDir" {$logdir = $fields[1].Trim()}
        "NMI" {$nmi = $fields[1].Trim()}
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

if (-not $rootDir)
{
    "Warn : no rootdir was specified"
}
else
{
    cd $rootDir
}

# Source TCUitls.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1")
{
    . .\setupScripts\TCUtils.ps1
}
else
{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
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

$retVal = SendCommandToVM $ipv4 $sshKey "cd /root && dos2unix kdump_config.sh && chmod u+x kdump_config.sh && ./kdump_config.sh $crashkernel"

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

bin\pscp -q -i ssh\${sshKey} root@${ipv4}:summary.log $logdir
$retVal = CheckResults $sshKey $ipv4
if (-not $retVal)
{
    "ERROR: Results are not as expected(configuration problems). Test Aborted."
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

Write-Output "VM Heartbeat is OK."

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

$retVal = SendCommandToVM $ipv4 $sshKey "cd /root && dos2unix kdump_results.sh && chmod u+x kdump_results.sh && ./kdump_results.sh"

$retVal = CheckResults $sshKey $ipv4
return $retVal