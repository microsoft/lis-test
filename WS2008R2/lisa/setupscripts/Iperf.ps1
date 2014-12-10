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
    Script to perform network stress testing


.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $False

"SwitchNIC.ps1"
"VM Name   = ${vmName}"
"HV Server = ${hvServer}"
"TestParams= ${testParams}"

#
# Check input arguments
#
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

    if ($tokens[0].Trim() -eq "CVM")
    {
       $cvm = $tokens[1].Trim()
    }

    if ($tokens[0].Trim() -eq "IPS")
    {
       $ips = $tokens[1].Trim()
    }

    if ($tokens[0].Trim() -eq "IPC")
    {
       $ipc = $tokens[1].Trim()
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
Write-Output "Covers TC124" | Out-File $summaryLog


#
# Load the PowerShell HyperV Library
#
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2Sp1\HyperV.psd1
}

#
# Start both the client and server VMs
#


Start-VM -VM $cvm -Server $hvServer -Wait -Force
  
Start-Sleep 60

.\plink.exe -i .\ssh\lisa_id_rsa.ppk root@${ips} pkg_add -r iperf

$pkg = .\plink.exe -i .\ssh\lisa_id_rsa.ppk root@${ips} pkg_info 2>&1

$chkin = $pkg | Select-String -Pattern "iperf" -Quiet

if($chkin -eq "True")
{
 Write-Output "Iperf installed successfully"
}
else
{
 Write-Output "Iperf installation failed"
 return $False
}

Start-Sleep 2

$serv = .\plink.exe -i .\ssh\lisa_id_rsa.ppk root@${ips} "/usr/local/bin/iperf -s >Result.xls &" 2>&1

$chkserv = $serv | Select-String -Pattern "[1]" -Quiet

if($chkserv -eq "True")
{
 Write-Output "Iperf server set"
}
else
{
 Write-Output "Iperf server setting failed"
 return $False
}

$connect = .\plink.exe -i .\ssh\lisa_id_rsa.ppk root@${ipc} /usr/local/bin/iperf -c ${ips} -t 600  2>&1

$check = $connect | Select-String -Pattern "Interval" -Quiet

if($check -eq "True")
{
 Write-Output "Iperf ran successfully"
 $retVal=$true
}
else
{
 Write-Output "Iperf run failed"
 return $False
}

Stop-VM -VM $cvm -Server $hvServer -Wait -Force

return $retVal
