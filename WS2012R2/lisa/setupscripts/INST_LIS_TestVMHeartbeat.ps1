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
    Verify the VM is providing heartbeat.

.Description
    Use the PowerShell cmdlet to verify the heartbeat
	provided by the test VM is detected by the Hyper-V
	server.
	
	A sample XML test case definition for this test would look similar to:
        <test>
            <testName>VMHeartBeat</testName>
            <testScript>SetupScripts\INST_LIS_TestVMHeartbeat.ps1</testScript>
            <timeout>600</timeout>
            <noReboot>True</noReboot>
            <testParams>
                <param>TC_COVERED=CORE-02</param>
                <param>rootDir=D:\lisa\trunk\lisablue</param>
            </testParams>
        </test>

.Parameter vmName
    Name of the Test VM.
	
.Parameter hvServer
    Name of the Hyper-V server hosting the test VM.
	
.Parameter testParams
    A semicolon separated list of test parameters.
	
.Example
    .\INST_LIS_TestVMHeartbeat.ps1 "myVM" "localhost" "rootDir"
#>



param([string] $vmName, [string] $hvServer, [string] $testParams)


#####################################################################
#
# TestPort
#
#####################################################################
function TestPort ([String] $serverName, [Int] $port=22, [Int] $to=3)
{
    <#
    .Synopsis
        Test if a port is open on a remote server.

    .Description
        Test if a remote server is listening on a specific TCP
        port.  The default port is the SSH port, port 22.

    .Parameter serverName
        Name of the remote serever to check.

    .Parameter port
        The TCP port number to check.  Default is 22.

    .Parameter to
        Timeout value in seconds.  Default is 3 seconds.

    .Example
        TestPort "192.168.1.101" 22 5
    #>

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

#####################################################################
#
# Main script body
#
#####################################################################

$retVal = $False

"TestVMHeartbeat.ps1"
"VM Name   = ${vmName}"
"HV Server = ${hvServer}"
"TestParams= ${testParams}"

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
$vmIPAddr = $null
$rootDir = $null
$tcCovered = "Undefined"

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
        $rootDir = $tokens[1]
    }
    
    if ($tokens[0].Trim() -eq "ipv4")
    {
        $vmIPAddr = $tokens[1].Trim()
    }

        if ($tokens[0].Trim() -eq "TC_COVERED")
    {
        $tcCovered = $tokens[1].Trim()
    }
}

if (-not $vmIPAddr)
{
    "Error: The IPv4 test parameter was not provided."
    return $False
}

if ($rootDir -eq $null)
{
    "Error: The RootDir test parameter is not defined."
    return $False
}

cd $rootDir

#
# 
#
$summaryLog  = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers ${tcCovered}" | Out-File $summaryLog

#
# Test VM if its running.
#

$vm = Get-VM $vmName -ComputerName $hvServer 
$hvState = $vm.State
if ($hvState -ne "Running")
{
    "Error: VM $vmName is not in running state. Test failed."
    return $retVal
}

#
# We need to wait for TCP port 22 to be available on the VM
#
$heartbeatTimeout = 300
while ($heartbeatTimeout -gt 0)
{
    if ( (TestPort $vmIPAddr) )
    {
        break
    }

    Start-Sleep -seconds 5
    $heartbeatTimeout -= 5
}

if ($heartbeatTimeout -eq 0)
{
    "Error: Test case timed out for VM to go to Running"
    return $False
}

#
# Check the VMs heartbeat
#
$hb = Get-VMIntegrationService -VMName $vmName -ComputerName $hvServer -Name "HeartBeat"
if ($($hb.Enabled) -eq "True")
{
    "Heartbeat detected"
    $retVal = $True   
}
else
{
    "HeartBeat not detected"
     Write-Output "Heartbeat not detected" | Out-File -Append $summaryLog
     return $False
}

#
# If we made it here, everything worked
#

return $retVal