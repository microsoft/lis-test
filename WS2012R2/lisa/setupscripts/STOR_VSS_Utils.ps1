
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
    Utility functions for VSS test cases.

.Description
    VSS Utility functions.  This is a collection of function
    commonly used by PowerShell scripts in VSS tests.
#>

function runSetup([string] $vmName, [string] $hvServer, [string] $driveletter, [boolean] $check_vssd = $True)
{
	$sts = Test-Path $driveletter
	if (-not $sts)
	{
		$logger.error("Error: Drive ${driveletter} does not exist")
		return $False
	}
	$logger.info("Removing old backups")
	try { Remove-WBBackupSet -Force -WarningAction SilentlyContinue }
	Catch { $logger.info("No existing backup's to remove") }

	# Check if the Vm VHD in not on the same drive as the backup destination
	$vm = Get-VM -Name $vmName -ComputerName $hvServer
	if (-not $vm)
	{
		$logger.error("VM ${vmName} does not exist")
		return $False
	}

	foreach ($drive in $vm.HardDrives)
	{
		if ( $drive.Path.StartsWith("${driveLetter}"))
		{
			$logger.error("Backup partition ${driveLetter} is same as partition hosting the VMs disk $($drive.Path)")
			return $False
		}
	}
	if ($check_vssd)
	{
		# Check to see Linux VM is running VSS backup daemon
		$sts = RunRemoteScript "STOR_VSS_Check_VSS_Daemon.sh"
		if (-not $sts[-1])
		{
			$logger.error("Executing $remoteScript on VM. Exiting test case!")
			return $False
		}
			$logger.info("VSS Daemon is running")
	}

	# Create a file on the VM before backup
 	$sts = CreateFile "/root/1"
 	if (-not $sts[-1])
	{
		$logger.error("Cannot create test file")
		return $False
 	}

	$logger.info("File created on VM: $vmname")
	return $True
}

function startBackup([string] $vmName, [string] $driveletter)
{
    # Remove Existing Backup Policy
	try { Remove-WBPolicy -all -force }
	Catch { $logger.info("No existing backup policy to remove")}

	# Set up a new Backup Policy
	$policy = New-WBPolicy

	# Set the backup location
	$backupLocation = New-WBBackupTarget -VolumePath $driveletter

	# Define VSS WBBackup type
	Set-WBVssBackupOptions -Policy $policy -VssCopyBackup

	# Add the Virtual machines to the list
	$VM = Get-WBVirtualMachine | where vmname -like $vmName
	Add-WBVirtualMachine -Policy $policy -VirtualMachine $VM
	Add-WBBackupTarget -Policy $policy -Target $backupLocation

	# Start the backup
	Write-Output "Backing to $driveletter"
	Start-WBBackup -Policy $policy

	# Review the results
	$BackupTime = (New-Timespan -Start (Get-WBJob -Previous 1).StartTime -End (Get-WBJob -Previous 1).EndTime).Minutes
	$logger.info("Backup duration: $BackupTime minutes")

	$sts=Get-WBJob -Previous 1
	if ($sts.JobState -ne "Completed" -or $sts.HResult -ne 0)
	{
		$logger.error("VSS Backup failed")
		$logger.error($sts.ErrorDescription)
		return $False
	}

	$logger.info(":Backup successful!")
	# Let's wait a few Seconds
	Start-Sleep -Seconds 70

	# Delete file on the VM
	$vmState = $(Get-VM -name $vmName -ComputerName $hvServer).state
    if (-not $vmState) {
		$sts = DeleteFile
		if (-not $sts[-1])
		{
			$logger.error("Cannot delete test file!")
			return $False
		}
		$logger.info("File deleted on VM: $vmname")
	}
	return $backupLocation
}

