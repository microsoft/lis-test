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

$retVal = $False
$vmIPAddr = $null
$rootDir = $null

#####################################################################
#
# Main script body
#
#####################################################################

# Check input arguments
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
        "Warn: test parameter '$p' is being ignored because it appears to be malformed"
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
        $TC_COVERED = $tokens[1].Trim()
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

# Delete any previous summary.log file, then create a new one
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Source TCUtils.ps1 for test related functions
  if (Test-Path ".\setupScripts\TCUtils.ps1")
  {
    . .\setupScripts\TCUtils.ps1
  }
  else
  {
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
  }

#
# Test if the VM is running
#
$vm = Get-VM $vmName -ComputerName $hvServer 
$hvState = $vm.State
$vmHeartbeat = $vm.Heartbeat

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
    "Error: Test case timed out for VM to enter in the Running state"
    return $False
}

#
# Check the VMs heartbeat
#


$hb = Get-VMIntegrationService -VMName $vmName -ComputerName $hvServer -Name "Heartbeat"
if ($($hb.Enabled) -eq "True" -And $($vm.Heartbeat) -eq "OkApplicationsUnknown")
{
    "Info: Heartbeat detected"
}
else
{
    "Test Failed: VM heartbeat not detected!"
     Write-Output "Heartbeat not detected while the Heartbeat service is enabled" | Out-File -Append $summaryLog
     return $False
}


#
#Disable the VMs heartbeat
#
Disable-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name "Heartbeat"
$status = Get-VMIntegrationService -VMName $vmName -ComputerName $hvServer -Name "Heartbeat"
if ($status.Enabled -eq $False -And $vm.Heartbeat -eq "Disabled")
{
    "Heartbeat disabled successfully"
}
else
{
    "Unable to disable the Heartbeat service"
     Write-Output "Unable to disable the Heartbeat service" | Out-File -Append $summaryLog
     return $False
}

#
#Check the VMs heartbeat again
#
Enable-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name "Heartbeat"
$hb = Get-VMIntegrationService -VMName $vmName -ComputerName $hvServer -Name "Heartbeat"
if ($($hb.Enabled) -eq "True" -And $($vm.Heartbeat) -eq "OkApplicationsUnknown")
{
    "Heartbeat detected again" 
}
else
{
    "Test Failed: VM heartbeat not detected again!"
     Write-Output "Error: Heartbeat not detected after re-enabling the Heartbeat service" | Out-File -Append $summaryLog 
}

#
#Check the VMs heartbeat during booting up
#
Stop-VM -ComputerName $hvServer -Name $vmName 
Start-VM -ComputerName $hvServer -Name $vmName

$hb = Get-VMIntegrationService -VMName $vmName -ComputerName $hvServer -Name "Heartbeat"
if ($($hb.Enabled) -eq "True" -And $($hb.PrimaryStatusDescription) -eq "No Contact")
{
    "During booting up: HeartBeat No Contact"
    $retVal = $True
}
else
{
    "Test Failed: VM heartbeat not detected!"
     Write-Output "Heartbeat not detected while the Heartbeat service is enabled" | Out-File -Append $summaryLog
     return $False
}
#
# If we made it here, everything worked
#
return $retVal
