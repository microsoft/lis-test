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
# PreScsi2.ps1
#
# Description:
#          Script to connect iSCSI target in iSCSI initiator.
#
#  
############################################################################

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $False

"Preiscsi.ps1"
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

    if ($tokens[0].Trim() -eq "IPT")
    {
       $ipt = $tokens[1].Trim()
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
Write-Output "Covers Scsi_Target" | Out-File $summaryLog


iscsicli.exe QAddTargetPortal $ipt

$status = iscsicli.exe ListTargets | Select-String -Pattern "iqn" -Quiet

if($status -eq "True")
{
    Write-Output "Added new target"
}
else
{
    Write-Output "No target found" | Out-File $summaryLog
    return $False
}

$Alltargets = iscsicli.exe ListTargets | Select-String -Pattern "iqn"

$Targetscon = $Alltargets.ToString().Trim()

Foreach ($Targets in $Targetscon)
{
    iscsicli.exe QLoginTarget $Targets
}

$sessions = gwmi -name root\wmi -class MSiSCSIInitiator_SessionClass

foreach ($sess in $sessions)
{
    $Tip = $sess.ConnectionInformation.TargetAddress
    if($Tip -eq $ipt)
    {
        Write-Output "iSCSI initiator connected successfully" | Out-File $summaryLog
        $retVal = $true
    }
    else
    {
        Write-Output "iSCSI initiator connection not found" 
        continue
    }
}

return $retVal