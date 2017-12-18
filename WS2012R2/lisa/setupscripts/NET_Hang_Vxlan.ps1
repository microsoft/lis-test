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

Set-PSDebug -Strict

#
# Check input arguments
#
if ($vmName -eq $null) {
    "Error: VM name is null" | Tee-Object -Append -file $summaryLog
    return $False
}

if ($hvServer -eq $null) {
    "Error: hvServer is null" | Tee-Object -Append -file $summaryLog
    return $False
}

if ($testParams -eq $null) {
    "Error: testParams is null" | Tee-Object -Append -file $summaryLog
    return $False
}

# sshKey used to authenticate ssh connection and send commands
$sshKey = $null

# IP Address of first VM
$ipv4 = $null

# Name of second VM
$vm2Name = $null

# name of the switch to which to connect
$netAdapterName = $null

# VM1 IPv4 Address
$vm1StaticIP = $null

# VM2 IPv4 Address
$vm2StaticIP = $null

# Netmask used by both VMs
$netmask = $null

# Snapshot name
$snapshotParam = $null

# Mac address for vm1
$vm1MacAddress = $null

# change working directory to root dir
$testParams -match "RootDir=([^;]+)"
if (-not $?) {
    "Mandatory param RootDir=Path; not found!" | Tee-Object -Append -file $summaryLog
    return $false
}
$rootDir = $Matches[1]

if (Test-Path $rootDir) {
    Set-Location -Path $rootDir
    if (-not $?) {
        "Error: Could not change directory to $rootDir !" | Tee-Object -Append -file $summaryLog
        return $false
    }
    "Changed working directory to $rootDir"
}
else {
    "Error: RootDir = $rootDir is not a valid path" | Tee-Object -Append -file $summaryLog
    return $false
}

# Source TCUitls.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
}
else {
    "Error: Could not find setupScripts\TCUtils.ps1" | Tee-Object -Append -file $summaryLog
    return $false
}

# Source NET_UTILS.ps1 for network functions
if (Test-Path ".\setupScripts\NET_UTILS.ps1") {
    . .\setupScripts\NET_UTILS.ps1
}
else {
    "Error: Could not find setupScripts\NET_Utils.ps1" | Tee-Object -Append -file $summaryLog
    return $false
}

$isDynamic = $false

$params = $testParams.Split(';')
foreach ($p in $params) {
    $fields = $p.Split("=")
    switch ($fields[0].Trim()) {
        "NIC"
        {
            $nicArgs = $fields[1].Split(',')
            if ($nicArgs.Length -eq 3) {
                $CurrentDir= "$pwd\"
                $testfile = "macAddress.file"
                $pathToFile="$CurrentDir"+"$testfile"
                $isDynamic = $true
            }
        }
    }
}

if ($isDynamic -eq $true) {
    $streamReader = [System.IO.StreamReader] $pathToFile
    $vm1MacAddress = $null
}

foreach ($p in $params)
{
    $fields = $p.Split("=")

    switch ($fields[0].Trim())
    {
    "VM2NAME" { $vm2Name = $fields[1].Trim() }
    "SshKey"  { $sshKey  = $fields[1].Trim() }
    "ipv4"    { $ipv4    = $fields[1].Trim() }
    "STATIC_IP1" { $vm1StaticIP = $fields[1].Trim() }
    "STATIC_IP2" { $vm2StaticIP = $fields[1].Trim() }
    "NETMASK" { $netmask = $fields[1].Trim() }
    "SnapshotName" { $SnapshotName = $fields[1].Trim() }
    "TestLogDir" {$logdir = $fields[1].Trim()}
    "TC_COVERED" {$tc_covered = $fields[1].Trim()}
    "SSH_PRIVATE_KEY" {$SSH_PRIVATE_KEY = $fields[1].Trim()}
    "NIC"
    {
        $nicArgs = $fields[1].Split(',')
        if ($nicArgs.Length -lt 3)
        {
            "Error: Incorrect number of arguments for NIC test parameter: $p"
            return $false

        }

        $nicType = $nicArgs[0].Trim()
        $networkType = $nicArgs[1].Trim()
        $networkName = $nicArgs[2].Trim()
        if ($nicArgs.Length -eq 4) {
            $vm1MacAddress = $nicArgs[3].Trim()
        }

        #
        # Validate the network adapter type
        #
        if ("NetworkAdapter" -notcontains $nicType)
        {
            "Error: Invalid NIC type: $nicType . Must be 'NetworkAdapter'"
            return $false
        }

        #
        # Validate the Network type
        #
        if (@("External", "Internal", "Private") -notcontains $networkType)
        {
            "Error: Invalid netowrk type: $networkType .  Network type must be either: External, Internal, Private"
            return $false
        }
    }
    default   {}  # unknown param - just ignore it
    }
}

