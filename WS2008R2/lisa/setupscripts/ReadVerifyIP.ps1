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
# ReadVerifyIP.ps1
#
# Description:
#     This is a PowerShell test case script that runs on the on
#     the host rather than the VM.
#
#     This read the VM IPV4 & IPV6 addresses using network adapter object and verifies that those are correct.
#     
#     The LISA scripts will always pass the vmName, hvServer, and a
#     string of testParams to the PowerShell test case script. For
#     example, if the <testParams> section was written as:
#
#         <testParams>
#             <param>TestCaseTimeout=300</param>
#         </testParams>
#
#     The string passed in the testParams variable to the PowerShell
#     test case script script would be:
#
#         "TestCaseTimeout=300"
#
#     The PowerShell test case scripts need to parse the testParam
#     string to find any parameters it needs.
#
#     All setup and cleanup scripts must return a boolean ($true or $false)
#     to indicate if the script completed successfully or not.
#
############################################################################
param([string] $vmName, [string] $hvServer, [string] $testParams)


#####################################################################
#
# SendCommandToVM()
#
#####################################################################
function SendCommandToVM([String] $sshKey, [String] $ipv4, [string] $command)
{
    $retVal = $null

    $sshKeyPath = Resolve-Path $sshKey
    
    $dt = .\bin\plink -i ${sshKeyPath} root@${ipv4} $command  

    if ($?)
    {
        $retVal = $dt
    }
    else
    {
        Write-Output "Error: $vmName unable to send command to VM. Command = '$command'"
    }

    return $retVal
}


#####################################################################
#
# Main script body
#
#####################################################################

$retVal = $False

"ReadVerifyIP.ps1"
"VM Name   = ${vmName}"
"HV Server = ${hvServer}"
"TestParams= ${testParams}"
#
# Check input arguments
#
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
$vmIPAddr = $null
$sshKey = $null

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

     if ($tokens[0].Trim() -eq "sshKey")
    {
        $sshKey = $tokens[1].Trim()
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

if (-not $sshKey)
{
    "Error: testParams is missing the sshKey parameter"
    return $False
}

cd $rootDir

#
# Delete any summary.log from a previous test run, then create a new file
#

$summaryLog  = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers TC92" | Out-File $summaryLog


#
# Load the PowerShell HyperV Library
#
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2Sp1\HyperV.psd1
}


#
# Read the IPV4 IP6 address of the VM from hyperv manager
#

$nic = hyper-v\Get-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer -IsLegacy $false

$ips =  $nic.IPAddresses | Out-String -Stream  

$ipv4 = $ips[0]
$ipv6 = $ips[1]

Write-host "VMBUS IP addresses read from Network adapter object are -IPV4 - ${ipv4}, IPV6 - ${ipv6}"


#
# Login to the VM and verify that the IPs received using network adapter object is correct. 
#

$NET_PATH = SendCommandToVM ".\ssh\${sshKey}" $vmIPAddr "find /sys/devices -name net | grep vmbus* | sed -n 1p"

$device = SendCommandToVM ".\ssh\${sshKey}" $vmIPAddr "ls ${NET_PATH}"


[string] $ip_v4 = SendCommandToVM ".\ssh\${sshKey}" $vmIPAddr "ifconfig ${device} | grep 'inet addr:' | cut -d ':' -f 2 | cut -d ' ' -f 1"

if ($ip_v4 -ne $ipv4 )
{
    Write-Output "IPV4 ${ipv4} read from HyperV manager does not match with the IP ${ip_v4} read from VM - interface ${device}" | Out-File $summaryLog
    return $retVal
}


[string] $ip_v6 = SendCommandToVM ".\ssh\${sshKey}" $vmIPAddr "ifconfig ${device} | grep 'inet6 addr:' | cut -d ' ' -f 13 | cut -d '/' -f 1"

if ($ip_v6 -ne $ipv6 )
{
    Write-Output "IPV6 ${ipv6} read from HyperV manager does not match with the IP ${ip_v6} read from VM - interface ${device}" | Out-File $summaryLog
    return $retVal
}
 
Write-Output "Successfully retrieved & verified the VM IP addresses using VM network adapter object -IPV4 - ${ipv4} and IPv6 -${ipv6}" | Out-File $summaryLog

return $True 
