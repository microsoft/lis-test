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
##############################################################################

<#
.Synopsis
    Verify the time sync after VM state change
.Description
    This test will check the time sync of guest OS with the host. It will save/pause the VM, wait for 10 mins,
    resume/start the VM and re-check the time sync.

.Parameter vmName
    Name of the VM to test.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case.

.Example
    setupScripts\INST_timesync_change_state.ps1 -vmName NameOfVm -hvServer localhost -testParams 'sshKey=path/to/ssh;ipv4=ipaddress;vmState=Pause'

#>

param ([String] $vmName, [String] $hvServer, [String] $testParams)

$sshKey = $null
$ipv4 = $null
$rootDir = $null
$testDelay = 600
$chrony_state = $null

#####################################################################
#
# Main script body
#
#####################################################################

#
# Make sure all command line arguments were provided
#
if (-not $vmName)
{
    "Error: vmName argument is null"
    return $False
}

if (-not $hvServer)
{
    "Error: hvServer argument is null"
    return $False
}

if (-not $testParams)
{
    "Error: testParams argument is null"
    return $False
}

#
# Parse the testParams string
#
$params = $testParams.Split(";")
foreach($p in $params)
{
    $tokens = $p.Trim().Split("=")
    if ($tokens.Length -ne 2)
    {
        # Just ignore it
        continue
    }

    $val = $tokens[1].Trim()

    switch($tokens[0].Trim().ToLower())
    {
    "sshkey"  { $sshKey = $val }
    "ipv4"    { $ipv4 = $val }
    "rootdir" { $rootDir = $val }
    "tc_covered" { $tcCovered = $val }
    "vmstate" { $vmState = $val.toLower() }
    "testdelay"  {$testDelay = $val}
    "chrony"  {$chrony_state = $val}
    default  { continue }
    }
}
"Info: testDelay = $testDelay; chrony_state = $chrony_state;"
#
# Make sure the required testParams were found
#
if (-not $sshKey)
{
    "Error: testParams is missing the sshKey parameter"
    return $False
}

if (-not $ipv4)
{
    "Error: testParams is missing the ipv4 parameter"
    return $False
}

if (-not $vmState)
{
    "Error: testParams is missing the vmState parameter"
    return $False
}

#
# Change the working directory
#
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

cd $rootDir

. .\setupscripts\TCUtils.ps1
#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers ${tcCovered}" | Out-File -Append $summaryLog

$retVal = ConfigTimeSync -sshKey $sshKey -ipv4 $ipv4
if (-not $retVal)
{
    Write-Output "Error: Failed to config time sync."
    return $False
}

$diffInSeconds = GetTimeSync -sshKey $sshKey -ipv4 $ipv4
if ($diffInSeconds -and $diffInSeconds -lt 5)
{
    "Info: Time is properly synced"
}
else
{
    Write-Output "Error: Time is out of sync before pause/save action!" | Tee-Object -Append -file $summaryLog
    return $False
}

if ($chrony_state -eq "off")
{
    Write-Output "Info: Chrony has been turned off by shell script."
} 

Start-Sleep -S 10
#
# Pause/Save the VM state and wait for 10 mins.
#
if ($vmState -eq "pause")
{
    Suspend-VM -Name $vmName -ComputerName $hvServer -Confirm:$False
}
elseif ($vmState -eq "save")
{
    Save-VM -Name $vmName -ComputerName $hvServer -Confirm:$False
}
else
{
    Write-Output "Error: Invalid VM state - ${vmState}" | Out-Fie $summaryLog
}

if ($? -ne "True")
{
  write-host "Error while suspending the VM state"
  return $false
}

#
# If the test delay was specified, sleep for a bit
#
"Sleeping for ${testDelay} seconds"
Start-Sleep -S $testDelay

#
# After 10 mins resume the VM and check the time sync.
#
Start-VM -Name $vmName -ComputerName $hvServer -Confirm:$False -WarningAction SilentlyContinue
if ($? -ne "True")
{
  write-host "Error while changing VM state"
  return $false
}

$diffInSeconds = GetTimeSync -sshKey $sshKey -ipv4 $ipv4
if ($diffInSeconds -and $diffInSeconds -lt 5)
{
    Write-Output "Info: Time is properly synced after start action" | Tee-Object -Append -file $summaryLog
    return $True
}
else
{
    Write-Output "Error: Time is out of sync after start action!" | Tee-Object -Append -file $summaryLog
    return $False
}
