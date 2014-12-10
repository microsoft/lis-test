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
    

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>
############################################################################
# MMIO_TestVariousGapSizes-2.3.2.ps1
#
# Description:
# This test case script implements MMIO 2.3.2. It verifies setting PCI hole 
# to a linux VM with various gap sizes. The valid range of PCI hole is 128MB-
# 3584MB. This test uses various values inside and outside the valid range.
#
# Any size value outside valid range is an invalid gap size. If user tries
# to set an invalid gap size then the system returns 4096 error code;
# for all valid gap sizes system returns 0.
#
# This script generates the random gap sizes for verification within and
# outside the valid range.
#
# The following is an example of a testParam for setting the PCI_hole size 
# for a VM of 512MB Memory.
#
#	<test>
#       <testName>MMIO_TestVariousGapSizes</testName>
#	    <testScript>SetupScripts\MMIO_TestVariousGapSizes-2.3.2.ps1</testScript>
#	    <timeout>600</timeout>
#   </test>
#
############################################################################

param([string] $vmName, [string] $hvServer, [string] $testParams)

############################################################################
#
# GetGapSize ()
#
# Description: This function generates the random MMIO Gap sizes for the test
#
############################################################################
function GetGapSize ()
{
    $range1 = [int[]] @(1..10 | %{Get-Random -Minimum 4 -Maximum 125}) # Values below the valid range
    $range2 = [int[]] @(1..10 | %{Get-Random -Minimum 131 -Maximum 3582}) # Values within valid range
    $range3 = [int[]] @(1..10 | %{Get-Random -Minimum 3588 -Maximum 4010}) # Values above the valid range
    $range4 = @(0, 1, 2, 3, 126, 127, 129, 130, 3583, 3584, 3585, 3586, 3587, 4094, 4095, 4096, 4097, 4098, 128)
    $newGapSize = $range1 + $range2 + $range3 + $range4
    return $newGapSize
}
############################################################################
#
# TestPort()
#
# Description:This function will wait till the VM on the given hyperv 
# server starts gracefully and verified if the port 22 is open on the VM.
#
############################################################################
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

    #
    # Check to see if the connection is done
    #
    if($connected)
    {
    
    #
    # Close our connection
    #
        try
        {
            $sts = $tcpclient.EndConnect($iar) | out-Null
            $retVal = $true
        }
        catch
        {
            # Nothing we need to do...
        }

    }
    $tcpclient.Close()

    return $retVal
}
############################################################################
#
# GetVmSettingData()
#
# Description:Getting all VM's system settings data from the host hyper-v
# server.
#
############################################################################
function GetVmSettingData([String] $name, [String] $server)
{
    $settingData = $null

    if (-not $name)
    {
        return $null
    }

    $vssd = gwmi -n root\virtualization\v2 -class Msvm_VirtualSystemSettingData -ComputerName $server
    if (-not $vssd)
    {
        return $null
    }

    foreach ($vm in $vssd)
    {
        if ($vm.ElementName -ne $name)
        {
            continue
        }

        return $vm
    }

    return $null
}
###########################################################################
#
# SetMMIOGap()
#
# Description:Function to validate and set the MMIO Gap to the linux VM
#
###########################################################################
function SetMMIOGap([INT] $newGapSize)
{

    #
    # Getting the VM settings
    #
    $vssd = GetVmSettingData $vmName $hvServer
    if (-not $vssd)
    {
        
        return $false
    }
    
    #
    # Create a management object
    #
    $mgmt = gwmi -n root\virtualization\v2 -class Msvm_VirtualSystemManagementService -ComputerName $hvServer
    if(-not $mgmt)
    {
    
        return $false
    }

    #
    # Setting the new PCI hole size
    #
    $vssd.LowMmioGapSize = $newGapSize

    $sts = $mgmt.ModifySystemSettings($vssd.gettext(1))
    
    if ($sts.ReturnValue -eq 0) 
    {
        return $true
    }

    return $false
}
############################################################################
#
# Main script body
#
############################################################################
$retVal = $false

#
# Check input arguments
#
if (-not $vmName)
{
    "Error: VM name is null. "
    return $retVal
}

if (-not $hvServer)
{
    "Error: hvServer is null"
    return $retVal
}

#
# Parse the testParams string
#
$vmIPAddr = $null

$params = $testParams.Split(';')
foreach ($p in $params)
{
    if ($p.Trim().Length -eq 0)
    {
        continue
    }

    $tokens = $p.Trim().Split('=')
    
    if ($tokens.Length -ne 2)
    {
        "Warn : test parameter '$p' is being ignored because it appears to be malformed"
        continue
    }
    
    if ($tokens[0].Trim() -eq "ipv4")
    {
        $vmIPAddr = $tokens[1].Trim()
    }
}

#
# Stopping VM prior to setting MMIO gap
#
$vm = Get-VM -Name $vmName -ComputerName $hvServer
if ($vm.state -ne "off")
{
    Stop-VM -Name $vmName -ComputerName $hvServer -Force
    if(!$?)
    {
        "Error: VM could not be stopped"
        return $false
    }
}

#
# Getting the MMIO Gap sizes for testing
#
$errorsDetected = $False
$newGapSize = GetGapSize

foreach ($entry in $newGapSize)
{
    $gapSize = $entry[0]
    if ($gapSize -lt 128 -or $gapSize -ge 3585)
    {
        $expectedResults = "False"
    }
    else
    {
        $expectedResults = "True"
    }
    

    "Info : Testing gap = ${gapSize}"
    $actualResults = SetMMIOGap $gapSize
    
    if ("$actualResults" -ne "$expectedResults")
    {
        "Error: Setting gap size to ${gapSize} returned unexpected results"
        "       Expected results = ${expectedResults}"
        $errorsDetected = $True
    }
}

$vssd = GetVmSettingData $vmName $hvServer

if (-not $vssd)
{
    "Error: Unable to find settings data for VM '${vmName}'"
    return $false
}

#
# Starting the VM 
#
$testCaseTimeout = 600
$vm = Get-VM -Name $vmName -ComputerName $hvServer
if ($vm.state -ne "Running" -and $vm.Heartbeat -ne "OkApplicationsUnknown")
{
    Start-VM -Name $vmName -ComputerName $hvServer
    while ($testCaseTimeout -gt 0)
    {
        if ( (TestPort $vmIPAddr) )
        {
            break
        }

        Start-Sleep -seconds 2
        $testCaseTimeout -= 2
    }

    if ($testCaseTimeout -eq 0)
    {
        "Error: Test case timed out for VM to go to Running"
        return $False
    }
}

#
# Validating results
#
$msg = "Info : Test Failed"
if (-not $errorsDetected)
{
    $msg = "Info : Test Passed"
    $retVal = $True
}

$msg

return $retVal

