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
#############################################################
#
# VerifyVlanTag.ps1
#
# Description:
#    This script verifies that the Vlan is configured properly on the both VM1,VM2. 
#    It will ping to Vm2 from Vm1 using Vlan IP and vicevarsa.
#
# Test Params:
#    Vlan IPs, External network IPs of both VM1 & VM2, VM2 Name, rootDir
#
#############################################################
param ([String] $vmName, [String] $hvServer, [String] $testParams)



#############################################################
#
# Main script body
#
#############################################################

$retVal = $False

#
# Check the required input args are present
#
if (-not $vmName)
{o
    "Error: null vmName argument"
    return $False
}

if (-not $hvServer)
{
    "Error: null hvServer argument"
    return $False
}

if (-not $testParams)
{
    "Error: null testParams argument"
    return $False
}

#
# Display some info for debugging purposes
#
"VM name     : ${vmName}"
"Server      : ${hvServer}"
"Test params : ${testParams}"

#
# Parse the test params
#

$params = $testParams.Split(";")
foreach($p in $params)
{
    $tokens = $p.Trim().Split("=")
    if ($tokens.Length -ne 2)
    {
        # Just ignore it
        continue
    }
    
    $val = $tokens[1].Trim()
    
    switch($tokens[0].Trim().ToLower())
    {
    "VM1VlanIP"  { $VM1VlanIP = $val }
    "VM2VlanIP"  { $VM2VlanIP = $val }
    "VM1ExtIP" { $VM1ExtIP = $val }
    "VM2ExtIP" { $VM2ExtIP = $val }
    "VM2" { $VM2 = $val }
    "RootDir" { $RootDir = $val }
    "TC_COVERED" { $TC_COVERED = $val }
    default  { continue }
    }
}


if (-not $VM1VlanIP)
{
    "Error: VM1 vlan IP test parameter is missing"
    return $False
}

if (-not $VM2VlanIP)
{
    "Error: VM2 vlan IP test parameter is missing"
    return $False
}

if (-not $VM1ExtIP)
{
    "Error: VM1 Ext IP test parameter is missing"
    return $False
}
if (-not $VM2ExtIP)
{
    "Error: VM2 Ext IP test parameter is missing"
    return $False
}

if (-not $VM2)
{
    "Error: VM2 test parameter is missing"
    return $False
}

if (-not $TC_COVERED)
{
    "Error: Test case number test parameter is missing"
    return $False
}

#
# Change the working directory to where we need to be
#
if (-not (Test-Path $RootDir))
{
    "Error: The directory `"${RootDir}`" does not exist"
    return $False
}
cd $rootDir

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "${TC_COVERED}" | Out-File -Append $summaryLog

#
# Load the HyperVLib version 2 modules
#
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2SP1\Hyperv.psd1
}

#
# Start the VM2
#
Start-VM -VM $VM2 -Server $hvServer  -Force -Wait

Start-Sleep 150


#
# try pinging to VM1 from VM2 using Vlan IP and vicevarsa.
#

$a = .\bin\plink.exe -i .\ssh\lisa_id_rsa.ppk root@${VM1ExtIP} "ping -c 4 ${VM2VlanIP}"

Write-Output $a

$b = $a | Select-String -Pattern "ttl" -Quiet 

if ($b -ne "True")
{
 Write-Output "Ping from VM1 to VM2 on Vlan IP failed" | Out-File -Append $summaryLog
 return $False
}

$a = .\bin\plink.exe -i .\ssh\lisa_id_rsa.ppk root@${VM2ExtIP} "ping -c 4 ${VM1VlanIP}"

Write-Output $a

$b = $a | Select-String -Pattern "ttl" -Quiet 
if ($b -ne "True")
{
 Write-Output "Ping from VM2 to VM1 on Vlan IP failed" | Out-File -Append $summaryLog
 return $False
}

$retVal = $true

Write-Output "Pinging from VM1 to VM2 on Vlan ip and vicevarsa is successful" | Out-File -Append $summaryLog

return $retVal
