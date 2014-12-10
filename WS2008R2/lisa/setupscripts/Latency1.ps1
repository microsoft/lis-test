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
             Script to perform network Latency testing
Pre-requisites
         Need an encrypted password file created using the command - Read-Host -AsSecureString | ConvertFrom-SecureString | Out-File <root directory>\SelfEncryptPasswd.txt   
         On the remote server remoteing should be enabled using command - Enable-PSRemoting -Force

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $False

"Latency.ps1"
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
$RemoteServ = $null
$TC_COVERED = $null
$ips = $null

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


    if ($tokens[0].Trim() -eq "IPS")
    {
       $ips = $tokens[1].Trim()
    }

    if ($tokens[0].Trim() -eq "RemoteServ")
    {
       $RemoteServ = $tokens[1].Trim()
    }

    if ($tokens[0].Trim() -eq "TC_COVERED")
    {
       $TC_COVERED = $tokens[1].Trim()
    }

}

if ($rootDir -eq $null)
{
    "Error: The RootDir test parameter is not defined."
    return $False
}

if ($RemoteServ -eq $null)
{
    "Error: The RemotServ test parameter is not defined."
    return $False
}

if ($ips -eq $null)
{
    "Error: The guest VM IP test parameter is not defined."
    return $False
}

cd $rootDir

#
#
#
$summaryLog  = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers ${TC_COVERED}" | Out-File $summaryLog

#
# Load the PowerShell HyperV Library
#
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2Sp1\HyperV.psd1
}


#
# Ping the guest VM from a remote host and calcuate the average RTT.
#

Enable-PSRemoting -Force

winrm s winrm/config/client '@{TrustedHosts="'"${RemoteServ}"'"}'

$pass = cat .\SelfEncryptPasswd.txt | ConvertTo-SecureString

$cred = New-Object -type System.Management.Automation.PSCredential -ArgumentList "redmond\v-ninad",$pass


$connect = Invoke-Command -ComputerName ${RemoteServ} -ScriptBlock {param($ips) ping -n 50 $ips } -credential $cred -ArgumentList $ips

$check = $connect | Select-String -Pattern "Average"

$temp = $check.ToString() -split "=",4

Write-Output "$temp" | Out-File -Append $summaryLog

$d = $temp[3] -split "ms"

Write-Output "$d" | Out-File -Append $summaryLog

$avg_reg = [int]::Parse("${d}")

Write-Output "Average RTT without load : ${avg_reg}" | Out-File -Append $summaryLog


#
# Start IOZONE tool on the guest VM
#

.\plink.exe -i .\ssh\lisa_id_rsa.ppk root@${ips} pkg_add -r iozone

$pkg = .\plink.exe -i .\ssh\lisa_id_rsa.ppk root@${ips} pkg_info 2>&1

$chkin = $pkg | Select-String -Pattern "iozone" -Quiet

if($chkin -eq "True")
{
 Write-Output "Iozone installed successfully"
}
else
{
 Write-Output "Iozone installation failed"
 return $False
}

Start-Sleep 2

$serv = .\plink.exe -i .\ssh\lisa_id_rsa.ppk root@${ips} "/usr/local/bin/iozone -R -l 2 -u 2 -t 2 -s 100m -b Result.xls &" 2>&1

#
# While the IOZONE is running, ping the guest VM from a remote host and calculate the RTT.
#

#winrm s winrm/config/client '@{TrustedHosts="'"${RemoteServ}"'"}'

#$pass = cat .\SelfEncryptPasswd.txt | ConvertTo-SecureString

#$cred = New-Object -type System.Management.Automation.PSCredential -ArgumentList "redmond\v-ninad",$pass

$connect = Invoke-Command -ComputerName ${RemoteServ} -ScriptBlock {param($ips) ping -n 50 $ips } -credential $cred -ArgumentList $ips

$check = $connect | Select-String -Pattern "Average"

$temp = $check.ToString() -split "=",4

Write-Output "$temp" | Out-File -Append $summaryLog

$d = $temp[3] -split "ms"

Write-Output "$d" | Out-File -Append $summaryLog

$avg_WithLoad = [int]::Parse("${d}")

Write-Output "Average RTT when IOZone running  : ${avg_WithLoad}" | Out-File -Append $summaryLog

$RTT_Threshold = $avg_reg+(($avg_reg*10)/100)

if ($avg_WithLoad -le $RTT_Threshold)
{
 "Latency is in the limits"
 $retVal = $true
}
else
{
 "Latency is out of limit"
 return $False
}


return $retVal