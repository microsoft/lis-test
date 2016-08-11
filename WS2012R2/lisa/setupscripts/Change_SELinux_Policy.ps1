#####################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, current_lis 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache current_lis 2.0 License for specific language governing
# permissions and limitations under the License.
#
#####################################################################

<#
.Synopsis

    Test different scenarios for LIS CDs
   .Parameter vmName
    Name of the VM.
    .Parameter hvServer
    Name of the Hyper-V server hosting the VM.
    .Parameter testParams
    Test data for this test case
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

# Checking the input arguments
if (-not $vmName) {
    "Error: VM name is null!"
    return $retVal
}

if (-not $hvServer) {
    "Error: hvServer is null!"
    return $retVal
}

if (-not $testParams) {
    "Error: No testParams provided!"
    "This script requires the test case ID and VM details as the test parameters."
    return $retVal
}

$testParams -match "RootDir=([^;]+)"
if (-not $?){
  "Mandatory param RootDir=Path; not found!"
  return $false
}
$rootDir = $Matches[1]

if (Test-Path $rootDir){
  Set-Location -Path $rootDir
  if (-not $?){
    "Error: Could not change directory to $rootDir !"
    return $false
  }
  "Changed working directory to $rootDir"
}
else{
  "Error: RootDir = $rootDir is not a valid path"
  return $false
}

# Source TCUtils.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1"){
  . .\setupScripts\TCUtils.ps1
}
else{
  "Error: Could not find setupScripts\TCUtils.ps1"
  return $false
}

#
# Checking the mandatory testParams. New parameters must be validated here.
#
$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")

    if ($fields[0].Trim() -eq "rootDir") {
        $rootDir = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "ipv4") {
        $ipv4 = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "sshKey") {
        $sshkey = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "selinux") {
        $selinux = $fields[1].Trim()
    }
}

#
# Verify the VM exists
#

$vm = Get-VM -VMName $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm)
{
    "Error: VM ${vmName} does not exist"
    return $False
}

$ipv4 = GetIPv4 $vmName $hvServer

# Change selinux policy
$sts = SendCommandToVM $ipv4 $sshkey "sed -i 's/SELINUX=\S*/SELINUX=${selinux}/g' /etc/selinux/config"
if (-not $sts[-1]){
    Write-Output "Error: Could not change the selinux policy."
    return $False
}

# Reboot the VM to apply the changes
Restart-VM -VMName $vmName -ComputerName $hvServer -Force

$sts = WaitForVMToStartSSH $ipv4 180
if (-not $sts[-1]){
    Write-Output "Error: $vmName didn't start after reboot"
    return $False
}

return $True