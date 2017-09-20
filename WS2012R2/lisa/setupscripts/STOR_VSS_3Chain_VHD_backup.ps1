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
    This script will create a new VM with a 3-chained differencing disk
    attached based on the source vm vhd/x.
    If the source Vm has more than 1 snapshot, they will be removed except
    the latest one. If the VM has no snapshots, the script will create one.
    After that it will proceed with backup/restore operation.

    It uses a second partition as target.

    Note: The script has to be run on the host. A second partition
    different from the Hyper-V one has to be available.

    <test>
        <testName>VSS_BackupRestore_3Chain_VHD</testName>
        <testScript>setupscripts\VSS_3Chain_VHD_backup.ps1</testScript>
        <testParams>
            <param>driveletter=F:</param>
        </testParams>
        <timeout>1200</timeout>
        <OnError>Continue</OnError>
    </test>

.Parameter vmName
    Name of the VM to backup/restore.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\VSS_3Chain_VHD_backup.ps1 -hvServer localhost -vmName NameOfVm -testParams 'sshKey=path/to/ssh;rootdir=path/to/testdir;ipv4=ipaddress;driveletter=D:'

#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false
$summaryLog  = "${vmName}_summary.log"
$vm2Name = $null

#######################################################################
# Fix snapshots. If there are more then 1 remove all except latest.
#######################################################################
function FixSnapshots($vmName, $hvServer)
{
    # Get all the snapshots
    $vmsnapshots = Get-VMSnapshot -VMName $vmName
    $snapnumber = ${vmsnapshots}.count

    # Get latest snapshot
    $latestsnapshot = Get-VMSnapshot -VMName $vmName | sort CreationTime | select -Last 1
    $LastestSnapName = $latestsnapshot.name

    # Delete all snapshots except the latest
    if ($snapnumber -gt 1)
    {
        Write-Output "INFO: $vmName has $snapnumber snapshots. Removing all except $LastestSnapName"
        foreach ($snap in $vmsnapshots)
        {
            if ($snap.id -ne $latestsnapshot.id)
            {
                $snapName = ${snap}.Name
                $sts = Remove-VMSnapshot -Name $snap.Name -VMName $vmName -ComputerName $hvServer
                if (-not $?)
                {
                    Write-Output "ERROR: Unable to remove snapshot $snapName of ${vmName}: `n${sts}"
                    return $False
                }
                Write-Output "INFO: Removed snapshot $snapName"
            }

        }
    }

    # If there are no snapshots, create one.
    ElseIf ($snapnumber -eq 0)
    {
        Write-Output "INFO: There are no snapshots for $vmName. Creating one ..."
        $sts = Checkpoint-VM -VMName $vmName -ComputerName $hvServer
        if (-not $?)
        {
           Write-Output "ERROR: Unable to create snapshot of ${vmName}: `n${sts}"
           return $False
        }

    }

    return $True
}

#######################################################################
#
# Main script body
#
#######################################################################
# Source TCUtils.ps1 for common functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
	. .\setupScripts\TCUtils.ps1
	"Info: Sourced TCUtils.ps1"
}
else {
	"Error: Could not find setupScripts\TCUtils.ps1"
	return $false
}

$global:logger = [Logger]::new("${vmName}_summary.log")

# Check input arguments
if ($vmName -eq $null)
{
    $logger.error("VM name is null")
    return $retVal
}

if ($hvServer -eq $null)
{
    $logger.error("hvServer is null")
    return $retVal
}

$params = $testParams.Split(";")

foreach ($p in $params)
{
  $fields = $p.Split("=")

  switch ($fields[0].Trim())
    {
    "sshKey" { $sshKey  = $fields[1].Trim() }
    "ipv4"   { $ipv4    = $fields[1].Trim() }
    "rootDir" { $rootDir = $fields[1].Trim() }
    "driveletter" { $driveletter = $fields[1].Trim() }
     default  {}
    }
}
if ($null -eq $sshKey)
{
    $logger.error("Test parameter sshKey was not specified")
    return $False
}

if ($null -eq $ipv4)
{
    $logger.error("Test parameter ipv4 was not specified")
    return $False
}

if ($null -eq $rootdir)
{
    $logger.error("Test parameter rootdir was not specified")
    return $False
}

if ($null -eq $driveletter)
{
    $logger.error("Backup driveletter is not specified.")
    return $False
}
$vmName1 = "${vmName}_ChildVM"