$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Make sure the VM supports vxlan
$sts = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "dos2unix ~/utils.sh"
[int]$majorVersion = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} ". utils.sh && GetOSVersion && echo `$os_RELEASE"
[int]$minorVersion = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} ". utils.sh && GetOSVersion && echo `$os_UPDATE"
if ((($majorVersion -le 6) -and ($minorVersion -le 4)) -or $majorVersion -le 5) {
    "Error: RHEL ${majorVersion}.${minorVersion} doesn't support vxlan" | Tee-Object -Append -file $summaryLog
    return $false
}

$kernel = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "uname -a | grep 'i686\|i386'"
if( $kernel.Contains("i686") `
    -or $kernel.Contains("i386")){
        Write-Output "Info: Vxlan not supported on 32 bit OS"  | Tee-Object -Append -file $summaryLog
        return $Skipped
}

if ($isDynamic -eq $true){
    $vm1MacAddress = $streamReader.ReadLine()
    $streamReader.close()
}
else {
    $retVal = isValidMAC $vm1MacAddress

    if (-not $retVal)
    {
        "Invalid Mac Address $vm1MacAddress" | Tee-Object -Append -file $summaryLog
        return $false
    }
}

if (-not $vm1MacAddress) {
    "Error: test parameter vm1MacAddress was not specified" | Tee-Object -Append -file $summaryLog
    return $False
}

if (-not $vm2Name) {
    "Error: test parameter vm2Name was not specified" | Tee-Object -Append -file $summaryLog
    return $False
}

# make sure vm2 is not the same as vm1
if ("$vm2Name" -like "$vmName") {
    "Error: vm2 must be different from the test VM." | Tee-Object -Append -file $summaryLog
    return $false
}

if (-not $sshKey) {
    "Error: test parameter sshKey was not specified" | Tee-Object -Append -file $summaryLog
    return $False
}

if (-not $ipv4) {
    "Error: test parameter ipv4 was not specified" | Tee-Object -Append -file $summaryLog
    return $False
}

if (-not $SSH_PRIVATE_KEY) {
    "Error: test parameter SSH_PRIVATE_KEY was not specified" | Tee-Object -Append -file $summaryLog
    return $False
}
# Set the parameter for the snapshot
$snapshotParam = "SnapshotName = ${SnapshotName}"

#revert VM2
.\setupScripts\RevertSnapshot.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $snapshotParam
Start-sleep -s 5

# hold testParam data for NET_ADD_NIC_MAC script
$vm2testParam = $null
$vm2MacAddress = $null

# Get a MAC Address for VM2 Private NIC
$vm2MacAddress = getRandUnusedMAC $hvServer
$retVal = isValidMAC $vm2MacAddress
if (-not $retVal) {
    "Could not find a valid MAC for $vm2Name. Received $vm2MacAddress" | Tee-Object -Append -file $summaryLog
    return $false
}

# Construct NET_ADD_NIC_MAC Parameter
$vm2testParam = "NIC=NetworkAdapter,$networkType,$networkName,$vm2MacAddress"

if ( Test-Path ".\setupscripts\NET_ADD_NIC_MAC.ps1") {
    # Make sure VM2 is shutdown
    if (Get-VM -Name $vm2Name -ComputerName $hvServer |  Where { $_.State -like "Running" }) {

        Stop-VM $vm2Name -force
        if (-not $?) {
            "Error: Unable to shut $vm2Name down (in order to add a new network Adapter)" | Tee-Object -Append -file $summaryLog
            return $false
        }

        # wait for VM to finish shutting down
        $timeout = 60
        while (Get-VM -Name $vm2Name -ComputerName $hvServer |  Where { $_.State -notlike "Off" }) {

            if ($timeout -le 0) {
                "Error: Unable to shutdown $vm2Name" | Tee-Object -Append -file $summaryLog
                return $false
            }

            start-sleep -s 5
            $timeout = $timeout - 5
        }
    }

    .\setupscripts\NET_ADD_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
}
else {
    "Error: Could not find setupScripts\NET_ADD_NIC_MAC.ps1 ." | Tee-Object -Append -file $summaryLog
    return $false
}

if (-not $?) {
    "Error: Cannot add new NIC to $vm2Name" | Tee-Object -Append -file $summaryLog
    return $false
}

# Check if the NIC was added
$vm2nic = Get-VMNetworkAdapter -VMName $vm2Name -ComputerName $hvServer -IsLegacy:$false | where { $_.MacAddress -like "$vm2MacAddress" }

if (-not $vm2nic) {
    "Error: Could not retrieve the newly added NIC to VM2" | Tee-Object -Append -file $summaryLog
    return $false
}

# Start VM2
if (Get-VM -Name $vm2Name -ComputerName $hvServer |  Where { $_.State -notlike "Running" }) {

    Start-VM -Name $vm2Name -ComputerName $hvServer
    if (-not $?) {
        "Error: Unable to start VM ${vm2Name}" | Tee-Object -Append -file $summaryLog
        $error[0].Exception
        return $False
    }
}

$timeout = 250 # seconds
if (-not (WaitForVMToStartKVP $vm2Name $hvServer $timeout)) {
    "Error: $vm2Name never started KVP" | Tee-Object -Append -file $summaryLog
    return $false
}

# get vm2 ipv4
$vm2ipv4 = GetIPv4 $vm2Name $hvServer

# Delete old summary logs
$retVal= SendCommandToVM $vm2ipv4 $sshKey "rm summary.log"

# Send utils.sh to second vm.
Start-Sleep -s 20
.\bin\pscp.exe -q -i .\ssh\${sshKey} ".\remote-scripts\ica\utils.sh" root@${vm2ipv4}:

# Delete old summary logs
$retVal= SendCommandToVM $ipv4 $sshKey "rm summary.log"

# Configure the interfaces for both VMs
$retVal = CreateInterfaceConfig $ipv4 $sshKey "static" $vm1MacAddress $vm1StaticIP $netmask
if (-not $retVal) {
    "Error: Failed to create Interface-File on vm $ipv4 for interface with mac $vm1MacAddress, by setting a static IP of $vm1StaticIP netmask $netmask" | Tee-Object -Append -file $summaryLog
    return $false
}

$retVal = CreateInterfaceConfig $vm2ipv4 $sshKey "static" $vm2MacAddress $vm2StaticIP $netmask
if (-not $retVal) {
    "Error: Failed to create Interface-File on vm $vm2ipv4 for interface with mac $vm2MacAddress, by setting a static IP of $vm2StaticIP netmask $netmask" | Tee-Object -Append -file $summaryLog
    return $false
}

#
# Wait for second VM to set up the test interface
#
Start-Sleep -S 10
$retVal = SendFileToVM $ipv4 $sshKey ".\remote-scripts\ica\NET_Configure_Vxlan.sh" "/root/NET_Configure_Vxlan.sh"
if (-not $retVal) {
    return $false
}

$vm="local"
$retVal = SendCommandToVM $ipv4 $sshKey "cd /root && dos2unix NET_Configure_Vxlan.sh && chmod u+x NET_Configure_Vxlan.sh && ./NET_Configure_Vxlan.sh $vm1StaticIP $vm"

$first_result = CheckResults $sshKey $ipv4
if (-not $first_result[-1]) {
    "Error: Results are not as expected in configuration. Test failed. Check logs for more details." | Tee-Object -Append -file $summaryLog
    bin\pscp -q -i ssh\${sshKey} root@${ipv4}:summary.log $logdir
    Rename-Item $logdir\summary.log "${vmname}_Vxlan_Hang.log"
    return $false
}

Start-Sleep -S 10
$retVal = SendFileToVM $vm2ipv4 $sshKey ".\remote-scripts\ica\NET_Configure_Vxlan.sh" "/root/NET_Configure_Vxlan.sh"

$vm="remote"
$retVal = SendCommandToVM $vm2ipv4 $sshKey "cd /root && dos2unix NET_Configure_Vxlan.sh && chmod u+x NET_Configure_Vxlan.sh && ./NET_Configure_Vxlan.sh $vm2StaticIP $vm"

#
# Wait to second vm to configure the vxlan interface
#
Start-Sleep -S 10

# create command to be sent to first VM. This verify if we can ping the second vm through test interface and sends the rsync command.

$cmdToVM = @"
#!/bin/bash
    . /root/constants.sh
    ping -I vxlan0 242.0.0.11 -c 3
    if [ `$? -ne 0 ]; then
        echo "Failed to ping the second vm through vxlan0 after configurations." >> summary.log
        echo "TestAborted" >> state.txt
    else
        echo "Successfuly pinged the second vm through vxlan0 after configurations, connection is good." >> summary.log
        echo "Starting to transfer files with rsync" >> summary.log
        rsyncPara="ssh -o StrictHostKeyChecking=no -i /root/.ssh/`$SSH_PRIVATE_KEY"
        echo "rsync -e '`$rsyncPara' -avz /root/test root@242.0.0.11:/root" | at now +1 minutes
    fi

