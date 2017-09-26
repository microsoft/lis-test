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
    This script tests VSS backup functionality.

.Description
    This script will set Integration Services "Backup (volume checkpoint)" -VSS as disabled, then do offline backup, set VSS as enabled, then do online backup.

    A typical XML definition for this test case would look similar
    to the following:

    <test>
        <testName>STOR_VSS_Backup_Disable_Enable_VSS</testName>
        <setupScript>setupscripts\RevertSnapshot.ps1</setupScript>
        <files>remote-scripts/ica/utils.sh</files>
        <testScript>setupscripts\STOR_VSS_Backup_Disable_Enable_VSS.ps1</testScript>
        <testParams>
            <param>TC_COVERED=VSS-21</param>
        </testParams>
        <timeout>2400</timeout>
        <OnError>Continue</OnError>
    </test>

.Parameter vmName
    Name of the VM to backup

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example

    .\setupscripts\STOR_VSS_Backup_Disable_Enable_VSS.ps1 -hvServer localhost -vmName vm_name -testParams 'driveletter=D:;RootDir=path/to/testdir;sshKey=sshKey;ipv4=ipaddress'

#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

#######################################################################
#
# Main script body
#
#######################################################################

# Check input arguments
if ($vmName -eq $null)
{
    "ERROR: VM name is null"
    return $False
}

# Check input params
$params = $testParams.Split(";")

foreach ($p in $params)
{
  $fields = $p.Split("=")

  switch ($fields[0].Trim())
    {
    "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    "sshKey" { $sshKey = $fields[1].Trim() }
    "ipv4" { $ipv4 = $fields[1].Trim() }
    "rootdir" { $rootDir = $fields[1].Trim() }
    "driveletter" { $driveletter = $fields[1].Trim() }
     default  {}
    }
}

if ($null -eq $sshKey)
{
    "ERROR: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4)
{
    "ERROR: Test parameter ipv4 was not specified"
    return $False
}

if ($null -eq $rootdir)
{
    "ERROR: Test parameter rootdir was not specified"
    return $False
}

if ($null -eq $driveletter)
{
    "ERROR: Backup driveletter is not specified."
    return $False
}

# Change the working directory to where we need to be
cd $rootDir

# Source TCUtils.ps1 for common functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
	. .\setupScripts\TCUtils.ps1
	"Info: Sourced TCUtils.ps1"
}
else {
	"Error: Could not find setupScripts\TCUtils.ps1"
	return $false
}

$loggerManager = [LoggerManager]::GetLoggerManager($vmName, $testParams)
$global:logger = $loggerManager.TestCase

$logger.info("This script covers test case: ${TC_COVERED}")

# Source STOR_VSS_Utils.ps1 for common VSS functions
if (Test-Path ".\setupScripts\STOR_VSS_Utils.ps1") {
	. .\setupScripts\STOR_VSS_Utils.ps1
	$logger.info("Sourced STOR_VSS_Utils.ps1")
}
else {
	$logger.error("Could not find setupScripts\STOR_VSS_Utils.ps1")
	return $false
}
# set the backup type array, if set Integration Service VSS
# as disabled/unchecked, it exectes offline backup, if VSS is
# enabled/checked and hypervvssd is running, it executes online backup.
$backupTypes = @("offline","online")

# checkVSSD uses to set integration service,
# also uses to define whether need to check
# hypervvssd running status during runSetup
$checkVSSD= @($false,$true)

# If the kernel version is smaller than 3.10.0-383,
# it does not take effect after un-check then
# check VSS service unless restart VM.
$supportkernel = "3.10.0.383"
$supportStatus = GetVMFeatureSupportStatus $ipv4 $sshKey $supportkernel

for ($i = 0; $i -le 1; $i++ )
{
   # stop vm then set integration service
   if (-not $supportStatus[-1])
   {
       # need to stop-vm to set integration service
       Stop-VM -Name $vmName -ComputerName $hvServer -Force
   }

   # set service status based on checkVSSD
   $sts = SetIntegrationService $vmName $hvServer "VSS" $checkVSSD[$i]

   if (-not $sts[-1])
   {
       $logger.error("${vmName} failed to set Integration Service")
       return $False
   }

   #  restart the VM to make VSS service change take effect
   if (-not $supportStatus[-1])
   {
       $timeout = 300
       $sts = Start-VM -Name $vmName -ComputerName $hvServer
       if (-not (WaitForVMToStartKVP $vmName $hvServer $timeout ))
       {
           $logger.error("${vmName} failed to start")
           return $False
       }
       	Start-Sleep -s 3
   }
    ## run set up
    $sts = runSetup $vmName $hvServer $driveletter $checkVSSD[$i]
    if (-not $sts[-1])
    {
        return $False
    }

    $sts = startBackup $vmName $driveLetter
    if (-not $sts[-1])
    {
        return $False
    }
    else
    {
        $backupLocation = $sts
    }

    # check the backup type, if VSS integration service is disabled,
    # it executes offline backup, otherwise, it executes online backup.
    $sts = getBackupType

    $temp = $backupTypes[$i]
    if  ( $sts -ne $temp )
    {
        $logger.error("Didn't get expected backup type")
        return $False
    }
    else
    {
        $logger.info("Received expected backup type $temp")
    }
    runCleanup $backupLocation
}
return $True
