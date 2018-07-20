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

<#
.Synopsis
 Run the StartVM test.

 Description:
    This script sets up additional Network Adapters for a second (dependency) VM,
    starts it first and configures the interface files in the OS.
    Afterwards the main test is started together with the main VM.

    For the time being it is customized for use with the Networking tests.

    The following testParams are mandatory:

        NIC=NIC type, Network Type, Network Name, MAC Address

            NIC Type can be one of the following:
                NetworkAdapter
                LegacyNetworkAdapter

            Network Type can be one of the following:
                External
                Internal
                Private

            Network Name is the name of a existing network.

            Only the Network Name parameter is used by this script, but the others are still necessary, in order to have the same
            parameters as the NET_ADD_NIC_MAC script.

            The following is an example of a testParam for removing a NIC

                "NIC=NetworkAdapter,Internal,InternalNet,001600112200"

        VM2NAME=name_of_second_VM
            this is the name of the second VM. It will not be managed by the LIS framework, but by this script.

    The following testParams are optional:

        STATIC_IP=xx.xx.xx.xx
            xx.xx.xx.xx is a valid IPv4 Address. If not specified, a default value of 10.10.10.1 will be used.
            This will be assigned to VM1's test NIC.

        STATIC_IP2=xx.xx.xx.xx
            xx.xx.xx.xx is a valid IPv4 Address. If not specified, an IP Address from the same subnet as VM1's STATIC_IP
            will be computed (usually the first address != STATIC_IP in the subnet).This will be assigned as VM2's test NIC.

        NETMASK=yy.yy.yy.yy
            yy.yy.yy.yy is a valid netmask (the subnet to which the tested netAdapters belong). If not specified, a default value of 255.255.255.0 will be used.

        LEAVE_TRAIL=yes/no
            if set to yes and the NET_ADD_NIC_MAC.ps1 script was called from within this script for VM2, then it will not be removed
            at the end of the script. Also temporary bash scripts generated during the test will not be deleted.

    All test scripts must return a boolean ($true or $false)
    to indicate if the script completed successfully or not.

   .Parameter vmName
    Name of the first VM implicated in the test .

    .Parameter hvServer
    Name of the Hyper-V server hosting the VM.

    .Parameter testParams
    Test data for this test case

    .Example
    StartVM -vmName myVM -hvServer localhost -testParams "NIC=NetworkAdapter,Private,Private,001600112200;VM2NAME=vm2Name"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

Set-PSDebug -Strict
#######################################################################
#
# Main script body
#
#######################################################################

# Check input arguments
if ($hvServer -eq $null)
{
    "Error: hvServer is null"
    return $False
}

if ($testParams -eq $null)
{
    "Error: testParams is null"
    return $False
}

# Write out test Params
$testParams

# sshKey used to authenticate ssh connection and send commands
$sshKey = $null

# IP Address of first VM
$ipv4 = $null

# IP Address of second VM
$ipv4VM2 = $null

# Name of second VM
$vm2Name = $null

# VM1 IPv4 Address
$vm1StaticIP = $null

# VM2 IPv4 Address
$vm2StaticIP = $null

# Netmask used by both VMs
$netmask = $null

# boolean to leave a trail
$leaveTrail = $null

# switch name
$networkName = $null

#Snapshot name
$snapshotParam = $null

#Test IPv6
$Test_IPv6 = $null

#Test IPv6
$vm2MacAddress = $null

#ifcfg bootproto
$bootproto = $null

# change working directory to root dir
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
        "Error: Could not change directory to $rootDir !"
        return $false
    }
    "Changed working directory to $rootDir"
}
else
{
    "Error: RootDir = $rootDir is not a valid path"
    return $false
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

# Source NET_UTILS.ps1 for network functions
if (Test-Path ".\setupScripts\NET_UTILS.ps1")
{
    . .\setupScripts\NET_UTILS.ps1
}
else
{
    "Error: Could not find setupScripts\NET_Utils.ps1"
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
    "STATIC_IP" { $vm1StaticIP = $fields[1].Trim() }
    "STATIC_IP2" { $vm2StaticIP = $fields[1].Trim() }
    "Test_IPv6" { $Test_IPv6 = $fields[1].Trim() }
    "NETMASK" { $netmask = $fields[1].Trim() }
    "MAC" { $vm2MacAddress = $fields[1].Trim() }
    "LEAVE_TRAIL" { $leaveTrail = $fields[1].Trim() }
    "SnapshotName" { $SnapshotName = $fields[1].Trim() }
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
        $legacy = $false

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
        #
        # Make sure the network exists
        #
        $vmSwitch = Get-VMSwitch -Name $networkName -ComputerName $hvServer
        if (-not $vmSwitch)
        {
            "Error: Invalid network name: $networkName . The network does not exist."
            return $false
        }

        if ($isDynamic -eq $true){
            $vm1MacAddress = $streamReader.ReadLine() 
        }
        else {
            $retVal = isValidMAC $vm1MacAddress

            if (-not $retVal)
            {
                "Invalid Mac Address $vm1MacAddress"
                return $false
            }  
        }

        #
        # Get Nic with given MAC Address
        #
        $vm1nic = Get-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer -IsLegacy:$false | where {$_.MacAddress -eq $vm1MacAddress }
        if ($vm1nic)
        {
            "$vmName found NIC with MAC $vm1MacAddress ."
        }
        else
        {
            "Error: $vmName - No NIC found with MAC $vm1MacAddress ."
            return $false
        }
    }
    default   {}  # unknown param - just ignore it
    }
}

