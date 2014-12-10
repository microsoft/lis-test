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

    Balloon_StartVM will check to see if the Hyper-V memory is moved
    from an existing to a starting VM when there are insufficient 
    memory resources.

    The ICA scripts will always pass the vmName, hvServer, and a
    string of testParams to the PowerShell test case script. For
    example, if the <testParams> section was written as:

        <testParams>
            <param>VM2=SuSE-DM-VM2</param>
        </testParams>

    The string passed in the testParams variable to the PowerShell
    test case script script would be:

        "HeartBeatTimeout=60;TestCaseTimeout=300"

    Thes PowerShell test case cripts need to parse the testParam
    string to find any parameters it needs.

    All setup and cleanup scripts must return a boolean ($true or $false)
    to indicate if the script completed successfully or not.

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)


#####################################################################
#
# TestPort
#
#####################################################################
function TestPort ([String] $serverName, [Int] $port=22, [Int] $to=3)
{
    $retVal = $False
    $timeout = $to * 1000

    #
    # Try an async connect to the specified machine/port
    #
    $tcpclient = new-Object system.Net.Sockets.TcpClient
    $iar = $tcpclient.BeginConnect($serverName,$port,$null,$null)

    #
    # Wait for the connect to complete. Also set a timeout
    # so we don't wait all day
    #
    $connected = $iar.AsyncWaitHandle.WaitOne($timeout,$false)

    # Check to see if the connection is done
    if($connected)
    {
        #
        # Close our connection
        #
        try
        {
            $sts = $tcpclient.EndConnect($iar) | out-Null.
        }
        catch
        {
            # Nothing we need to do...
        }

        $retVal = $true
    }

    $tcpclient.Close()

    return $retVal
}

#######################################################################
#
#
#
#######################################################################
function WaitForVMToStart([String] $vmName)
{
    Start-Sleep -s 10  # To Do - replace this with another check

    return $True
}


#######################################################################
#
#
#
#######################################################################
function VerifyVMConfig([Microsoft.HyperV.PowerShell.VirtualMachine] $vm, [Double] $percent, [Long] $minMemory)
{
    $hostInfo = Get-VMHost -ComputerName $hvServer
    $memPercent = $hostInfo.MemoryCapacity * $percent

    if (-not $vm.DynamicMemoryEnabled)
    {
        return $False
    }

    #if ($vm.MemoryStartup -lt $memPercent)
    #{
    #    return $False
    #}

    #if ($vm.MemoryMaximum -ne $vm.MemoryStartup)
    #{
    #    return $False
    #}

    #if ($vm.MemoryMinimum -ne $minMemory)
    #{
    #    return $False
    #}

    #
    # If we made it here, all the checks passed.
    #
    return $True
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

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    switch ($fields[0].Trim())
    {
    "vm2Name" { $vm2Name = $fields[1].Trim() }
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

#
# display variables in the log
#
"vm1Name = ${vm1Name}"
"vm2Name = ${vm2Name}"

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
"Info : Collecting information on ${vm1Name} and ${vm2Name}"

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
# Make sure the VMs have a reasonable config
#
if (-not (VerifyVMConfig $vm1 0.81 256MB))
{
    "Error: VM ${vm1Name} is not configured correctly"
    return $False
}

if (-not (VerifyVMConfig $vm2 0.28 512MB))
{
    "Error: VM ${vm2Name} is not configured correctly"
    return $False
}

#
# Collect VM1s memory metrics
#
"Info : Collecting metrics for ${vm1Name}"

$vm1 = Get-VM -Name $vm1Name -ComputerName $hvServer 
$beforeMemory = $vm1.MemoryAssigned

#
# Sleep a bit to let things settle
#
Start-Sleep -s 30

#
# Start VM2
#
"Info : Starting VM ${vm2name}"

Start-VM -Name $vm2Name -ComputerName $hvServer 
if (-not (WaitForVMToStart))
{
    "Error: ${vm2Name} failed to start"
    return $False
}

#
# Collect metrics for VM1 again now that VM2 is up and running
#
"Info : Collecting metrics for ${vm1Name}"

$vm1 = Get-VM -Name $vm1Name -ComputerName $hvServer 
$afterMemory = $vm1.MemoryAssigned

#
# Stop VM2 since ICA does know about it
#
Stop-VM -Name $vm2Name -ComputerName $hvServer -TurnOff -Force

#
# Compute the difference in assigned memory
#
$memDelta = $afterMemory - $beforeMemory
"Info : Before memory: ${beforeMemory}"
"Info : After memory : ${afterMemory}"
"Info : ${vm1Name} memory was reduced by ${memDelta} bytes"

$results = "Failed"
$retVal = $False
if ($memDelta -lt 0)
{
    $results = "Passed"
    $retVal = $True
}

"Info : Test ${results}"

return $retVal
