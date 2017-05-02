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
    This script will set the vm in Paused, Saved or Off state.
    
    After that it will perform backup/restore.

    It uses a second partition as target. 

    Note: The script has to be run on the host. A second partition
    different from the Hyper-V one has to be available. 

    For the state param there are 3 options:

    <param>vmState=Paused</param>
    <param>vmState=Off</param>
    <param>vmState=Saved</param>

    A typical XML definition for this test case would look similar
    to the following:
    
    <test>
    <testName>VSS_BackupRestore_State</testName>
    <testScript>setupscripts\VSS_BackupRestore_State.ps1</testScript> 
    <testParams>
        <param>driveletter=F:</param>
        <param>vmState=Paused</param>
        <param>TC_COVERED=VSS-15</param>
    </testParams>
    <timeout>1200</timeout>
    <OnERROR>Continue</OnERROR>
    </test>

.Parameter vmName
    Name of the VM to backup/restore.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example

    .\setupscripts\VSS_BackupRestore_State.ps1 -hvServer localhost -vmName vm_name -testParams 'driveletter=D:;RootDir=path/to/testdir;sshKey=sshKey;ipv4=ipaddress;vmState=Saved'

#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false

#######################################################################
# Channge the VM state 
#######################################################################
function ChangeVMState($vmState,$vmName)
{
    $vm = Get-VM -Name $vmName

    if ($vmState -eq "Off")
    {
        Stop-VM -Name $vmName -ErrorAction SilentlyContinue
        return $vm.state
    }
    elseif ($vmState -eq "Saved")
    {
        Save-VM -Name $vmName -Action SilentlyContinue
        return $vm.state
    }
    elseif ($vmState -eq "Paused") 
    {
        Suspend-VM -Name $vmName -ErrorAction SilentlyContinue
        return $vm.state
    }
    else
    {
        return $false    
    }
}

####################################################################### 
# 
# Main script body 
# 
#######################################################################

# Check input arguments
if ($vmName -eq $null)
{
    "ERROR: VM name is null"
    return $retVal
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
    "vmState" { $vmState = $fields[1].Trim() }
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

if ($null -eq $vmState)
{
    "ERROR: vmState param is not specified."
    return $False
}

# Change the working directory to where we need to be
cd $rootDir

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Source TCUtils.ps1 for common functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
	. .\setupScripts\TCUtils.ps1
	"Info: Sourced TCUtils.ps1"
}
else {
	"Error: Could not find setupScripts\TCUtils.ps1"
	return $false
}


# Source STOR_VSS_Utils.ps1 for common VSS functions
if (Test-Path ".\setupScripts\STOR_VSS_Utils.ps1") {
	. .\setupScripts\STOR_VSS_Utils.ps1
	"Info: Sourced STOR_VSS_Utils.ps1"
}
else {
	"Error: Could not find setupScripts\STOR_VSS_Utils.ps1"
	return $false
}


$sts = runSetup $vmName $hvServer $driveletter
if (-not $sts[-1]) 
{
    return $False
}


# Check if VM is Started
$vm = Get-VM -Name $vmName
$currentState=$vm.state

if ( $currentState -ne "Running" )  
{
    Write-Output "ERROR: $vmName is not started."
    return $False
}

# Change the VM state
$sts = ChangeVMState $vmState $vmName
if (-not $sts[-1])
{
    Write-Output "ERROR: vmState param is wrong. Available options are `'Off`', `'Saved`'' and `'Paused`'."
    return $false
}

elseif ( $sts -ne $vmState )
{
    Write-Output "ERROR: Failed to put $vmName in $vmState state."
    return $False
}

Write-Output "State change of $vmName to $vmState : Success."


$sts = startBackup $vmName $driveLetter
if (-not $sts[-1])
{
    return $False
}
else 
{
    $backupLocation = $sts
}

$sts = restoreBackup $backupLocation
if (-not $sts[-1])
{   
    return $False
}

$sts = checkResults $vmName $hvServer
if (-not $sts[-1]) 
{   
    $retVal = $False
} 
else 
{
	$retVal = $True
    $results = $sts
}


runCleanup $backupLocation

Write-Output "INFO: Test ${results}"
return $retVal