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
    Test LIS and shutdown with different RAM sizes.

.Description
    Test LIS and shutdown with different RAM settings
    The XML test case definition for this test would
    look similar to the following:
        <test>
            <testName>RebootDiffSize</testName>
            <testParams>
                <param>TC_COVERED=CORE-17</param>
                <param>MemSize=5GB,2GB</param>
            </testParams>
            <testScript>SetupScripts\CORE_RebootDiffMemory.ps1</testScript>
            <timeout>10800</timeout>
        </test>

.Parameter
    Name of VM to test

.Parameter
    Name of Hyper-V server hosting the VM

.Parameter
    Semicolon separated list of test parameters

.Example

#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$sshKey = $null
$ipv4 = $null
$rootDir = $null
$TC_COVERED = "Undefined"

######################################################################
#
# Get IP from VM
#
######################################################################
function get_vmip()
{
    $timeout = 180
    while ($timeout -gt 0)
    {
        #
        # Check if the VM is in the Hyper-v Running state
        #
        $ipv4 = GetIPv4 $vmName $hvServer
        if ($ipv4)
        {
            break
        }
        start-sleep -seconds 1
        $timeout -= 1
    }

    if($timeout -le 0)
    {
        Write-output "VM timeout at GetIPv4 operation with memory size $memory GB" | Tee-Object -Append -file $summaryLog
        return $False
    }
    else
    {
        # Write-output "VM started with $memory" | Tee-Object -Append -file $summaryLog
        return $True
    }
}

#######################################################################
#
# Main script block
#
#######################################################################

$retVal = $False

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

$params = $testParams.Split(";")

foreach ($p in $params)
{
    $fields = $p.Split("=")
    if ($fields.Length -ne 2)
    {
        # Malformed - just ignore
        continue
    }

    switch ($fields[0].Trim())
    {
    "sshKey"     { $sshKey    = $fields[1].Trim() }
    "ipv4"       { $ipv4      = $fields[1].Trim() }
    "rootdir"    { $rootDir   = $fields[1].Trim() }
    "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    default   {}
    }
}

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue

#
# Make sure the required test params are provided
#
if ($null -eq $sshKey)
{
    Write-output "Error: Test parameter sshKey was not specified" | Tee-Object -Append -file $summaryLog
    $retVal = $False
}

if ($null -eq $ipv4)
{
    Write-output "Error: Test parameter ipv4 was not specified" | Tee-Object -Append -file $summaryLog
    $retVal = $False
}

if (-not $rootDir)
{
    Write-output "Error: Test parameter rootDir was not specified" | Tee-Object -Append -file $summaryLog
    return $False
}

#
# Change the working directory to where we need to be
#
if (-not (Test-Path $rootDir))
{
    Write-output"Error: The directory `"${rootDir}`" does not exist" | Tee-Object -Append -file $summaryLog
    return $False
}

cd $rootDir

Write-output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Source the TCUtils.ps1 file
#
. .\setupscripts\TCUtils.ps1

# Save current memory
$currentMemory = (Get-VMMemory -VMName $vmName -ComputerName $hvServer).startup / 1GB

# Get free memory from server
$osInfo = Get-WMIObject Win32_OperatingSystem -ComputerName $hvServer
$freeMem = [int]$($OSInfo.FreePhysicalMemory) / 1MB

#Array of memory size to boot( total available memory, 70% of available memory, 40% of available memory)
$mem100 = "{0:N0}" -f $($freeMem - 2)
$mem70 = "{0:N0}" -f $($freeMem * 0.7)
$mem40 = "{0:N0}" -f $($freeMem * 0.4)
$memArray = $mem100, $mem70, $mem40

ForEach ($memory in $memArray)
{
    #
    # Shutdown VM.
    #
    $vm = Get-VM -Name $vmName -ComputerName $hvServer
    if($vm.State -ne "Off")
    {
        Stop-VM -Name $vmName -ComputerName $hvServer -Force
        if (-not $?)
        {
           Write-output "Error: Unable to Shut Down VM" | Tee-Object -Append -file $summaryLog
           $retVal = $False
           break
        }

        $timeout = 180
        $sts = WaitForVMToStop $vmName $hvServer $timeout
        if (-not $sts)
        {
           Write-output "Error: WaitForVMToStop fail" | Tee-Object -Append -file $summaryLog
           $retVal = $False
           break
        }
    }
    
    $memoryParam = "VMMemory = ${memory}GB"
    $sts = .\setupScripts\SetVMMemory.ps1 -vmName $vmName -hvServer $hvServer -testParams $memoryParam
    if ($sts[-1] -eq "True")
    {
        Write-output "VM memory count updated to $memory GB RAM" | Tee-Object -Append -file $summaryLog
    }
    else
    {
        Write-output "Error: Unable to update VM memory to $memory GB RAM. Consider changing the value." | Tee-Object -Append -file $summaryLog
        $retVal = $False
        break
    }

    $Error.Clear()
    Start-VM -Name $vmName -ComputerName $hvServer  -ErrorAction SilentlyContinue
    if ( $Error[0] -and $Error[0].Exception.Message.Contains("Not enough memory") )
    {
        Write-output "Error: Not enough memory ($memory) GB to start VM. Consider changing the value." | Tee-Object -Append -file $summaryLog
        $retVal = $False
        break
    }
    $Error.Clear()
    $sts = get_vmip
    if (-not $sts[-1]) {
        Write-output "Error: VM timeout at GetIPv4 operation with memory size $memory GB" | Tee-Object -Append -file $summaryLog
        $retVal = $False
        break
    }
    else
    {
        Write-output "VM started with $memory GB RAM" | Tee-Object -Append -file $summaryLog
    }

    #
    # Wait for VM to start ssh
    #
    $sts = WaitForVMToStartSSH $ipv4 60
    if(-not $sts[-1]){
        Write-Output "ERROR: Port 22 not open" | Tee-Object -Append -file $summaryLog
        $retVal = $False
        break
    }

    #
    # Reboot VM
    #
    $sts = SendCommandToVM $ipv4 $sshKey "reboot now"

    # If the VM has no IP it means it rebooted
    $sts = GetIPv4 $vmName $hvServer

    if (-not $?) {
		Write-Output "ERROR: Failed to reboot VM" | Tee-Object -Append -file $summaryLog
		$retVal = $False
        break
    }

    $sts = get_vmip
    if (-not $?) {
        Write-output "Error: VM timeout at GetIPv4 operation after rebooting" | Tee-Object -Append -file $summaryLog
        $retVal = $False
        break
    }

    $retVal = $True
}

# Reset VM memory
Stop-VM -Name $vmName -ComputerName $hvServer
$sts = .\setupScripts\SetVMMemory.ps1 -vmName $vmName -hvServer $hvServer -testParams "VMMemory = ${currentMemory}GB"

return $retVal
