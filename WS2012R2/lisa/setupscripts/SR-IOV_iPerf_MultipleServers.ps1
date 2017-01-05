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
    Multiple VM SR-IOV test

.Description
    a. Using two Hyper-V hosts, create Linux VMs, VM1 and VM2, on the first host,
       and  VM3 and VM4 on the second Hyper-V host.
    b. Configure each VM with a synthetic NIC with SR-IOV enabled on
       the vSwitch and the VMs NIC.
    c. On each Linux VM, run the bonding script to create the bond0 device.
    d. Verify the bond0 device is working on each VM.
    e. Run iPerf from VM1 to VM3 and from VM2 to VM4 simultaneously
 Acceptance Criteria
    a. iPerf completes.
    b. Dropped packets does not exceed 3% of total packets.

    
.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

.Example
    <test>
        <testName>Single_SaveVM</testName>
        <testScript>setupScripts\SR-IOV_SavePauseVM.ps1</testScript>
        <files>remote-scripts/ica/utils.sh</files> 
        <setupScript>
            <file>setupscripts\RevertSnapshot.ps1</file>
            <file>setupscripts\SR-IOV_enable.ps1</file>
        </setupScript> 
        <noReboot>False</noReboot>
        <testParams>
            <param>NIC=NetworkAdapter,External,SRIOV,001600112200</param>
            <param>TC_COVERED=??</param>                                   
            <param>BOND_IP1=10.11.12.31</param>
            <param>BOND_IP2=10.11.12.32</param>
            <param>NETMASK=255.255.255.0</param>
            <param>REMOTE_USER=root</param>
            <!-- VM_STATE has to be 'pause' or 'save' -->
            <param>VM_STATE=save</param>
        </testParams>
        <timeout>1800</timeout>
    </test>
#>

param ([String] $vmName, [String] $hvServer, [string] $testParams)

function StopVM ([String] $vmName, [String] $hvServer)
{
    # Make sure VM2 is shutdown
    if (Get-VM -Name $vmName -ComputerName $hvServer |  Where { $_.State -like "Running" }) {
        Stop-VM $vmName  -ComputerName $hvServer -force

        if (-not $?)
        {
            "ERROR: Failed to shut $vm2Name down (in order to add a new network Adapter)"
            return $false
        }

        # wait for VM to finish shutting down
        $timeout = 60
        while (Get-VM -Name $vmName -ComputerName $hvServer |  Where { $_.State -notlike "Off" })
        {
            if ($timeout -le 0) {
                "ERROR: Failed to shutdown $vmName"
                return $false
            }

            start-sleep -s 5
            $timeout = $timeout - 5
        }

    }
}
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
        "NETMASK" { $netmask = $fields[1].Trim() }
        "VM2NAME" { $vm2Name = $fields[1].Trim() }
        "REMOTE_SERVER" { $remoteServer = $fields[1].Trim()}
        "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
        "VM3NAME" { $vm3name = $fields[1].Trim() }
        "VM4NAME" { $vm4name = $fields[1].Trim() }
        "VM3BOND_IP" { $vm3bondIP = $fields[1].Trim() }
        "VM4BOND_IP" { $vm4bondIP = $fields[1].Trim() }
    }
}

$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Configure the bond on test VM
#
$retVal = ConfigureBond $ipv4 $sshKey $netmask
if (-not $retVal)
{
    "ERROR: Failed to configure bond on vm $vmName (IP: ${ipv4}), by setting a static IP of $vmBondIP1 , netmask $netmask"
    return $false
}

#
# Start VM3 and VM4 and configure them
#
$retVal = ConfigureVMandBond $vm3Name $hvServer $sshKey $vm3bondIP $netmask
if (-not $retVal)
{
    "ERROR: Failed to configure vm $vm3Name on $hvServer"
    return $false
}
$retVal = ConfigureVMandBond $vm4Name $hvServer $sshKey $vm4bondIP $netmask
if (-not $retVal)
{
    "ERROR: Failed to configure vm $vm4Name on $remoteServer"
    return $false
}

# Get ipv4 from VM2
$vm2ipv4 = GetIPv4 $vm2Name $remoteServer 
"$vm2Name IPADDRESS: $vm2ipv4"

# Get ipv4 from VM3
$vm3ipv4 = GetIPv4 $vm3Name $hvServer
"$vm3Name IPADDRESS: $vm3ipv4"

# Get ipv4 from VM4
$vm4ipv4 = GetIPv4 $vm4Name $hvServer
"$vm4Name IPADDRESS: $vm4ipv4"

