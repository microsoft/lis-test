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
      The ICA scripts will always pass the vmName, hvServer, and a
  string of testParams from the test definition separated by
  semicolons. The testParams for this script identify disk
  controllers, hard drives, and .vhd types.  The testParams
  have the format of:

     NIC=NIC type, Network Type, Network Name

  NIC Type can be one of the following:
     NetworkAdapter
     LegacyNetworkAdapter

  Network Type can be one of the following:
     External
     Internal
     Private

  Network Name is the name of a existing netowrk.

  This script will not create the network.  It will switch the network.

  The following is an example of a testParam for adding a NIC

    <testParams>
        <param>NIC=NetworkAdapter,External,Corp Ethernet LAN</param>
    <testParams>

  The above will be parsed into the following string by the ICA scripts and passed
  to the setup script:

      "NIC=NetworkAdapter,External,Corp Ehternet LAN"

  The setup (and cleanup) scripts need to parse the testParam
  string to find any parameters it needs.

  Notes:
    This is a setup script that will run as pretest script.
    This script will switch NIC network of the VM.

   The .xml entry for this script could look like either of the
    following:
        <pretest>setupScripts\SwitchNIC.ps1</pretest>

  All scripts must return a boolean ($true or $false)
  to indicate if the script completed successfully or not.

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

.\plink.exe -i .\ssh\lisa_id_rsa.ppk root@10.200.48.247 pkg_add -r iperf

Start-Sleep 5

.\plink.exe -i .\ssh\lisa_id_rsa.ppk root@10.200.48.247 "/usr/local/bin/iperf -s >Result.xls &"

$connect = .\plink.exe -i .\ssh\lisa_id_rsa.ppk root@10.200.48.24 /usr/local/bin/iperf -c 10.200.48.247 -t 600  2>&1

$check = $connect | Select-String -Pattern "Interval" -Quiet

Write-Output $check

if($check -eq "True")
{
 Write-Output "Iperf ran successfully"
 $retVal=$true
}

return $retVal
