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
 Run the NET_SendIPtoVM test.

 Description:
    This script sends the IP of a test interface from the dependency VM to the test VM. It can be used as a pretest in case
    the main test consists of a remote-script which needs external information of the other VM.

    It can be used with the main Linux distributions. For the time being it is customized for use with the Networking tests.

    The following testParams are mandatory:

        VM2NAME=name_of_second_VM
            this is the name of the second VM. It will not be managed by the LIS framework, but by this script.

    The following testParams are optional:

        MAC=001600112233
            The static MAC address of the test NIC of the dependency VM.

        sshKey=sshKey.ppk
            The private key which will be used to allow sending information to the VM.

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

#
#Helper function to execute command on remote machine.
#
function Execute ([string] $command)
{
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} $command
    return $?
}
    
#
# Check input arguments
#
if ($vmName -eq $null)
{
    "Error: VM name is null"
    return $False
}

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

# Name of second VM
$vm2Name = $null

# In case the dependency VM is on another server than the test VM
$vm2Server = $null

#IP assigned to test interfaces

$tempipv4VM2 = $null
$testipv4VM2 = $null
$testipv6VM2 = $null

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

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")

    switch ($fields[0].Trim())
    {
    "VM2NAME" { $vm2Name = $fields[1].Trim() }
    "sshKey"  { $sshKey  = $fields[1].Trim() }
    "ipv4"    { $ipv4    = $fields[1].Trim() }
    "MAC"     { $vm2MacAddress = $fields[1].Trim() }
    "VM2SERVER"    { $vm2Server    = $fields[1].Trim() }
    "ENABLE_VMMQ"   { $EnableVmmq    = $fields[1].Trim()}
    default   {}  # unknown param - just ignore it
    }
}

if ($EnableVmmq -like "yes")
{
    write-output "Info: Activating VMMQ for $vm2Name"
    Set-VMNetworkAdapter -VMName $vm2Name -ComputerName $vm2Server -VmmqEnabled $True
    if (-not $?)
    {
        "Error: Unable to activate VMMQ for ${vm2Name}"
        $error[0].Exception
        return $False
    }

    Write-Output "Info: Activating VMMQ for $VMNAME"
    Set-VMNetworkAdapter -VMName $VMNAME -ComputerName $hvserver -VmmqEnabled $True
    if (-not $?)
    {
        "Error: Unable to activate VMMQ for ${vm2Name}"
        $error[0].Exception
        return $False
    }
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

if (-not $vm2MacAddress)
{
    "Error: test parameter MAC was not specified"
    return $False
}

if (-not $vm2Server)
{
    $vm2Server = $hvServer
    "vm2Server was set as $hvServer"
}

$checkState = Get-VM -Name $vm2Name -ComputerName $vm2Server

if ($checkState.State -notlike "Running")
{
    "Warning: ${vm2Name} is not running, we'll try to start it"
    Start-VM -Name $vm2Name -ComputerName $vm2Server
    if (-not $?)
    {
        "Error: Unable to start VM ${vm2Name}"
        $error[0].Exception
        return $False
    }
    $timeout = 240 # seconds
    if (-not (WaitForVMToStartKVP $vm2Name $vm2Server $timeout))
    {
        "Warning: $vm2Name never started KVP"
    }

   sleep 30

    $vm2ipv4 = GetIPv4 $vm2Name $vm2Server

    $timeout = 200 #seconds
    if (-not (WaitForVMToStartSSH $vm2ipv4 $timeout))
    {
        "Error: VM ${vm2Name} never started"
        Stop-VM $vm2Name -ComputerName $vm2Server -force | out-null
        return $False
    }

    "Succesfully started VM ${vm2Name}"
}

$ipv4 = GetIPv4 $vmName $hvServer

if (-not $ipv4) {
    "Error: could not retrieve test VM's test IP address"
    return $False
}

sleep 60

$tempipv4VM2 = Get-VMNetworkAdapter -VMName $vm2Name -ComputerName $vm2Server | Where-object {$_.MacAddress -like "$vm2MacAddress"} | Select -Expand IPAddresses
$testipv4VM2 = $tempipv4VM2[0]
$testipv6VM2 = $tempipv4VM2[1]

if (-not $testipv4VM2) {
    "Error: could not retrieve dependency VM's test IP address"
    return $False
}

$cmd="echo `"STATIC_IP2=$($testipv4VM2)`" >> ~/constants.sh";
$result = Execute($cmd);

if (-not $result) {
    Write-Error -Message "Error: Unable to submit ${cmd} to vm" -ErrorAction SilentlyContinue
    return $False
}

if ($testipv6VM2)
{
    $cmd="echo `"STATIC_IP2_V6=$($testipv6VM2)`" >> ~/constants.sh";
    $result = Execute($cmd);

    if (-not $result) {
        Write-Error -Message "Error: Unable to submit ${cmd} to vm" -ErrorAction SilentlyContinue
    }
}
else
{
    "Warning: could not retrieve dependency VM's test IPv6 address"
}

"Dependency VM's test IP submitted successfully!"
return $true
