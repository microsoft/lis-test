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
    

.Description
        This is a PowerShell test case script that runs on the on
    the ICA host rather than the VM.

    Verif a VM that has had its Assigned Memory modified by the
    dynamic memory can be shutdown cleanly.

    The ICA scripts will always pass the vmName, hvServer, and a
    string of testParams to the PowerShell test case script. For
    example, if the <testParams> section was written as:

        <testParams>
            <param>VM1Name=SuSE-DM-VM1</param>
            <param>VM2Name=SuSE-DM-VM2</param>
        </testParams>

    The string passed in the testParams variable to the PowerShell
    test case script script would be:

        "VM1Name=SuSE-DM-VM1;VM2Name=SuSE-DM-VM2"

    Thes PowerShell test case cripts need to parse the testParam
    string to find any parameters it needs.

    All setup and cleanup scripts must return a boolean ($True or $False)
    to indicate if the script completed successfully or not.

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)


#######################################################################
#
# WaitToEnterVMState()
#
# Description:
#     Wait up to 2 minutes for a VM to enter a specific state
#
#######################################################################
function WaitToEnterVMState([String] $name, [String] $server, [String] $state)
{
    $isInState = $False

    $timeout = 120

    while ($timeout -gt 0)
    {
        $vm = Get-VM -Name $name -ComputerName $server
        if (-not $vm)
        {
            return $False
        }

        if ($vm.State -eq $state)
        {
            $isInState = $True
            break
        }

        $timeout -= 10
        Start-Sleep -s 10
    }

    return $isInState
}


#######################################################################
#
# WaiForVMToStartKVP()
#
# Description:
#    Use KVP to get a VMs IP address.  Once the address is returned,
#    consider the VM up.
#
#######################################################################
function WaitForVMToStartKVP([String] $vmName, [String] $hvServer, [int] $timeout)
{
    $ipv4 = $null
    $retVal = $False

    $waitTimeOut = $timeout
    while ($waitTimeOut -gt 0)
    {
        $ipv4 = GetIPv4ViaKVP $vmName $hvServer
        if ($ipv4)
        {
            $retVal = $True
            break
        }

        $waitTimeOut -= 10
        Start-Sleep -s 10
    }

    return $retVal
}


#######################################################################
#
# GetIPv4ViaKVP()
#
# Description:
#
#
#######################################################################
function GetIPv4ViaKVP( [String] $vm, [String] $server)
{

    $vmObj = Get-WmiObject -Namespace root\virtualization -Query "Select * From Msvm_ComputerSystem Where ElementName=`'$vm`'" -ComputerName $server
    if (-not $vmObj)
    {
        return $null
    }

    $kvp = Get-WmiObject -Namespace root\virtualization -Query "Associators of {$vmObj} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent" -ComputerName $Server
    if (-not $kvp)
    {
        return $null
    }

    $rawData = $Kvp.GuestIntrinsicExchangeItems
    if (-not $rawData)
    {
        return $null
    }

    $name = $null
    $addresses = $null

    foreach ($dataItem in $rawData)
    {
        $found = 0
        $xmlData = [Xml] $dataItem
        foreach ($p in $xmlData.INSTANCE.PROPERTY)
        {
            if ($p.Name -eq "Name" -and $p.Value -eq "NetworkAddressIPv4")
            {
                $found += 1
            }

            if ($p.Name -eq "Data")
            {
                $addresses = $p.Value
                $found += 1
            }

            if ($found -eq 2)
            {
                $addrs = $addresses.Split(";")
                foreach ($addr in $addrs)
                {
                    if ($addr.StartsWith("127."))
                    {
                        Continue
                    }
                    return $addr
                }
            }
        }
    }

    return $null
}


#######################################################################
#
# WaiForVMToReportDemand()
#
# Description:
#    Try to connect to the SSH port (port 22) on the VM
#
#######################################################################
function WaitForVMToReportDemand([String] $name, [String] $server, [int] $timeout)
{
    $retVal = $False

    $waitTimeOut = $timeout
    while($waitTimeOut -gt 0)
    {
        $vm = Get-VM -Name $name -ComputerName $server
        if (-not $vm)
        {
            return $false
        }

        if ($vm.MemoryDemand -and $vm.MemoryDemand -gt 0)
        {
            return $True
        }

        $waitTimeOut -= 5  # Note - Test Port will sleep for 5 seconds
        Start-Sleep -s 5
    }

    return $retVal
}


#######################################################################
#
# Main script body
#
#######################################################################

$retVal = $false

