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
    Name of the VM to remove disk from .

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example

    .\setupscripts\VSS_BackupRestore_State.ps1 -hvServer localhost -vmName vm_name -testParams 'driveletter=D:;RootDir=path/to/testdir;sshKey=sshKey;ipv4=ipaddress;vmState=Saved'

#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

#######################################################################
#Checks if the VSS Backup daemon is running on the Linux guest  
#######################################################################
function CheckVSSDaemon()
{
     $retValue = $False
    
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "ps -ef | grep '[h]v_vss_daemon' > /root/vss"
    if (-not $?)
    {
        Write-Error -Message  "ERROR: Unable to run ps -ef | grep hv_vs_daemon" -ErrorAction SilentlyContinue
        Write-Output "ERROR: Unable to run ps -ef | grep hv_vs_daemon"
        return $False
    }

    .\bin\pscp -i ssh\${sshKey} root@${ipv4}:/root/vss .
    if (-not $?)
    {
       
       Write-Error -Message "ERROR: Unable to copy vss from the VM" -ErrorAction SilentlyContinue
       Write-Output "ERROR: Unable to copy vss from the VM"
       return $False
    }

    $filename = ".\vss"
  
    # This is assumption that when you grep vss backup process in file, it will return 1 lines in case of success. 
    if ((Get-Content $filename  | Measure-Object -Line).Lines -eq  "1" ) 
    {
        Write-Output "VSS Daemon is running"  
        $retValue =  $True
    }    
    del $filename   
    return  $retValue 
}

#######################################################################
# Check boot.msg in Linux VM for Recovering journal. 
#######################################################################
function CheckRecoveringJ()
{
    $retValue = $False
       
    .\bin\pscp -i ssh\${sshKey}  root@${ipv4}:/var/log/boot.* ./boot.msg 

    if (-not $?)
    {
      Write-Output "ERROR: Unable to copy boot.msg from the VM"
       return $False
    }

    $filename = ".\boot.msg"
    $text = "recovering journal"
    
    $file = Get-Content $filename
    if (-not $file)
    {
        Write-Error -Message "Unable to read file" -Category InvalidArgument -ErrorAction SilentlyContinue
        return $null
    }

     foreach ($line in $file)
    {
        if ($line -match $text)
        {           
            $retValue = $True 
            Write-Output "$line"          
        }             
    }

    del $filename
    return $retValue    
}

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
        Save-VM -Name $vmName -ErrorAction SilentlyContinue
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
$retVal = $false

Write-Output "Removing old backups"
try { Remove-WBBackupSet -Force -WarningAction SilentlyContinue }
Catch { Write-Output "No existing backup's to remove"}

# Define and cleanup the summaryLog
$summaryLog  = "${vmName}_summary.log"
echo "Covers VSS Backup" > $summaryLog

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

echo $params

# Change the working directory to where we need to be
cd $rootDir

# Source the TCUtils.ps1 file
. .\setupscripts\TCUtils.ps1

# Check if the Vm VHD in not on the same drive as the backup destination 
$vm = Get-VM -Name $vmName -ComputerName $hvServer
if (-not $vm)
{
    "Error: VM '${vmName}' does not exist"
    return $False
}
 
foreach ($drive in $vm.HardDrives)
{
    if ( $drive.Path.StartsWith("${driveLetter}"))
    {
        "Error: Backup partition '${driveLetter}' is same as partition hosting the VMs disk"
        "       $($drive.Path)"
        return $False
    }
}

# Check to see Linux VM is running VSS backup daemon 
$sts = CheckVSSDaemon
if (-not $sts[-1])
{
    Write-Output "ERROR: VSS backup daemon is not running inside Linux VM"
    return $False
}
Write-Output "VSS Daemon is running " >> $summaryLog

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

# Install the Windows Backup feature
Write-Output "Checking if the Windows Server Backup feature is installed..."
try { Add-WindowsFeature -Name Windows-Server-Backup -IncludeAllSubFeature:$true -Restart:$false }
Catch { Write-Output "Windows Server Backup feature is already installed, no actions required."}