if ($isDynamic -eq $true) 
{
    $streamReader.close()
}

if (-not $vm2Name)
{
    "Error: test parameter vm2Name was not specified"
    return $False
}

# make sure vm2 is not the same as vm1
if ("$vm2Name" -like "$vmName")
{
    "Error: vm2 must be different from the test VM."
    return $false
}

if (-not $sshKey)
{
    "Error: test parameter sshKey was not specified"
    return $False
}

if (-not $netmask)
{
    $netmask = 255.255.255.0
}

if (-not $vm2StaticIP)
{
    $bootproto = "dhcp"
}
else
{
    $bootproto = "static"
}

#set the parameter for the snapshot
$snapshotParam = "SnapshotName = ${SnapshotName}"

#revert VM2
.\setupScripts\RevertSnapshot.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $snapshotParam
Start-sleep -s 5

#
# Verify the VMs exists
#
$vm2 = Get-VM -Name $vm2Name -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm2)
{
    "Error: VM ${vm2Name} does not exist"
    return $False
}

# hold testParam data for NET_ADD_NIC_MAC script
$vm2testParam = $null

# remember if we added the NIC or it was already there.
$scriptAddedNIC = $false

# Check for a NIC of the given network type on VM2
$vm2nic = $null
$nic2 = Get-VMNetworkAdapter -VMName $vm2Name -ComputerName $hvServer -IsLegacy:$false | where { $_.SwitchName -like "$networkName" }

#Generate a Mac address for the VM's test nic, if this is not a specified parameter
if (-not $vm2MacAddress) {
    $vm2MacAddress = getRandUnusedMAC $hvServer

    $CurrentDir= "$pwd\"
    $testfile = "macAddressDependency.file" 
    $pathToFile="$CurrentDir"+"$testfile" 
    $streamWrite = [System.IO.StreamWriter] $pathToFile
    $streamWrite.WriteLine($vm2MacAddress)
    $streamWrite.close()
}

#construct NET_ADD_NIC_MAC Parameter
$vm2testParam = "NIC=NetworkAdapter,$networkType,$networkName,$vm2MacAddress"

if ( Test-Path ".\setupscripts\NET_ADD_NIC_MAC.ps1")
{
    # Make sure VM2 is shutdown
    if (Get-VM -Name $vm2Name -ComputerName $hvServer |  Where { $_.State -like "Running" })
    {
        Stop-VM $vm2Name -ComputerName $hvServer -Force
        if (-not $?)
        {
            "Error: Unable to shut $vm2Name down (in order to add a new network Adapter)"
            return $false
        }
    }

    .\setupscripts\NET_ADD_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
}
else
{
    "Error: Could not find setupScripts\NET_ADD_NIC_MAC.ps1 ."
    return $false
}

if (-Not $?)
{
    "Error: Cannot add new NIC to $vm2Name"
    return $false
}

# get the newly added NIC
$vm2nic = Get-VMNetworkAdapter -VMName $vm2Name -ComputerName $hvServer -IsLegacy:$false | where { $_.MacAddress -like "$vm2MacAddress" }

if (-not $vm2nic)
{
    "Error: Could not retrieve the newly added NIC to VM2"
    return $false
}

$scriptAddedNIC = $true

#
# Start VM2
#
if (Get-VM -Name $vm2Name -ComputerName $hvServer |  Where { $_.State -notlike "Running" })
{
    Start-VM -Name $vm2Name -ComputerName $hvServer
    if (-not $?)
    {
        "Error: Unable to start VM ${vm2Name}"
        $error[0].Exception
        return $False
    }
}


$new_ip = GetIPv4AndWaitForSSHStart $vm2Name $hvServer $sshKey 360
if ($new_ip) {$vm2ipv4 = $new_ip}
else {
    "Error: Failed to boot VM $vm2Name"
    return $false
}

# send utils.sh to VM2
if (-not (Test-Path ".\remote-scripts\ica\utils.sh"))
{
    "Error: Unable to find remote-scripts\ica\utils.sh "
    return $false
}

"Sending .\remote-scripts\ica\utils.sh to $vm2ipv4 , authenticating with $sshKey"
$retVal = SendFileToVM "$vm2ipv4" "$sshKey" ".\remote-scripts\ica\utils.sh" "/root/utils.sh"

if (-not $retVal)
{
    "Failed sending file to VM!"
    return $False
}

"Successfully sent utils.sh"

"Configuring test interface (${vm2MacAddress}) on $vm2Name (${vm2ipv4}) "
$retVal = CreateInterfaceConfig $vm2ipv4 $sshKey $bootproto $vm2MacAddress $vm2StaticIP $netmask
if (-not $retVal)
{
    "Failed to create Interface on vm $vm2ipv4 for interface with mac $vm2MacAddress, by setting a static IP of $vm2StaticIP netmask $netmask"
    return $false
}

#get the ipv4 of the test adapter allocated by DHCP
"vm2 Name = ${vm2Name}"
"vm2 ipv4 = ${vm2ipv4}"
"vm2 MAC = ${vm2MacAddress}"

return $true
