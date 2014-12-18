##########################################################################
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
##########################################################################
<#
.Synopsis
    This script enables Secure Boot features of a Generation 2 VM.

.Description
    This setup script will enable the Secure Boot features of a Generation 2 VM.
    
.Parameter vmName
    Name of the VM to remove disk from .

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\SecureBootVSS.ps1 -hvServer localhost -vmName NameOfVm -testParams 'sshKey=path/to/ssh;rootdir=path/to/testdir;ipv4=ipaddress;driveletter=D:'

#>
param(
    [String] $vmName,
    [String] $hvServer,
    [String] $testParams
)

if (-not $vmName)
{
    "Error: no VMName specified"
    return $False
}

if (-not $hvServer)
{
    "Error: no hvServer specified"
    return $False
}

if (-not $testParams)
{
    "Error: no testParams specified"
    return $False
}

$error.Clear()
$vm = Get-VM -Name $vmName
if ($error.Count -gt 0)
{
    "Error: Unable to get `"${vmName}`" vm"
    $error[0].Exception
    return $False
}

#
# Check if it's a Generation 2 vm

if ($vm.Generation -ne 2)
{
    "Error: `"${vmName}`" is not a Generation 2 vm"
    return $False
}

#
# Check if Secure Boot is enabledd
#
$firmwareSettings = Get-VMFirmware -VMName $vm.Name
if ($firmwareSettings.SecureBoot -ne "On")
{
    $error.Clear()
    Set-VMFirmware -VMName $vm.Name -EnableSecureBoot On
    if ($error.Count -gt 0)
    {
        "Error: Unable to enable secure boot"
        $error[0].Exception
        return $False
    }
}

$error.Clear()
Set-VMFirmware -VMName $vm.Name -SecureBootTemplate MicrosoftUEFICertificateAuthority
if ($error.Count -gt 0)
{
    "Error: Unable to set secure boot template"
    $error[0].Exception
    return $False
}

Write-Host "Secure Boot: $($firmwareSettings.SecureBoot).`nSecure Boot Template: $($firmwareSettings.SecureBootTemplate) "

return $True
