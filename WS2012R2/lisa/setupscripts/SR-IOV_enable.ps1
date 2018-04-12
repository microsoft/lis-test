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
    Enable SR-IOV on VM

.Description
    This is a setupscript that enables SR-IOV on VM
    Steps:
    1. Add new NICs to VMs
    2. Configure/enable SR-IOV on VMs settings via cmdlet Set-VMNetworkAdapter
    3. Set up SR-IOV on VM2 
    Optional: Set up an internal network on VM2
    
.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

.Example
    <test>
        <testName>VerifyVF_basic</testName>
        <testScript>SR-IOV_VerifyVF_basic.sh</testScript>
        <files>remote-scripts\ica\SR-IOV_VerifyVF_basic.sh,remote-scripts/ica/utils.sh</files> 
        <setupScript>
            <file>setupscripts\RevertSnapshot.ps1</file>
            <file>setupscripts\SR-IOV_enable.ps1</file>
        </setupScript> 
        <noReboot>False</noReboot>
        <testParams>
            <param>NIC_sriov_name=SRIOV</param>
            <param>TC_COVERED=??</param>
            <param>VF_IP1=10.11.12.31</param>
            <param>VF_IP2=10.11.12.32</param>
            <param>NETMASK=255.255.255.0</param>
            <param>REMOTE_USER=root</param>
            <param>Clean_Dependency=yes</param>
        </testParams>
        <timeout>600</timeout>
    </test>

#>

