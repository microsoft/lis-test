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
    Perform tens of Save/Pause operations and check the time for the VF to
    get up

.Description
    1.  Configure two VMs, where each VM has a SR-IOV device.
    2.  Start iPerf3 server on test VM
    3.  Start iPerf3 client on dependency VM for 30 minutes
    4.  Measure throughput in dependency VM.
    5.  Save/Pause the test VM for 5 seconds
    6.  Resume test VM
    7.  Check throughput on dependency VM and measure how long it takes to 
        get a throughput close to the throughput measured before saving the VM.
    8.  Repeat steps 5-7 for 30 minutes

.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

.Example
    <test>
        <testName>Stress_SaveVM</testName>
        <testScript>setupScripts\SR-IOV_Stress_SavePause.ps1</testScript>
        <files>remote-scripts/ica/utils.sh</files> 
        <setupScript>
            <file>setupscripts\RevertSnapshot.ps1</file>
            <file>setupscripts\SR-IOV_enable.ps1</file>
        </setupScript> 
        <noReboot>False</noReboot>
        <testParams>
            <param>NIC=NetworkAdapter,External,SRIOV,001600112800</param>
            <param>TC_COVERED=SRIOV-25</param>                                   
            <param>BOND_IP1=10.11.12.31</param>
            <param>BOND_IP2=10.11.12.32</param>
            <param>NETMASK=255.255.255.0</param>
            <!-- VM_STATE has to be 'pause' or 'save' -->
            <param>VM_STATE=save</param>
        </testParams>
        <cleanupScript>setupscripts\SR-IOV_ShutDown_Dependency.ps1</cleanupScript>
        <timeout>1800</timeout>
    </test>
#>

param ([String] $vmName, [String] $hvServer, [string] $testParams)

#############################################################
#
# Main script body
#
#############################################################
$retVal = $False

#
# Check the required input args are present
#

# Write out test Params
$testParams


if ($hvServer -eq $null)
{
    "ERROR: hvServer is null"
    return $False
}

if ($testParams -eq $null)
{
    "ERROR: testParams is null"
    return $False
}

#change working directory to root dir
$testParams -match "RootDir=([^;]+)"
if (-not $?)
{
    "Mandatory param RootDir=Path; not found!"
    return $false
}
$rootDir = $Matches[1]

if (Test-Path $rootDir)
{
    Set-Location -Path $rootDir
    if (-not $?)
    {
        "ERROR: Could not change directory to $rootDir !"
        return $false
    }
    "Changed working directory to $rootDir"
}
else
{
    "ERROR: RootDir = $rootDir is not a valid path"
    return $false
}

# Source TCUitls.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1")
{
    . .\setupScripts\TCUtils.ps1
}
else
{
    "ERROR: Could not find setupScripts\TCUtils.ps1"
    return $false
}

# Source NET_UTILS.ps1 for network functions
if (Test-Path ".\setupScripts\NET_UTILS.ps1")
{
    . .\setupScripts\NET_UTILS.ps1
}
else
{
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
        "BOND_IP1" { $vmBondIP1 = $fields[1].Trim() }
        "BOND_IP2" { $vmBondIP2 = $fields[1].Trim() }
        "NETMASK"  { $netmask = $fields[1].Trim() }
        "REMOTE_USER" { $remoteUser = $fields[1].Trim() }
        "REMOTE_SERVER" { $remoteServer = $fields[1].Trim() }
        "VM2NAME"  { $vm2Name = $fields[1].Trim() }
        "VM_STATE" { $vmState = $fields[1].Trim()}
        "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    }
}
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Get IPs
$ipv4 = GetIPv4 $vmName $hvServer
"${vmName} IP Address: ${ipv4}"
$vm2ipv4 = GetIPv4 $vm2Name $remoteServer
"${vm2Name} IP Address: ${vm2ipv4}"

#
# Construct commands based on the test case - save or pause
#
if ( $vmState -eq "pause" ) {
    $cmd_StateChange = "Suspend-VM -Name `$vmName -ComputerName `$hvServer -Confirm:`$False"
    $cmd_StateResume = "Resume-VM -Name `$vmName -ComputerName `$hvServer -Confirm:`$False"
}

elseif ( $vmState -eq "save" ) {
    $cmd_StateChange = "Save-VM -Name `$vmName -ComputerName `$hvServer -Confirm:`$False"
    $cmd_StateResume = "Start-VM -Name `$vmName -ComputerName `$hvServer -Confirm:`$False"
}

else {
    "ERROR: Check the parameters! It should have VM_STATE=pause or VM_STATE=save" | Tee-Object -Append -file $summaryLog
    return $false    
}

#
# Configure the bond on test VM
#
Start-Sleep -s 5
$retVal = ConfigureBond $ipv4 $sshKey $netmask
if (-not $retVal)
{
    "ERROR: Failed to configure bond on vm $vmName (IP: ${ipv4}), by setting a static IP of $vmBondIP1 , netmask $netmask"
    return $false
}

