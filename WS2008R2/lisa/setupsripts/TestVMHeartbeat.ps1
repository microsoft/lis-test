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
#
# TestVMHeartbeat.ps1
#
# Description:
#     This is a PowerShell test case script that runs on the on
#     the ICA host rather than the VM.
#
#     TestVMHeartbeat will check to see if the Hyper-V heartbeat
#     of the VM can be detected.
#
#     The ICA scripts will always pass the vmName, hvServer, and a
#     string of testParams to the PowerShell test case script. This
#     test case script does not require any parameters.
#
#     Final test case is determined by returning either True of False.
#
############################################################################
param([string] $vmName, [string] $hvServer, [string] $testParams)

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
$rootDir = $null

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
Write-Output "Covers TC41" | Out-File $summaryLog

#
# Set the heartbeat timeout to 60 seconds
#
$heartbeatTimeout = 60

#
# Load the PowerShell HyperV Library
#
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2Sp1\HyperV.psd1
}

# Test VM if its running.
#

$vm = Get-VM $vmName -server $hvServer 
$hvState = $vm.EnabledState
if ($hvState -ne 2)
{
    "Error: VM $vmName is not in running state. Test failed."
    return $retVal
}

#
# Test the VMs heartbeat
#
$hb = Test-VmHeartbeat -vm $vmName -server $hvServer -HeartBeatTimeOut $heartbeatTimeout
if ($hb -ne $null)
{
    if ($hb.status -eq "OK")
    {
        "Heartbeat detected"
        Write-Output "Heartbeat detected" | Out-File -Append $summaryLog
        $retVal = $True   
    }
}

return $retVal