param ([String] $vmName, [String] $hvServer, [string] $testParams)
#
# Function which configures VF on VM2 and assigns a static IP to it
#
function ConfigureVFSecondVM([String]$conIpv4,[String]$sshKey,[String]$netmask)
{
    # create command to be sent to VM. This determines the interface based on the MAC Address.
    $cmdToVM = @"
#!/bin/bash
        cd ~
        # Source utils.sh
        dos2unix utils.sh
        dos2unix SR-IOV_Utils.sh

        # Source SR-IOV_Utils.sh
        . SR-IOV_Utils.sh || {
            echo "ERROR: unable to source SR-IOV_Utils.sh!" >> SRIOV_SendFile.log
            exit 2
        }

        # Install dependencies needed for testing
        InstallDependencies

        # Get the number of VFs on the VM
        vfCount=`$(find /sys/devices -name net -a -ipath '*vmbus*' | grep pci | wc -l)

        __iterator=1
        __ipIterator=2
        # Set static IPs for each VF
        while [ `$__iterator -le `$vfCount ]; do
            # Extract vfIP value from constants.sh
            staticIP=`$(cat constants.sh | grep IP`$__ipIterator | tr = " " | awk '{print `$2}')

            if is_ubuntu ; then
                __file_path="/etc/network/interfaces"

                # Add VF to /etc/network/interfaces 
                echo "auto eth`$__iterator" >> `$__file_path
                echo "iface eth`$__iterator inet static" >> `$__file_path
                echo "address `$staticIP" >> `$__file_path
                echo "netmask $netmask" >> `$__file_path

                ifup eth`$__iterator

            elif is_suse ; then
                __file_path="/etc/sysconfig/network/ifcfg-eth`$__iterator"
                rm -f `$__file_path
                # Create ifcfg file for the VF

                echo "DEVICE=eth`$__iterator" >> `$__file_path
                echo "NAME=eth`$__iterator" >> `$__file_path
                echo "BOOTPROTO=static" >> `$__file_path
                echo "IPADDR=`$staticIP" >> `$__file_path
                echo "NETMASK=$netmask" >> `$__file_path
                echo "STARTMODE=auto" >> `$__file_path

                ifup eth`$__iterator

            elif is_fedora ; then
                __file_path="/etc/sysconfig/network-scripts/ifcfg-eth`$__iterator"
                rm -f `$__file_path
                # Create ifcfg file for the VF

                echo "DEVICE=eth`$__iterator" >> `$__file_path
                echo "NAME=eth`$__iterator" >> `$__file_path
                echo "BOOTPROTO=static" >> `$__file_path
                echo "IPADDR=`$staticIP" >> `$__file_path
                echo "NETMASK=$netmask" >> `$__file_path
                echo "ONBOOT=yes" >> `$__file_path

                ifup eth`$__iterator

            fi

            __ipIterator=`$((`$__ipIterator + 2))
            : `$((__iterator++))
        done

        # Must fix retVal handler to return proper exit codes
        echo ConfigureVF: returned `$__retVal >> /root/SR-IOV_enable.log 2>&1
        exit `$__retVal
"@

    $filename = "ConfigureVF.sh"
    # check for file
    if (Test-Path ".\${filename}") {
        Remove-Item ".\${filename}"
    }

    Add-Content $filename "$cmdToVM"

    # send file
    $retVal = SendFileToVM $conIpv4 $sshKey $filename "/root/${$filename}"

    # delete file unless the Leave_trail param was set to yes.
    if ([string]::Compare($leaveTrail, "yes", $true) -ne 0) {
        Remove-Item ".\${filename}"
    }

    # check the return Value of SendFileToVM
    if (-not $retVal) {
        return $false
    }

    # execute sent file
    $retVal = SendCommandToVM $conIpv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"
    return $retVal
}

#############################################################
#
# Main script body
#
#############################################################
$retVal = $False
$maxNICs = "no"
$networkName = $null
$remoteServer = $null
$nicIterator = 0
$vm_vfIP = @()
$vfIterator = 0
$nicValues = @()
$leaveTrail = "no"

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

$params = $testParams.Split(';')
foreach ($p in $params)
{
    $fields = $p.Split("=")

    switch ($fields[0].Trim())
    {
    "VM2NAME" { $vm2Name = $fields[1].Trim() }
    "SshKey"  { $sshKey  = $fields[1].Trim() }
    "ipv4"    { $ipv4    = $fields[1].Trim() }
    "VF_IP1" { 
        $vm_vfIP1 = $fields[1].Trim()
        $vm_vfIP += ($vm_vfIP1)
        $vfIterator++ }
    "VF_IP2" { 
        $vm_vfIP2 = $fields[1].Trim()
        $vm_vfIP += ($vm_vfIP2)
        $vfIterator++ }
    "VF_IP3" { 
        $vm_vfIP3 = $fields[1].Trim()
        $vm_vfIP += ($vm_vfIP3)
        $vfIterator++ }
    "VF_IP4" { 
        $vm_vfIP4 = $fields[1].Trim()
        $vm_vfIP += ($vm_vfIP4)
        $vfIterator++ }
    "MAX_NICS" { $maxNICs = $fields[1].Trim() }
    "Test_IPv6" { $Test_IPv6 = $fields[1].Trim() }
    "NETMASK" { $netmask = $fields[1].Trim() }
    "LEAVE_TRAIL" { $leaveTrail = $fields[1].Trim() }
    "SnapshotName" { $SnapshotName = $fields[1].Trim() }
    "REMOTE_SERVER" { $remoteServer = $fields[1].Trim()}
    "Switch_Name"{ $vSwitchName = $fields[1].Trim()}
    "Clean_Dependency"{ $cleanDependency = $fields[1].Trim()}
    "NIC"
    {
        $temp = $p.Trim().Split('=')
        if ($temp[0].Trim() -eq "NIC")
        {
            $nicArgs = $temp[1].Split(',')
            if ($nicArgs.Length -lt 4)
            {
                "Error: Incorrect number of arguments for NIC test parameter: $p"
                return $false
            }

            $nicType = $nicArgs[0].Trim()
            $networkType = $nicArgs[1].Trim()
            $networkName = $nicArgs[2].Trim()
            $macAddress = $nicArgs[3].Trim()
            $legacy = $false
            # Store NIC values for later use
            $nicValues += ($nicType,$networkType,$networkName,$macAddress,$legacy)
            # Increment nicIterator for every NIC declared
            $nicIterator++

            # Validate the network adapter type
            if (@("NetworkAdapter", "LegacyNetworkAdapter") -notcontains $nicType)
            {
                "Error: Invalid NIC type: $nicType"
                "       Must be either 'NetworkAdapter' or 'LegacyNetworkAdapter'"
                return $false
            }

            if ($nicType -eq "LegacyNetworkAdapter")
            {
                $legacy = $true
            }

            # Validate the Network type
            if (@("External", "Internal", "Private") -notcontains $networkType)
            {
                "Error: Invalid netowrk type: $networkType"
                "       Network type must be either: External, Internal, Private, None"
                return $false
            }

            # Make sure the network exists
            if ($networkType -notlike "None")
            {
                $vmSwitch = Get-VMSwitch -Name $networkName -ComputerName $hvServer
                if (-not $vmSwitch)
                {
                    "Error: Invalid network name: $networkName"
                    "       The network does not exist"
                    return $false
                }
                
                # make sure network is of stated type
                if ($vmSwitch.SwitchType -notlike $networkType)
                {
                    "Error: Switch $networkName is type $vmSwitch.SwitchType (not $networkType)"
                    return $false
                }
            }

            # Validate the MAC is the correct length
            if ($macAddress.Length -ne 12)
            {
               "Error: Invalid mac address: $p"
                 return $false
            }

            # Make sure each character is a hex digit
            $ca = $macAddress.ToCharArray()
            foreach ($c in $ca)
            {
                if ($c -notmatch "[A-Fa-f0-9]")
                {
                    "Error: MAC address contains non hexidecimal characters: $c"
                   return $false
                }
            }
        }
    }
    default   {}  # unknown param - just ignore it
    }
}

if ($maxNICs -eq "yes") {
    $nicIterator = 7
    $vfIterator = 14
    $networkName = $vSwitchName
}

if (-not $vm2Name) {
    "ERROR: test parameter vm2Name was not specified"
    return $False
}

# Make sure vm2 is not the same as vm1
if ("$vm2Name" -like "$vmName") {
    "ERROR: vm2 must be different from the test VM."
    return $false
}

if (-not $networkName) {
    "ERROR: test parameter NIC_sriov_name was not specified"
    return $False
}

# Check if VM2 is on another host
# If VM2 is on the same host, $remoteServer will be same as $hvServer
if (-not $remoteServer) {
    $remoteServer = $hvServer
}

#
# Attach SR-IOV to both VMs and start VM2
#
# Verify VM2 exists
$vm2 = Get-VM -Name $vm2Name -ComputerName $remoteServer -ERRORAction SilentlyContinue
if (-not $vm2) {
    "ERROR: VM ${vm2Name} does not exist"
    return $False
}

# Verify if VM2 is already configured
$vm2_is_configured = $false
if (Get-VM -Name $vm2Name -ComputerName $remoteServer |  Where { $_.State -like "Running" })
{
    # Get ipv4 of VM2
    $vm2ipv4 = GetIPv4 $vm2Name $remoteServer
    "${vm2Name} IPADDRESS: ${vm2ipv4}"

    # Verify if SR-IOV is enabled and configured on VM2
    $retval = .\bin\plink.exe -i ssh\$sshKey root@${vm2ipv4} "ifconfig | grep $vm_vfIP2"
    if ($retVal) {
        $vm2_is_configured = $true
    }

    if ($vm_vfIP4 -ne $null) {
        $retval = .\bin\plink.exe -i ssh\$sshKey root@${vm2ipv4} "ifconfig | grep $vm_vfIP4"
        if ($retVal) {
            $vm2_is_configured = $true
        }
        else {
            $vm2_is_configured = $false
        }
    }
}

# There are some tests that require a clean dependency VM
if ($cleanDependency -ne $null) {
    if ($cleanDependency -eq 'yes'){
        $vm2_is_configured = $false
    }
}

if ($vm2_is_configured -eq $false) {
    if (Get-VM -Name $vm2Name -ComputerName $remoteServer |  Where { $_.State -like "Running" }) {
        Stop-VM $vm2Name -ComputerName $remoteServer -TurnOff -Force
        if (-not $?) {
            "ERROR: Failed to shutdown $vm2Name (in order to add a new network Adapter)"
            return $false
        }

        # wait for VM to finish shutting down
        $timeout = 60
        while (Get-VM -Name $vm2Name -ComputerName $remoteServer|  Where { $_.State -notlike "Off" }) {
            if ($timeout -le 0) {
                "ERROR: Failed to shutdown $vm2Name"
                return $false
            }

            start-sleep -s 5
            $timeout = $timeout - 5
        }
    }

    # Revert VM2
    $snapshotParam = "SnapshotName = ${SnapshotName}"
    .\setupScripts\RevertSnapshot.ps1 -vmName $vm2Name -hvServer $remoteServer -testParams $snapshotParam
    Start-sleep -s 5
}

# Add NICs to both VMs
for ($i=0; $i -lt $nicIterator; $i++){
    # Add Nic with given MAC Address
    # $nicValues[$i*5+2] means $networkName
    # $nicValues[$i*5+3] means $macAddress
    # $nicValues[$i*5+4] means $legacy

    # Changing MAC on VM1 to avoid conflicts
    if ($maxNICs -ne "yes" ) {
        $macAddress = $nicValues[$i*5+3]
        $macSubstring=[convert]::ToInt32($macAddress.Substring(9))
        $macSubstring = $macSubstring + 10
        $macAddress = $macAddress -replace $macAddress.Substring(9), "$macSubstring"
        
        Add-VMNetworkAdapter -VMName $vmName -SwitchName $nicValues[$i*5+2] -StaticMacAddress $macAddress `
        -IsLegacy:$nicValues[$i*5+4] -ComputerName $hvServer
        if ($? -ne "True") {
            "Error: Add-VmNic to $vmName failed"
            $retVal = $False
        }

        if ($vm2_is_configured -eq $false) {
            Add-VMNetworkAdapter -VMName $vm2Name -SwitchName $nicValues[$i*5+2] -StaticMacAddress $nicValues[$i*5+3] `
            -IsLegacy:$nicValues[$i*5+4] -ComputerName $remoteServer 
            if ($? -ne "True") {
                "Error: Add-VmNic to $vm2Name failed"
                $retVal = $False
            }
        $retVal = $True
        }
    }
    else {
        Add-VMNetworkAdapter -VMName $vmName -SwitchName $vSwitchName -IsLegacy:$false -ComputerName $hvServer
        if ($? -ne "True") {
            "Error: Add-VmNic to $vmName failed"
            $retVal = $False
        }

        Add-VMNetworkAdapter -VMName $vm2Name -SwitchName $vSwitchName -IsLegacy:$false -ComputerName $remoteServer 
        if ($? -ne "True") {
            "Error: Add-VmNic to $vm2Name failed"
            $retVal = $False
        }
        $retVal = $True
    }
}

# Enable SR-IOV
Set-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer -IovWeight 1
if ($? -eq "True") {
    $retVal = $True
}
else {
    "ERROR: Failed to enable SR-IOV on $vmName!"
}

if ($vm2_is_configured -eq $false) {
    Set-VMNetworkAdapter -VMName $vm2Name -ComputerName $remoteServer -IovWeight 1
    if ($? -eq "True") {
        $retVal = $True
    }
    else {
        "ERROR: Failed to enable SR-IOV on $vm2Name!"
    }

    # Start VM2
    if (Get-VM -Name $vm2Name -ComputerName $remoteServer |  Where { $_.State -notlike "Running" }) {
        Start-VM -Name $vm2Name -ComputerName $remoteServer
        if (-not $?) {
            "ERROR: Failed to start VM ${vm2Name}"
            $ERROR[0].Exception
            return $False
        }
    }

    $timeout = 200 # seconds
    if (-not (WaitForVMToStartKVP $vm2Name $remoteServer $timeout)) {
        "Warning: $vm2Name never started KVP"
    }

    #
    # Set up VF on VM2
    #
    # Get IP from VM2
    $vm2ipv4 = GetIPv4 $vm2Name $remoteServer
    "$vm2Name IPADDRESS: $vm2ipv4"

    # wait for ssh to start
    $timeout = 200 #seconds
    if (-not (WaitForVMToStartSSH $vm2ipv4 $timeout)) {
        "ERROR: VM ${vm2Name} never started"
        Stop-VM $vm2Name -ComputerName $remoteServer -TurnOff -Force | out-null
        return $False
    }

    # send utils.sh to VM2
    if (-not (Test-Path ".\remote-scripts\ica\utils.sh")) {
        "ERROR: Failed to find remote-scripts\ica\utils.sh "
        return $false
    }

    "Sending .\remote-scripts\ica\utils.sh to $vm2ipv4 , authenticating with $sshKey"
    $retVal = SendFileToVM "$vm2ipv4" "$sshKey" ".\remote-scripts\ica\utils.sh" "/root/utils.sh"

    if (-not $retVal) {
        "Failed sending utils.sh file to VM!"
        return $False
    }
    "Successfully sent utils.sh"

    "Sending .\remote-scripts\ica\SR-IOV_Utils.sh to $vm2ipv4 , authenticating with $sshKey"
    $retVal = SendFileToVM "$vm2ipv4" "$sshKey" ".\remote-scripts\ica\SR-IOV_Utils.sh" "/root/SR-IOV_Utils.sh"

    if (-not $retVal) {
        "Failed sending SR-IOV_Utils.sh file to VM!"
        return $False
    }
    "Successfully sent SR-IOV_Utils.sh"

    if ($maxNICs -eq "yes") {
        $nicIterator = 1
    }

    # Create constants.sh file on vm2
    for ($i=0; $i -lt $vfIterator; $i++){
        # get ip from array
        $j = $i + 1
        if ($maxNICs -eq "yes") {
            $ipToSend = "10.1${nicIterator}.12.${j}"
            if ($j % 2 -eq 0) {
                $nicIterator++
            }
        }
        else {
            $ipToSend = $vm_vfIP[$i]
        }
        # construct command to be sent on vm2
        $commandToSend = "echo -e VF_IP$j=$ipToSend >> constants.sh"

        $retVal = SendCommandToVM "$vm2ipv4" "$sshKey" $commandToSend
        if (-not $retVal) {
            "Failed appending $ipToSend to constants.sh"
            return $False
        }
        "Successfully appended $ipToSend to constants.sh"   
    }

    if ($maxNICs -eq "yes") {
        $nicIterator = 0
    }

    "Configuring VF on $vm2Name (${vm2ipv4}) "
    $retVal = ConfigureVFSecondVM $vm2ipv4 $sshKey $netmask
    if (-not $retVal) {
        "Error: Failed to configure vf on vm $vm2ipv4 for interface with mac $vm2MacAddress, by setting a static IP of $vm_vfIP2 netmask $netmask"
        return $false
    }
}

return $retVal