function restoreBackup([string] $backupLocation)
{
    # Start the Restore
	$logger.info("Now let's restore the VM from backup.")

	# Get BackupSet
	$BackupSet = Get-WBBackupSet -BackupTarget $backupLocation

	# Start restore
	Start-WBHyperVRecovery -BackupSet $BackupSet -VMInBackup $BackupSet.Application[0].Component[0] -Force -WarningAction SilentlyContinue
	$sts=Get-WBJob -Previous 1
	if ($sts.JobState -ne "Completed" -or $sts.HResult -ne 0)
	{
		$logger.error("VSS Restore failed")
		$logger.error($sts.ErrorDescription)
		return $False
	}
	return $True
}

function checkResults([string] $vmName, [string] $hvServer)
{
   # Review the results
	$RestoreTime = (New-Timespan -Start (Get-WBJob -Previous 1).StartTime -End (Get-WBJob -Previous 1).EndTime).Minutes
	$logger.error("Restore duration: $RestoreTime minutes")

	# Make sure VM exists after VSS backup/restore operation
	$vm = Get-VM -Name $vmName -ComputerName $hvServer
		if (-not $vm)
		{
			$logger.error("VM ${vmName} does not exist after restore")
			return $False
		}
	$logger.info("Restore success!")

	# After Backup Restore VM must be off make sure that.
	if (-not $vm.state) {
		$logger.info("Waiting for vm to turn off")
		Start-Sleep -Seconds 60

		if ( $vm.state -ne "Off" )
		{
			$logger.error("VM is not in OFF state, current state is " + $vm.state)
			return $False
		}
	}

	# Now Start the VM
	$timeout = 300
	$sts = Start-VM -Name $vmName -ComputerName $hvServer
	if (-not (WaitForVMToStartKVP $vmName $hvServer $timeout ))
	{
		$logger.error("${vmName} failed to start")
		return $False
	}
	else
	{
		$logger.info("Started VM ${vmName}")
	}

	Start-Sleep -s 60

	# Now Check the boot logs in VM to verify if there is no Recovering journals in it .

	$sts= GetSelinuxAVCLog
	if ($sts[-1])
    {
        $logger.error("There is selinux avc denied log in audit log")
        return $False
    }
    else
    {
        $logger.info("no selinux avc deny log in audit logs")
    }
	# only check restore file when ip available
	#$ipv4 = GetIPv4 $vmName $hvServer
	$stsipv4 = Test-NetConnection $ipv4 -Port 22 -WarningAction SilentlyContinue
	if ($stsipv4.PingSucceeded)
	{
		$sts= CheckFile "/root/1"
		if (-not $sts[-1])
		{
			$logger.error("No /root/1 file after restore")
			return $False
		}
		else
		{
			$logger.info("there is /root/1 file after restore")
			Write-Output $logMessage
		}
	}
	else
	{
		$logger.info("Ignore checking file /root/1 when no network")
	}

	# Now Check the boot logs in VM to verify if there is no Recovering journals in it .
	$sts=CheckRecoveringJ
    if ($sts[-1])
    {
        $logger.error("No Recovering Journal in boot logs")
        return $False
    }
    else
    {
        $results = "Passed"
        $logger.info("Recovering Journal in boot msg: Success")
		$logger.info("INFO: VSS Back/Restore: Success")
        return $results
    }
}

function runCleanup([string] $backupLocation)
{
    # Remove Created Backup
    $logger.info("Removing old backups from $backupLocation")
    try { Remove-WBBackupSet -BackupTarget $backupLocation -Force -WarningAction SilentlyContinue }
    Catch { $logger.info("No existing backup's to remove")}
}

function getBackupType()
{
	# check the latest successful job backup type, "online" or "offline"
	$backupType = $null
	$sts = Get-WBJob -Previous 1
	if ($sts.JobState -ne "Completed" -or $sts.HResult -ne 0)
	{
		$logger.error("VSS Backup failed ")
		return $backupType
	}

	$contents = get-content $sts.SuccessLogPath
	foreach ($line in $contents )
	{
		if ( $line -match "Caption" -and $line -match "online")
		{
			$logger.info("VSS Backup type is online")
			$backupType = "online"

		}
		elseif ($line -match "Caption" -and $line -match "offline")
		{
			$logger.info("VSS Backup type is offline")
			$backupType = "offline"
		}
	}
	return $backupType
}