#
# Check input arguments
#
if ($vmName -eq $null)
{
    "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null)
{
    "Error: hvServer is null"
    return $retVal
}

$vm2Name = $null
$sshKey  = $null
$ipv4    = $null

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    switch ($fields[0].Trim())
    {
    "vm2Name" { $vm2Name = $fields[1].Trim() }
    "sshKey"  { $sshKey  = $fields[1].Trim() }
    "ipv4"    { $ipv4    = $fields[1].Trim() }
	"rootdir" { $rootDir = $fields[1].Trim() }
    default  {}       
    }
}

if ($null -eq $vm2Name)
{
    "Error: Test parameter VM2 was not specified"
    return $retVal
}

$vm1Name = $vmName
"Info : vm1Name = ${vm1Name}"
"Info : vm2Name = ${vm2Name}"
"Info : sshKey  = ${sshKey}"
"Info : ipv4    = ${ipv4}"

#
# Change the working directory to where we need to be
#
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

cd $rootDir

#
# Verify both VMs exist
#
$vm1 = Get-VM -Name $vm1Name -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm1)
{
    "Error: VM ${vm1Name} does not exist"
    return $False
}

$vm2 = Get-VM -Name $vm2Name -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm2)
{
    "Error: VM ${vm2Name} does not exist"
    return $False
}

#
# Wait for hv_balloon to start reporting memory demand
#
if (-not (WaitForVMToReportDemand $vm1Name $hvServer 300))
{
    "Error: VM ${vm1Name} never reported memory demand"
    return $False
}

#
# Wait a bit longer for DM to settle out
#
Start-Sleep -s 15

#
# Collect VM1 stats before starting VM2
#
$vm1 = Get-VM -Name $vm1Name -ComputerName $hvServer 
$beforeMemory = $vm1.MemoryAssigned

#
# Start VM2 so it consumes memory
#
Start-VM -Name $vm2Name -ComputerName $hvServer 
$timeout = 180
if (-not (WaitForVMToStartKVP $vm2Name $hvServer $timeout))
{
    "Error: V< ${vm2Name} never reported memory demand"
    Stop-VM -Name $vm2Name -Force -Turnoff -ComputerName $hvServer
    return $False
}

$vm2ipv4 = GetIPv4ViaKVP $vm2Name $hvServer
if (-not $vm2ipv4)
{
    "Error: Unable to determine VM IPv4 address via KVP for ${vm2Name}"
    Stop-VM -Name $vm2Name -Force -Turnoff -ComputerName $hvServer
    return $False
}

#
# Collect metrics for VM1 again now that VM2 is up and running
# and compute the difference in assigned memory
#
$vm1 = Get-VM -Name $vm1Name -ComputerName $hvServer 
$afterMemory = $vm1.MemoryAssigned

$memDelta = $afterMemory - $beforeMemory
"Info : Before memory: {0,14}" -f $beforeMemory
"Info : After memory : {0,14}" -f $afterMemory
"Info : Delta memory : {0,14}" -f $memDelta

#
# now try the actual test - a clean shutdown.
#
$results = "Failed"
$retVal = $False

$sts = Stop-Vm -Name $vm1Name -Force -ComputerName $hvServer
if (-not (WaitToEnterVMState $vm1Name $hvServer "OFF"))
{
    "Error: Unable to cleanly shutdown VM ${vm1Name}"
}
else
{
    $results = "Passed"
    $retVal = $True
}

#
# Do some cleanup for ICA.  Stop vm2 since ICA does not know about it.
# Start vm1 to keep ICA from complaining about the VM being in the wrong state.
#
Start-VM -Name $vm1Name -ComputerName $hvServer

#
# Shutdown VM2 since ICA does not know about it.
#
.\bin\plink.exe -i ssh\${sshKey} root@${vm2ipv4} "init 0"
if (-not $?)
{
    "Error: Unable to init 0 ${vm2Name}"
    Stop-VM -Name $vm2Name -ComputerName $hvServer -TurnOff -Force
}

#
# Wait for vm2 to go to a stopped state
#
$timeout = 120
while ($timeout -gt 0)
{
    $vm = Get-VM -Name $vm2Name -ComputerName $hvServer
    if ($vm.State -eq "Off")
    {
        break;
    }
    $timeout -= 10
    Start-Sleep -s 10
}

if ($timeout -le 0)
{
    Stop-VM -Name $vm2Name -ComputerName $hvServer -TurnOff -Force
}

#
# Finish waiting for VM1 to reboot
#
WaitForVMToStartKVP $vm1Name $hvServer 300

"Info : Test ${results}"

return $retVal
