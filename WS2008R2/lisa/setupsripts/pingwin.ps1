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
# pingwin.ps1
#
# Description:
#    Script to run ping command on remote windows VMs.
#
#
############################################################################

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $False

"pingwin.ps1"
"VM Name   = ${vmName}"
"HV Server = ${hvServer}"
"TestParams= ${testParams}"
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
        $rootDir = $tokens[1].Trim()
    }
    
    if ($tokens[0].Trim() -eq "VM1")
    {
       $vm1 = $tokens[1].Trim()
    }
     
    if ($tokens[0].Trim() -eq "VM2")
    {
       $vm2 = $tokens[1].Trim()
    }

    if ($tokens[0].Trim() -eq "IP1")
    {
       $ip1 = $tokens[1].Trim()
    }
     
    if ($tokens[0].Trim() -eq "IP2")
    {
       $ip2 = $tokens[1].Trim()
    }

     if ($tokens[0].Trim() -eq "VP1")
    {
       $pn1 = $tokens[1].Trim()
    }

     if ($tokens[0].Trim() -eq "VP2")
    {
       $pn2 = $tokens[1].Trim()
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
Write-Output "Covers TC97" | Out-File $summaryLog


#
# Load the PowerShell HyperV Library
#
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2Sp1\HyperV.psd1
}

Set-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer -Name "Vm-Bus Network Adapter" -MacAddressSpoofing on
  
 $snic = Get-VMNIC -VM $vmName -VMBus

 if($snic.SwitchName[0] -ne "${pn1}" -or $snic.SwitchName[1] -ne "${pn2}")
  {
    "Error: No Network Adaptor set"
     return $False
  }
  else
  {
    "Network Adapter set"
  }

Start-Sleep 5

#
# Script to test ping on windows VM
#

Enable-PSRemoting -Force

$pass = cat .\pass.txt | ConvertTo-SecureString

$cred = New-Object -type System.Management.Automation.PSCredential -ArgumentList "Administrator",$pass

winrm s winrm/config/client '@{TrustedHosts="'"${vm2}"'"}'

$a = Invoke-Command -ComputerName ${vm2} -ScriptBlock { ping $ip1 } -credential $cred

winrm s winrm/config/client '@{TrustedHosts="'"${vm1}"'"}'

$b = Invoke-Command -ComputerName ${vm1} -ScriptBlock { ping $ip2 } -credential $cred

$c = $a|Select-String -Pattern "TTL" -Quiet

$d = $b|Select-String -Pattern "TTL" -Quiet

if($c -eq "True" -and $d -eq "True")
{
    Write-Output "Ping is successfull" | Out-File -Append $summaryLog
    $retVal = $true
}
else
{
    Write-Output "Ping is failed" | Out-File -Append $summaryLog
    return $false
}

return $retVal