"@

$filename = "vxlan_test.sh"

# check for file
if (Test-Path ".\${filename}") {
    Remove-Item ".\${filename}"
}

Add-Content $filename "$cmdToVM"

# send file
$retVal = SendFileToVM $ipv4 $sshKey $filename "/root/${$filename}"
# check the return Value of SendFileToVM
if (-not $retVal) {
    return $false
}

# execute command
$retVal = SendCommandToVM $ipv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"

# extracting the log files
bin\pscp -q -i ssh\${sshKey} root@${ipv4}:summary.log $logdir
Rename-Item $logdir\summary.log "${vmname}_Vxlan_Hang.log"

# Checking results to see if we can go further
$check = CheckResults $sshKey $vm2ipv4
if (-not $check[-1]) {
    "Error: rsync failed on VM1" | Tee-Object -Append -file $summaryLog
    return $false
}

Start-Sleep -S 450
$timeout=200
do {
    sleep 5
    $timeout -= 5
    if ($timeout -eq 0) {
        Write-Output "Error: Connection lost to the first VM. Test Failed." | Tee-Object -Append -file $summaryLog
        Stop-VM -Name $vmName -ComputerName $hvServer -Force
        Stop-VM -Name $vm2Name -ComputerName $hvServer -Force
        return $False
    }
} until(Test-NetConnection $ipv4 -Port 22 -WarningAction SilentlyContinue | ? { $_.TcpTestSucceeded } )

