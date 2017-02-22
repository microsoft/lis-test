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

# In case the dependency VM is on another server than the test VM
$vm2Server = $null

#IP assigned to test interfaces

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
    "sshKey"  { $sshKey  = $fields[1].Trim() }
    "ipv4"    { $ipv4    = $fields[1].Trim() }
    "VM2SERVER"    { $vm2Server    = $fields[1].Trim() }
    "SLAVE_HOSTNAMES"    { $slave_hostnames    = $fields[1].Trim() }
    default   {}  # unknown param - just ignore it
    }
}


if (-not $sshKey)
{
    "Error: test parameter sshKey was not specified"
    return $False
}

if (-not $vm2Server)
{
    $vm2Server = $hvServer
    "vm2Server was set as $hvServer"
}

$ipv4 = GetIPv4 $vmName $hvServer

if (-not $ipv4) {
    "Error: could not retrieve test VM's test IP address"
    return $False
}

sleep 60

$slave_hostnames=$slave_hostnames.Trim("(", ")")
$slave_hostnames=$slave_hostnames.Split(" ")
foreach ($slave in $slave_hostnames)
{
    $auxip = GetIPv4 $slave $vm2Server
    if (-not $auxip) {
        "Error: could not retrieve test VM's test IP address"
        return $False
    }
    # Send IPv4 for each slave in constants
    $cmd="echo `"$($slave)=$($auxip)`" >> ~/constants.sh";
    $result = Execute($cmd);
    if (-not $result) {
        Write-Error -Message "Error: Unable to submit ${cmd} to vm" -ErrorAction SilentlyContinue
        return $False
    }

    # Set hostname for each slave
    echo y | .\bin\plink.exe -i .\ssh\rhel5_id_rsa.ppk root@$($auxip) hostnamectl set-hostname $($slave)
}

return $true