# Remove Existing Backup Policy
try { Remove-WBPolicy -all -force }
Catch { Write-Output "No existing backup policy to remove"}

# Set up a new Backup Policy
$policy = New-WBPolicy

# Set the backup backup location
$backupLocation = New-WBBackupTarget -VolumePath $driveletter

# Define VSS WBBackup type
Set-WBVssBackupOptions -Policy $policy -VssCopyBackup

# Add the Virtual machines to the list
$VM = Get-WBVirtualMachine | where vmname -like $vmName
Add-WBVirtualMachine -Policy $policy -VirtualMachine $VM
Add-WBBackupTarget -Policy $policy -Target $backupLocation

# Display the Backup policy
Write-Output "Backup policy is: `n$policy"

# Start the backup
Write-Output "Backing to $driveletter"
Start-WBBackup -Policy $policy

# Review the results            
$BackupTime = (New-Timespan -Start (Get-WBJob -Previous 1).StartTime -End (Get-WBJob -Previous 1).EndTime).Minutes
Write-Output "Backup duration: $BackupTime minutes"           
"Backup duration: $BackupTime minutes" >> $summaryLog

$sts=Get-WBJob -Previous 1
if ($sts.JobState -ne "Completed")
{
    Write-Output "ERROR: VSS WBBackup failed"
    $retVal = $false
    return $retVal
}

Write-Output "`nBackup success!`n"
# Let's wait a few Seconds
Start-Sleep -Seconds 3

# Start the Restore
Write-Output "`nNow let's do restore ...`n"

# Get BackupSet
$BackupSet=Get-WBBackupSet -BackupTarget $backupLocation

# Start Restore
Start-WBHyperVRecovery -BackupSet $BackupSet -VMInBackup $BackupSet.Application[0].Component[0] -Force -WarningAction SilentlyContinue
$sts=Get-WBJob -Previous 1
if ($sts.JobState -ne "Completed")
{
    Write-Output "ERROR: VSS Restore failed"
    $retVal = $false
    return $retVal
}

# Review the results  
$RestoreTime = (New-Timespan -Start (Get-WBJob -Previous 1).StartTime -End (Get-WBJob -Previous 1).EndTime).Minutes
Write-Output "Restore duration: $RestoreTime minutes"
"Restore duration: $RestoreTime minutes" >> $summaryLog

# Make sure VM exsist after VSS backup/restore Operation 
$vm = Get-VM -Name $vmName -ComputerName $hvServer
    if (-not $vm)
    {
        Write-Output "ERROR: VM ${vmName} does not exist after restore"
        return $False
    }
Write-Output "Restore success!"

# Now Start the VM 
$timeout = 500
$sts = Start-VM -Name $vmName -ComputerName $hvServer 
if (-not (WaitForVMToStartKVP $vmName $hvServer $timeout ))
{
    Write-Output "ERROR: ${vmName} failed to start"
    return $False
}
else
{
    Write-Output "INFO: Started VM ${vmName}"
}

# Now Check the boot logs in VM to verify if there is no Recovering journals in it . 
$sts=CheckRecoveringJ
if ($sts[-1])
{
    Write-Output "ERROR: Recovering Journals in Boot log File, VSS Backup/restore is Failed "
    Write-Output "No Recovering Journal in boot logs: Failed" >> $summaryLog
    return $False
}
else 
{
    $results = "Passed"
    $retVal = $True
    Write-Output "INFO: VSS Back/Restore: Success"   
    Write-Output "No Recovering Journal in boot msg: Success" >> $summaryLog
}

# Remove Created Backup
Write-Output "Removing old backups from $backupLocation"
try { Remove-WBBackupSet -BackupTarget $backupLocation -Force -WarningAction SilentlyContinue }
Catch { Write-Output "No existing backup's to remove"}

Write-Output "INFO: Test ${results}"
return $retVal