# If we are here then we still have a connection to VM.
# create command to be sent second VM. Verify if we can ping the first VM and if the test directory was transfered.

$cmdToVM = @"
#!/bin/bash
    ping -I vxlan0 242.0.0.12 -c 3
    if [ `$? -ne 0 ]; then
        echo "Could not ping the first VM through the vxlan interface. Lost connectivity between instances after rsync." >> summary.log
        echo "TestFailed" >> state.txt
        exit 1
    else
        echo "Ping to first vm succeded, that means the connection is good. Checking if the directory was transfered corectly." >> summary.log
        if [ -d "/root/test" ]; then
            echo "Test directory was found." >> summary.log
            size=``du -h /root/test | awk '{print `$1;}'``
            if [ `$size == "10G" ] || [ `$size == "11G" ]; then
                echo "Test directory has the proper size. Test ended successfuly." >> summary.log
                echo "TestCompleted" >> state.txt
            else
                echo "Test directory doesn't have the proper size. Test failed." >> summary.log
                echo "TestFailed" >> state.txt
                exit 2
            fi
        else
            echo "Test directory was not found." >> summary.log
            echo "TestFailed" >> state.txt
            exit 3
        fi
    fi
"@

$filename = "results_vxlan.sh"

# check for file
if (Test-Path ".\${filename}") {
    Remove-Item ".\${filename}"
}

Add-Content $filename "$cmdToVM"

# send file
$retVal = SendFileToVM $vm2ipv4 $sshKey $filename "/root/${$filename}"

# execute command
$retVal = SendCommandToVM $vm2ipv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename} $STATIC_IP"

bin\pscp -q -i ssh\${sshKey} root@${vm2ipv4}:summary.log $logdir
Rename-Item $logdir\summary.log "${vm2Name}_Vxlan_Hang.log"

$second_result = CheckResults $sshKey $vm2ipv4
Stop-VM -Name $vm2Name -ComputerName $hvServer -Force

if (-not $second_result[-1]) {
    "Error: rsync failed on VM2" | Tee-Object -Append -file $summaryLog
    return $false
}

Write-Output "Test passed. Connection is good, file was transfered" | Tee-Object -Append -file $summaryLog
return $second_result
