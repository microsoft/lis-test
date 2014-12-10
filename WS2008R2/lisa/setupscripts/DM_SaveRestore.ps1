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
        Verif a VM that has had its Assigned Memory modified can
    be saved and restored.

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
# WaitToEnterVMState()
#
# Description:
#     Wait up to 2 minutes for a VM to enter a specific state
#
#######################################################################
function WaitToEnterVMState([String] $name, [String] $server, [String] $state)
{
    $isInState = $False

    $count = 12

    while ($count -gt 0)
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

        Start-Sleep -s 10
    }

    return $isInState
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

$ipv4 = $null
$sshKey = $null
$vm2Name = $null
$vm2ipv4 = $null

#
# Display the test params in the log
#
"Test params = $testParams"

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
    "Error: Test parameter vm2Name was not specified"
    return $False
}

if ($null -eq $sshKey)
{
    "Error: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4)
{
    "Error: Test parameter ipv4 was not specified"
    return $False
}

$vm1Name = $vmName

#
# Include some info in the logs"
#
"Info : vm1Name = ${vm1Name}"
"Info : vm2Name = ${vm2Name}"
"Info : ipv4    = ${ipv4}"
"Info : sshKey  = ${sshKey}"

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
# Collect VM1 stats before starting VM2
#
$vm1 = Get-VM -Name $vm1Name -ComputerName $hvServer 
$beforeMemory = $vm1.MemoryAssigned

#
# Let the DM system settle out
#
Start-Sleep -s 45

Start-VM -Name $vm2Name -ComputerName $hvServer 
if (-not (WaitForVMToStartKVP $vm2Name $hvServer 300))
{
    "Error: ${vm2Name} failed to start"
    return $False
}

$vm2ipv4 = GetIPv4ViaKVP $vm2Name $hvServer
if (-not $vm2ipv4)
{
    "Error: Unable to get ipv4 via KVP for VM ${vm2Name}"
    Stop-VM -Name $vm2Name -Force -TurnOff
    return $False
}

#
# Collect metrics for VM1 again now that VM2 is up and running
# and compute the difference in assigned memory
#
$vm1 = Get-VM -Name $vm1Name -ComputerName $hvServer 
$afterMemory = $vm1.MemoryAssigned
$startupMemory = $vm1.MemoryStartup

$memDelta = $afterMemory - $beforeMemory
"Info : Before memory : ${beforeMemory}"
"Info : After memory  : ${afterMemory}"
"Info : ${vm1Name} Assigned Memory change by ${memDelta} bytes"
"Info : Startup memory: ${startupMemory}"

#
# If the assignemd memory for VM1 was modified, try the actual
# a save and restore.
#
$results = "Failed"
$retVal = $False
if ($memDelta -ne 0 -or $afterMemory -lt $startupMemory)
{
    Save-Vm -Name $vm1Name -ComputerName $hvServer
    if (-not (WaitToEnterVMState $vm1Name $hvServer "SAVED"))
    {
        "Error: Unable to Save VM ${vm1Name}"
        return $False
    }

    Start-VM -Name $vm1Name -ComputerName $hvServer
    if (-not (WaitForVMToStartKVP $vm1Name $hvServer 300))
    {
        "Error: ${vm1Name} failed to resume"
        return $False
    }

    $hn = .\bin\plink.exe -i .\ssh\$sshKey root@${ipv4} hostname
    if ($null -ne $hn)
    {
        $results = "Passed"
        $retVal = $True
    }
}
else
{
    "Error: Assigned Memory has not been modified"
}

#
# Stop vm2 since ICA does not know about it.
#
.\bin\plink.exe -i ssh\${sshKey} root@${vm2ipv4} "init 0"
if (-not $?)
{
    "Error: Unable to send 'init 0' to VM ${vm2Name}"
    return $False
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
    $timeout -= 5
    Start-Sleep -s 5
}

if ($timeout -le 0)
{
    Stop-VM -Name $vm2Name -ComputerName $hvServer -TurnOff -Force
}

#
#
#
"Info : Test ${results}"

return $retVal