#
# Install iPerf3 on VM1
#
Start-Sleep -s 5
"Installing iPerf3 on ${vmName}"
$retval = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "dos2unix SR-IOV_Utils.sh && source SR-IOV_Utils.sh && InstallDependencies"
if (-not $retVal)
{
    "ERROR: Failed to install iPerf3 on vm $vmName (IP: ${ipv4})"
    return $false
}

#
# Reboot VM
#
Start-Sleep -s 5
Restart-VM -VMName $vmName -ComputerName $hvServer -Force
$sts = WaitForVMToStartSSH $ipv4 200
if( -not $sts[-1]){
    "ERROR: VM $vmName has not booted after the restart" | Tee-Object -Append -file $summaryLog
    return $false    
}
# Get IPs
$ipv4 = GetIPv4 $vmName $hvServer
"${vmName} IP Address: ${ipv4}"

#
# Start iPerf3 on both VMs
#
# Start the client side
Start-Sleep -s 5
"Start Client"
.\bin\plink.exe -i ssh\$sshKey root@${vm2ipv4}  "kill `$(ps aux | grep iperf | head -1 | awk '{print `$2}')"
.\bin\plink.exe -i ssh\$sshKey root@${vm2ipv4}  "iperf3 -s > client.out &"

"Start Server"
# Start iPerf3 testing
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "echo 'source constants.sh && iperf3 -t 1800 -c `$BOND_IP2 --logfile PerfResults.log &' > runIperf.sh"
Start-Sleep -s 5
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "bash ~/runIperf.sh > ~/iPerf.log 2>&1"

# Wait 10 seconds and read the throughput
Start-Sleep -s 10
[decimal]$vfInitialThroughput = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PerfResults.log | head -1 | awk '{print `$7}'"
if (-not $vfInitialThroughput){
    "ERROR: No result was logged! Check if iPerf was executed!" | Tee-Object -Append -file $summaryLog
    return $false
}

"The throughput before starting the stress test is $vfInitialThroughput Gbits/sec" | Tee-Object -Append -file $summaryLog
# Get 70% of the initial throughput
[decimal]$vfInitialThroughput = $vfInitialThroughput * 0.7
[decimal]$vfThroughput = $vfInitialThroughput
"Values under $vfInitialThroughput Gbits/sec will end this test with a failure"
Start-Sleep -s 10

#
# Start the stress test
#
$isDone = $False
[int]$counter = 0
while ($isDone -eq $False) 
{
    [int]$timeToSwitch = 0
    $counter++
    $hasSwitched = $false

    # Read the throughput before changing VM state
    [decimal]$vfBeforeThroughput = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PerfResults.log | head -1 | awk '{print `$7}'"

    # Change state
    iex $cmd_StateChange
    Start-Sleep -s 5
    
    # Resume initial state
    iex $cmd_StateResume
    $hasResumed = 0

    # Check if the VM is running. If after 10 seconds it's not running, fail the test
    while ($hasResumed -le 20){
        $checkState = Get-VM -Name $vmName -ComputerName $hvServer
        if ($checkState.State -notlike "Running"){
            Start-Sleep -m 500
        }
        else {
            $hasResumed = 20
        }

        $hasResumed++
        if ($hasResumed -eq 20) {
            "ERROR: VM has not resumed after 10 seconds on run $counter" | Tee-Object -Append -file $summaryLog
            return $false     
        }
    }

    # Start measuring the time to switch between netvsc and VF
    # Throughput  will also be measured
    while ($hasSwitched -eq $false){
        # This check is made to determine if iPerf3 is still running
        $iperfDone = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -1 PerfResults.log | grep Done"
        if ($iperfDone) {
            $isDone = $true
            $hasSwitched = $true
            break
        }

        # Get the throughput
        [decimal]$vfAfterThroughput = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "tail -2 PerfResults.log | head -1 | grep Gbits | awk '{print `$7}'"

        # Compare results with the ones taken before the stress test
        # If they are simillar, end the 'while loop' and proceed to another state change
        if (($vfAfterThroughput -ne $vfBeforeThroughput) -and ($vfAfterThroughput -ge $vfInitialThroughput)){
            $hasSwitched = $true
        }
        # If they are not simillar, check the measured time
        # If it's bigger than 5 seconds, make an additional check, to see if the VF is running
        # If more than 5 seconds passed and also VF is not running, fail the test
        else {  
            if ($timeToSwitch -gt 5){
                $interfaceOutput = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "ifconfig | grep enP"
                if ($interfaceOutput -and ($vfAfterThroughput -gt 0)){
                    "Info: On run $counter, the throughput did not increase enough ($vfAfterThroughput gbps), but VF is up" | Tee-Object -Append -file $summaryLog
                    $hasSwitched = $true
                }
                else {
                    "ERROR: On run $counter - after 6 seconds, the iPerf3 throughput has not increased enough ($vfAfterThroughput gbps)
                    ifconfig shows that VF is also down" | Tee-Object -Append -file $summaryLog
                    return $false
                }     
            }
            Start-Sleep -s 1
        }

        $timeToSwitch++
    }

    "Run $counter :: Time to switch between netvsc and VF was $timeToSwitch seconds. Throughput was $vfAfterThroughput gbps"
}

"VM $vmName changed its state for $counter times and no issues were encountered" | Tee-Object -Append -file $summaryLog
return $true