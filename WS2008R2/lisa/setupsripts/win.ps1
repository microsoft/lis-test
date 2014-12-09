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
#
#
# Script to test ping on windows VM
#
#
$retVal = $false

Enable-PSRemoting -Force

winrm s winrm/config/client '@{TrustedHosts="WIN-17KR1IEDQC7"}'

$pass = cat D:\Automation\trunk\lisa\pass.txt | ConvertTo-SecureString
$cred = New-Object -type System.Management.Automation.PSCredential -ArgumentList "Administrator",$pass

$a = Invoke-Command -ComputerName WIN-17KR1IEDQC7 -ScriptBlock { ping 10.10.10.5 } -credential $cred

$b = $a|Select-String -Pattern "TTL" -Quiet
if($b -eq "True")
{
 "Ping is successfull"
 $retVal = $true
}
else
{
 "Ping Failed"
 return $false
}
return $True