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

    TestVMShutdown will send a shut-down request to the specific
    VM.  It then will wait to confirm the VM left the Running
    state.

    The ICA scripts will always pass the vmName, hvServer, and a
    string of testParams to the PowerShell test case script. For
    example, if the <testParams> section was written as:

        <testParams>
            <param>TestCaseTimeout=300</param>
        </testParams>

    The string passed in the testParams variable to the PowerShell
    test case script script would be:

        "TestCaseTimeout=300"

    The PowerShell test case scripts need to parse the testParam
    string to find any parameters it needs.

    All setup and cleanup scripts must return a boolean ($true or $false)
    to indicate if the script completed successfully or not. 
.Parameter vmName
    Name of the VM to test.
    
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
    
.Parameter testParams
    Test data for this test case
    
.Example

#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$rootDir = $null
$vmIPAddr = $null
$testCaseTimeout = 600

#####################################################################
#
# CheckCurrentStateFor
#
#####################################################################
function CheckCurrentStateFor([String] $vmName, [UInt16] $newState)
{
    $stateChanged = $False
    
    $vm = Get-VM $vmName -server $hvServer
    if ($($vm.EnabledState) -eq $newState)
    {
        $stateChanged = $True
    }
    
    return $stateChanged
}

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
    #`
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
            $sts = $tcpclient.EndConnect($iar) | out-Null
            $retVal = $true
        }
        catch
        {
            # Nothing we need to do...
        }

        #if($sts)
        #{
        #    $retVal = $true
        #}
    }
    $tcpclient.Close()

    return $retVal
}

#####################################################################
#
# Main script body
#
#####################################################################

$retVal = $False

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

#
# Parse the testParams string
#
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
    
    if ($tokens[0].Trim() -eq "RootDir")
    {
        $rootDir = $tokens[1].Trim()
    }
    
    if ($tokens[0].Trim() -eq "ipv4")
    {
        $vmIPAddr = $tokens[1].Trim()
    }
}

if ($rootDir -eq $null)
{
    "Error: The RootDir test parameter is not defined."
    return $False
}

if ($vmIPAddr -eq $null)
{
    "Error: The ipv4 test parameter is not defined."
    return $False
}

cd $rootDir

$summaryLog  = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers TC44" | Out-File $summaryLog

#
# Load the PowerShell HyperV library
#
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    $HYPERV_LIBRARY = ".\HyperVLibV2SP1\Hyperv.psd1"
    if ( (Test-Path $HYPERV_LIBRARY) )
    {
        Import-module .\HyperVLibV2SP1\Hyperv.psd1
    }
    else
    {
        "Error: The PowerShell HyperV library does not exist"
        return $False
    }
}

#
# If the VM is in a running state, ask HyyperV to invoke a shut-down.
# The VMs state will go from Running to Stopping, then Stopped.
# The VM Running state = 2
#
$vm = Get-VM $vmName -server $hvServer

if (-not $vm)
{
    "Error: Cannot find VM ${vmName} on server ${hvServer}"
    Write-Output "VM ${vmName} not found" | Out-File -Append $summaryLog
    return $False
}

if ($($vm.EnabledState) -ne 2)
{
    "Error: VM ${vmName} is not in the running state"
    "     : The Invoke-Shutdown was not sent"
    return $False
}

#
# Ask HyperV to request the VM to shut-down, then wait for the 
# VM to go into a Stopped state
#
Invoke-VmShutdown -vm $vmName -server $hvServer -Force
while ($testCaseTimeout -gt 0)
{
    if ( (CheckCurrentStateFor $vmName ([UInt16] [VMState]::Stopped)))
    {
        break
    }   

    Start-Sleep -seconds 2
    $testCaseTimeout -= 2
}

if ($testCaseTimeout -eq 0)
{
    "Error: Test case timed out waiting for VM to go to Stopped"
    return $False
}

Write-Output "Shut-down successful" | Out-File -Append $summaryLog

#
# Now start the VM so the automation scripts can do what they need to do
#
$sts = Start-VM -VM $vmName -Server $hvServer -Wait -Force
if ($sts -ne "OK")
{
    "Error: Unable to restart the VM"
    return $False
}

while ($testCaseTimeout -gt 0)
{
    if ( (CheckCurrentStateFor $vmName ([UInt16] [VMState]::Running)))
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

#
# Finally, we need to wait for TCP port 22 to be available on the VM
#
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
#Start-Sleep -Seconds 90

#
# If we got here, the VM was shut-down and restarted
#

return $True