# Send BOND_IP2 to VM3 and VM4. This ip will be used by iPerf
$commandToSend = "echo -e BOND_IP2=${vmBondIP2} >> constants.sh"
$retVal = SendCommandToVM "$vm3ipv4" "$sshKey" $commandToSend
if (-not $retVal)
{
    "Failed appending $ipToSend to constants.sh on VM3"
    return $False
}

$retVal = SendCommandToVM "$vm4ipv4" "$sshKey" $commandToSend
if (-not $retVal)
{
    "Failed appending $ipToSend to constants.sh on VM4"
    return $False
}

Start-Sleep -s 5
"All 4 VMs were successfully configured"

#
# Run iPerf3 with SR-IOV enabled
#
# Start the client side on VM2 and VM4
"Start Client"
.\bin\plink.exe -i ssh\$sshKey root@${vm2ipv4}  "iperf3 -s -p 5201 > client.out &"
.\bin\plink.exe -i ssh\$sshKey root@${vm2ipv4}  "iperf3 -s -p 5202 > client.out &"
.\bin\plink.exe -i ssh\$sshKey root@${vm2ipv4}  "iperf3 -s -p 5203 > client.out &"

Start-Sleep -s 5
# Start iPerf3 testing
"Start Servers"
.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "echo 'source constants.sh && iperf3 -c `$BOND_IP2 -p 5201 -u -t 100 --logfile PerfResults.log &' > runIperf.sh"
.\bin\plink.exe -i ssh\$sshKey root@${vm3ipv4} "echo 'source constants.sh && iperf3 -c `$BOND_IP2 -p 5202 -u -t 100 --logfile PerfResults.log &' > runIperf.sh"
.\bin\plink.exe -i ssh\$sshKey root@${vm4ipv4} "echo 'source constants.sh && iperf3 -c `$BOND_IP2 -p 5203 -u -t 100 --logfile PerfResults.log &' > runIperf.sh"


.\bin\plink.exe -i ssh\$sshKey root@${ipv4} "bash ~/runIperf.sh > ~/iPerf.log 2>&1"
.\bin\plink.exe -i ssh\$sshKey root@${vm3ipv4} "bash ~/runIperf.sh > ~/iPerf.log 2>&1"
.\bin\plink.exe -i ssh\$sshKey root@${vm4ipv4}  "bash ~/runIperf.sh > ~/iPerf.log 2>&1"

# Get the logs
"Get Logs"
Start-Sleep -s 120
$droppedPackets = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "cat PerfResults.log | grep % | sed 's/(/ /' | sed 's/%./ /' | awk '{print `$12}'"
if (-not $droppedPackets){
    "ERROR: No result was logged on VM1! Check if iPerf was executed on VM1!" | Tee-Object -Append -file $summaryLog
    return $false
}

"The droppedPackets percentage on Server 1 is ${droppedPackets}%" | Tee-Object -Append -file $summaryLog

$droppedPackets2 = .\bin\plink.exe -i ssh\$sshKey root@${vm3ipv4} "cat PerfResults.log | grep % | sed 's/(/ /' | sed 's/%./ /' | awk '{print `$12}'"
if (-not $droppedPackets2){
    "ERROR: No result was logged on VM3! Check if iPerf was executed on VM3!" | Tee-Object -Append -file $summaryLog
    return $false
}

"The droppedPackets percentage on Server 2 is ${droppedPackets2}%" | Tee-Object -Append -file $summaryLog

$droppedPackets3 = .\bin\plink.exe -i ssh\$sshKey root@${vm4ipv4} "cat PerfResults.log | grep % | sed 's/(/ /' | sed 's/%./ /' | awk '{print `$12}'"
if (-not $droppedPackets3){
    "ERROR: No result was logged on VM4! Check if iPerf was executed on VM4!" | Tee-Object -Append -file $summaryLog
    return $false
}

"The droppedPackets percentage on Server 3 is ${droppedPackets3}%" | Tee-Object -Append -file $summaryLog

if (($droppedPackets -ge 3) -or ($droppedPackets2 -ge 3) -or ($droppedPackets3 -ge 3)){
    "ERROR: The dropped packets are more than 3%" | Tee-Object -Append -file $summaryLog
    return $false  
}

#
# Stop all dependenncy VMs
#
StopVM $vm2Name $remoteServer
StopVM $vm3Name $hvServer
StopVM $vm4Name $hvServer

return $true