cd $rootDir
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


$sts = runSetup $vmName $hvServer $driveletter
if (-not $sts[-1])
{
	return $False
}

# Stop the running VM so we can create New VM from this parent disk.
# Shutdown gracefully so we dont corrupt VHD.
Stop-VM -Name $vmName
if (-not $?)
    {
       $logger.error("Unable to Shut Down VM")
       return $False
    }

# Add Check to make sure if the VM is shutdown then Proceed
$timeout = 50
$sts = WaitForVMToStop $vmName $hvServer $timeout
if (-not $sts)
    {
       $logger.error("Unable to Shut Down VM")
       return $False
    }

# Clean snapshots
$logger.info("Cleaning up snapshots")
$sts = FixSnapshots $vmName $hvServer
if (-not $sts[-1])
{
    $logger.error("Cleaning snapshots on $vmname failed.")
    return $False
}

# Get Parent VHD
$ParentVHD = GetParentVHD $vmName $hvServer
if(-not $ParentVHD)
{
    $logger.error("Unable to get parent VHD of VM $vmName")
    return $False
}

$logger.info("Successfully Got Parent VHD")

# Create Child and Grand-Child VHD, use temp path to avoid using same disk with backup drive

$childVhd = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(),"vssVhd")

$CreateVHD = CreateChildVHD $ParentVHD $childVhd $hvServer
if(-not $CreateVHD)
{
    $logger.error("Unable to create Child and Grand Child VHD of VM $vmName")
    return $False
}

$logger.info("Successfully created GrandChild VHD")

# Now create New VM out of this VHD.
# New VM is static hardcoded since we do not need it to be dynamic
$GChildVHD = $CreateVHD

# Get-VM
$vm = Get-VM -Name $vmName -ComputerName $hvServer

# Get the VM Network adapter so we can attach it to the new VM
$VMNetAdapter = Get-VMNetworkAdapter $vmName
if (-not $?)
    {
       $logger.error("Unable to get network adapter")
       return $false
    }

#Get VM Generation
$vm_gen = $vm.Generation
# Create the GChildVM
$newVm = New-VM -Name $vmName1 -VHDPath $GChildVHD -MemoryStartupBytes 1024MB -SwitchName $VMNetAdapter[0].SwitchName -Generation $vm_gen
if (-not $?)
    {
       $logger.error("Creating New VM")
       return $False
    }

# Disable secure boot
if ($vm_gen -eq 2)
{
    Set-VMFirmware -VMName $vmName1 -EnableSecureBoot Off
    if(-not $?)
    {
        $logger.error("Unable to disable secure boot")
        return $false
    }
}

$logger.info("New 3 Chain VHD VM $vmName1 created")

$timeout = 600
$sts = Start-VM -Name $vmName1 -ComputerName $hvServer
$logMsg = Get-VM -Name $vmName1
Write-Output $logMsg
if (-not (WaitForVMToStartKVP $vmName1 $hvServer $timeout ))
{
    $logger.error("${vmName1} failed to start")
    return $False
}

$logger.info("New VM $vmName1 started")

$sts = startBackup $vmName1 $driveletter
if (-not $sts[-1])
{
	$logger.error("Failed backup")
	return $False
} else {
	$backupLocation = $sts
}

$sts = restoreBackup $backupLocation
if (-not $sts[-1])
{
	$logger.error("Failed restore")
	return $False
}

$sts = checkResults $vmName1 $hvServer
if (-not $sts[-1])
{
	$logger.error("Failed result")
	$retVal = $False
}
else
{
	$retVal = $True
    $results = $sts
}


# Get new IPV4
$ipv4 =  GetIPv4 $vmName1 $hvServer
if (-not $?)
    {
       $logger.error("Getting IPV4 of New VM")
       $retVal= $False
    }

$logger.info("New VM's IP is $ipv4")
$logger.info("Test ${results}")

$sts = Stop-VM -Name $vmName1 -TurnOff
if (-not $?)
{
    $logger.error("Unable to Shut Down VM $vmName1")

}

runCleanup $backupLocation

# Clean Delete New VM created
$sts = Remove-VM -Name $vmName1 -Confirm:$false -Force
if (-not $?)
{
    $logger.error("Unable to delete New VM $vmName1")
}

$logger.info("Deleted VM $vmName1")

return $retVal
