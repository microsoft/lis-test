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
 Description:
    This script sends the IP constants of a test the dependency VM to the test VM. It can be used as a pretest in case
    the main test consists of a remote-script.
    It can be used with the main Linux distributions. For the time being it is customized for use with the Networking tests.
    The following testParams are mandatory:
        sshKey=sshKey.ppk
            The private key which will be used to allow sending information to the VM.
    The following testParams are optional:
        AddressFamily=IPv6 or IPv4
            the type of IPs used in the test. Default value is IPv4
        IPv4=the IPv4 of the VM
    All test scripts must return a boolean ($true or $false)
    to indicate if the script completed successfully or not.
   .Parameter vmName
    Name of the first VM implicated in the test .
    .Parameter hvServer
    Name of the Hyper-V server hosting the VM.
    .Parameter testParams
    Test data for this test case
    .Example
        InjectIPconstants.ps1 -vmName myVM -hvServer localhost -testParams "AddressFamily=IPv6"

#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

# sshKey used to authenticate ssh connection and send commands
$sshKey = $null

# IP Address of first VM
$ipv4 = $null

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

# Source NET_UTILS.ps1 for CIDRtoNetmask and other functions
if (Test-Path ".\setupScripts\NET_UTILS.ps1")
{
    . .\setupScripts\NET_UTILS.ps1
}
else
{
    "Error: Could not find setupScripts\NET_UTILS.ps1"
    return $false
}


$nic = $False
$switchs = $False
$AddressFamily = "IPv4"

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")

    switch ($fields[0].Trim())
    {
    "sshKey"        { $sshKey  = $fields[1].Trim() }
    "ipv4"          { $ipv4    = $fields[1].Trim() }
    "AddressFamily" { $AddressFamily    = $fields[1].Trim() }
    "SWITCH"        { $switchs = $fields[1].Trim() }
    "NIC"           { $nic     = $fields[1].Trim() }
    default         {}  # unknown param - just ignore it
    }
}

if (-not $sshKey)
{
    "Error: test parameter sshKey was not specified"
    return $False
}

$ipv4 = GetIPv4 $vmName $hvServer

if (-not $ipv4) {
    "Error: could not retrieve test VM's test IP address"
    return $False
}

if (-not $AddressFamily) {
    "Error: AddressFamily variable not defined"
    return $False
}

if($nic){
    $testType = $nic.split(',')[1]
}

if($switchs){
    $testType = $switchs.split(',')[1]
}

if($AddressFamily -eq "IPv4"){
    $externalIP = "8.8.4.4"
    $privateIP = "10.10.10.5"
}else{
    $externalIP = "2001:4860:4860::8888"
    $privateIP = "fd00::4:10"
}

$interfaces = (Get-NetIPAddress -AddressFamily $AddressFamily)
foreach($interface in $interfaces){
    if($interface.InterfaceAlias -like "*(Internal)*"){
        break
    }
}
$internalIP = $interface.IPAddress.split("%")[0]

$cmd=""
switch ($testType)
    {
    "Internal"  {   $PING_SUCC=$internalIP
                    $PING_FAIL=$externalIP
                    $PING_FAIL2=$privateIP
                    $STATIC_IP= GenerateIpv4 $PING_SUCC
                    $NETMASK = CIDRtoNetmask $interface.PrefixLength

                }
    "External"  {   $PING_SUCC=$externalIP
                    $PING_FAIL=$internalIP
                    $PING_FAIL2=$privateIP
                }
    "Private"   {   $PING_SUCC=$privateIP
                    $PING_FAIL=$externalIP
                    $PING_FAIL2=$internalIP

                    if($AddressFamily -eq "IPv4"){
                        $STATIC_IP= GenerateIpv4 $PING_SUCC
                        $STATIC_IP2= GenerateIpv4 $PING_SUCC $STATIC_IP
                        $NETMASK="255.255.255.0"
                    }else{
                        $STATIC_IP="fd00::4:10"
                        $STATIC_IP2="fd00::4:100"
                        $NETMASK=64
                    }

                }
    {($_ -eq "Internal") -or ($_ -eq "Private")}
                {
                    $cmd+="echo `"STATIC_IP=$($STATIC_IP)`" >> ~/constants.sh;";
                    $cmd+="echo `"STATIC_IP2=$($STATIC_IP2)`" >> ~/constants.sh;";
                    $cmd+="echo `"NETMASK=$($NETMASK)`" >> ~/constants.sh;";
                }
    default         {}  # unknown param - just ignore it
    }

$cmd+="echo `"PING_SUCC=$($PING_SUCC)`" >> ~/constants.sh;";
$cmd+="echo `"PING_FAIL=$($PING_FAIL)`" >> ~/constants.sh;";
$cmd+="echo `"PING_FAIL2=$($PING_FAIL2)`" >> ~/constants.sh;";

"PING_SUCC=$PING_SUCC"
"PING_FAIL=$PING_FAIL"
"PING_FAIL2=$PING_FAIL2"

if( $testType -eq "Internal"){
    "STATIC_IP=$STATIC_IP"
    "NETMASK=$NETMASK"
}

if( $testType -eq "Private"){
    "STATIC_IP=$STATIC_IP"
    "STATIC_IP2=$STATIC_IP2"
    "NETMASK=$NETMASK"
}

$result = Execute($cmd);

if (-not $result) {
    Write-Error -Message "Error: Unable to submit ${cmd} to vm" -ErrorAction SilentlyContinue
    return $False
}

"Test IP parameters successfully added to constants file"

return $true
