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
    Name of the VM to remove disk from .

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\VSS_3Chain_VHD_backup.ps1 -hvServer localhost -vmName NameOfVm -testParams 'sshKey=path/to/ssh;rootdir=path/to/testdir;ipv4=ipaddress;driveletter=D:'

.Link
    http://technet.microsoft.com/en-us/library/jj873971.aspx
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

#######################################################################
# Checks if the VSS Backup daemon is running on the Linux guest  
#######################################################################
function CheckVSSDaemon()
{
     $retValue = $False
    
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "ps -ef | grep hv_vss_daemon > /root/vss"
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
  
    
    $line = Get-Content $filename  | Measure-Object –Line
    if (-not $line)
    {
         Write-Error -Message "Unable to read file" -Category InvalidArgument -ErrorAction SilentlyContinue
         Write-Output "ERROR: Unable to copy vss from the VM"
       
    }

    # !!!!
    # This is assumption that when you grep vss backup process in file, it will always return 3 lines in case of success. 
    if ($line.Lines -eq  "3" )
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
       
    echo y | .\bin\pscp -i ssh\${sshKey} root@${ipv4}:/var/log/boot.* ./boot.msg 

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
# To Get Parent VHD from VM.
#######################################################################
function GetParentVHD($vmName, $hvServer)
{
    $ParentVHD = $null     

    $VmInfo = Get-VM -Name $vmName 
    if (-not $VmInfo)
        { 
             Write-Error -Message "Error: Unable to collect VM settings for ${vmName}" -ErrorAction SilentlyContinue
             return $False
        }    
    
    if ( $VmInfo.Generation -eq "" -or $VmInfo.Generation -eq 1  )
        {
            $Disks = $VmInfo.HardDrives
            foreach ($VHD in $Disks)
                {
                    if ( ($VHD.ControllerLocation -eq 0 ) -and ($VHD.ControllerType -eq "IDE"  ))
                        {
                            $Path = Get-VHD $VHD.Path
                            if ( $Path.ParentPath -eq "")
                                {
                                    $ParentVHD = $VHD.Path
                                }
                            else{
                                    $ParentVHD =  $Path.ParentPath
                                }

                            Write-Host "Parent VHD Found: $ParentVHD "
                        }
                }            
        }
    if ( $VmInfo.Generation -eq 2 )
        {
            $Disks = $VmInfo.HardDrives
            foreach ($VHD in $Disks)
                {
                    if ( ($VHD.ControllerLocation -eq 0 ) -and ($VHD.ControllerType -eq "SCSI"  ))
                        {
                            $Path = Get-VHD $VHD.Path
                            if ( $Path.ParentPath -eq "")
                                {
                                    $ParentVHD = $VHD.Path
                                }
                            else{
                                    $ParentVHD =  $Path.ParentPath
                                }
                            Write-Host "Parent VHD Found: $ParentVHD "
                        }
                }  
        }

    if ( -not ($ParentVHD.EndsWith(".vhd") -xor $ParentVHD.EndsWith(".vhdx") ))
    {
         Write-Error -Message " Parent VHD is Not correct please check VHD, Parent VHD is: $ParentVHD " -ErrorAction SilentlyContinue
         return $False
    }

    return $ParentVHD    

}

#######################################################################
# To Create Grand Child VHD from Parent VHD.
#######################################################################
function CreateGChildVHD($ParentVHD)
{

    $GChildVHD = $null
    $ChildVHD  = $null

    $hostInfo = Get-VMHost -ComputerName $hvServer
        if (-not $hostInfo)
        {
             Write-Error -Message "Error: Unable to collect Hyper-V settings for ${hvServer}" -ErrorAction SilentlyContinue
             return $False
        }

    $defaultVhdPath = $hostInfo.VirtualHardDiskPath
        if (-not $defaultVhdPath.EndsWith("\"))
        {
            $defaultVhdPath += "\"
        }

    # Create Child VHD

    if ($ParentVHD.EndsWith("x") )
    {
        $ChildVHD = $defaultVhdPath+$vmName+"-child.vhdx"
        $GChildVHD = $defaultVhdPath+$vmName+"-Gchild.vhdx"

    }
    else
    {
        $ChildVHD = $defaultVhdPath+$vmName+"-child.vhd"
        $GChildVHD = $defaultVhdPath+$vmName+"-Gchild.vhd"
    }

    if ( Test-Path  $ChildVHD )
    {
        Write-Host "Deleting existing VHD $ChildVHD"        
        del $ChildVHD
    }

     if ( Test-Path  $GChildVHD )
    {
        Write-Host "Deleting existing VHD $GChildVHD"        
        del $GChildVHD
    }

     # Create Child VHD  

    New-VHD -ParentPath:$ParentVHD -Path:$ChildVHD     
    if (-not $?)
    {
       Write-Error -Message "Error: Unable to create child VHD"  -ErrorAction SilentlyContinue
       return $False
    }

     # Create Grand Child VHD    
    
    $newVHD = New-VHD -ParentPath:$ChildVHD -Path:$GChildVHD
    if (-not $?)
    {
       Write-Error -Message "Error: Unable to create Grand child VHD" -ErrorAction SilentlyContinue
       return $False
    }

    return $GChildVHD    

}

######################################################################
# Get Network Adapter 
#######################################################################
function NetworkAdapter($hvServer)
{

    $NetworkAdapter = $null
    

    $hostInfo = Get-VMHost -ComputerName $hvServer
        if (-not $hostInfo)
        {
             Write-Error -Message "Error: Unable to collect Hyper-V settings for ${hvServer}" -ErrorAction SilentlyContinue
             return $False
        }

    $NetworkAdapter = $hostInfo.ExternalNetworkAdapters.SwitchName
        if (-not $NetworkAdapter)
        {
            Write-Error -Message "Error: Unable to collect Hyper-V ExternalNetworkAdapters for ${hvServer}" -ErrorAction SilentlyContinue
             return $False
        }


    return $NetworkAdapter    

}

#######################################################################
#
# Main script body
#
#######################################################################

$retVal = $false

$summaryLog  = "${vmName}_summary.log"

echo "Covers: VSS Backup 3 Chain VHD " >> $summaryLog

Write-Output "Removing old backups"
try { Remove-WBBackupSet -Force }
Catch { Write-Output "No existing backup's to remove"}

# Check input arguments
if ($vmName -eq $null)
{
    Write-Output "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null)
{
    Write-Output "Error: hvServer is null"
    return $retVal
}

$vm2Name = $null

$params = $testParams.Split(";")

foreach ($p in $params)
{
  $fields = $p.Split("=")
    
  switch ($fields[0].Trim())
    {
    "sshKey" { $sshKey  = $fields[1].Trim() }
    "ipv4"   { $ipv4    = $fields[1].Trim() }
    "rootdir" { $rootDir = $fields[1].Trim() }
    "driveletter" { $driveletter = $fields[1].Trim() }
     default  {}          
    }
}

if ($null -eq $sshKey)
{
    Write-Output "ERROR: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4)
{
    Write-Output "ERROR: Test parameter ipv4 was not specified"
    return $False
}

if ($null -eq $driveletter)
{
    Write-Output "ERROR: Test parameter driveletter was not specified."
    return $False
}

# Change the working directory to where we need to be
if (-not (Test-Path $rootDir))
{
    Write-Output "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

$vmName1 = "${vmName}_ChildVM"

cd $rootDir

# Source the TCUtils.ps1 file
. .\setupscripts\TCUtils.ps1

# Check to see Linux VM is running VSS backup daemon 
$sts = CheckVSSDaemon
if (-not $sts[-1])
{
    Write-Output "Error:  VSS backup daemon is not running inside Linux VM "
    return $False
}

echo "VSS Daemon is running " >> $summaryLog
Write-Output "INFO: VSS Daemon is running on $vmName"

# Stop the running VM so we can create New VM from this parent disk.
# Shutdown gracefully so we dont corrupt VHD.
Stop-VM –Name $vmName 
if (-not $?)
    {
       Write-Output "Error: Unable to Shut Down VM" 
       return $False
    }

echo "after stop vm" >> $summaryLog

# Add Check to make sure if the VM is shutdown then Proceed
$timeout = 50
$sts = WaitForVMToStop $vmName $hvServer $timeout
if (-not $sts)
    {
       Write-Output "Error: Unable to Shut Down VM"
       return $False
    }

# Clean snapshots
Write-Output "INFO: Cleaning up snapshots..."
$sts = FixSnapshots $vmName $hvServer
if (-not $sts[-1])
{
    Write-Output "Error: Cleaning snapshots on $vmname failed."
    return $False
}

# Get Parent VHD 
echo "after stopped vm " >> $summaryLog
$ParentVHD = GetParentVHD $vmName -$hvServer
if(-not $ParentVHD)
{
    "Error: Error getting Parent VHD of VM $vmName"
    return $False
} 

Write-Output "INFO: Successfully Got Parent VHD"
echo "get parent vhd " >> $summaryLog

# Creat Child and Grand Child VHD .
$CreateVHD = CreateGChildVHD $ParentVHD
if(-not $CreateVHD)
{
    Write-Output "Error: Error Creating Child and Grand Child VHD of VM $vmName"
    return $False
} 

Write-Output "INFO: Successfully Created GrandChild VHD"

# This is required for new vm creation .
$Switch = NetworkAdapter $hvServer
if (-not $?)
    {
       Write-Output "Error: Getting Switch Name" 
       return $False
    }

# Now create New VM out of this VHD.
# New VM is static hardcoded since we do not need it to be dynamic
$GChildVHD = $CreateVHD[-1]

$newVm = New-VM -Name $vmName1 -VHDPath $GChildVHD -MemoryStartupBytes 1024MB -SwitchName $Switch
if (-not $?)
    {
       Write-Output "Error: Creating New VM" 
       return $False
    }

echo "New 3 Chain VHD VM $vmName1 Created: Success" >> $summaryLog
Write-Output "INFO: New 3 Chain VHD VM $vmName1 Created"

$timeout = 500
$sts = Start-VM -Name $vmName1 -ComputerName $hvServer 
if (-not (WaitForVMToStartKVP $vmName1 $hvServer $timeout ))
{
    Write-Output "Error: ${vmName1} failed to start"
     return $False
}

Write-Output "INFO: New VM $vmName1 started"

# Install the Windows Backup feature
Write-Output "INFO: Checking if the Windows Server Backup feature is installed..."
try { Add-WindowsFeature -Name Windows-Server-Backup -IncludeAllSubFeature:$true -Restart:$false }
Catch { Write-Output "Windows Server Backup feature is already installed, no actions required."}

echo "`n"
# Remove Existing Backup Policy
try { Remove-WBPolicy -all -force }
Catch { Write-Output "No existing backup policy to remove"}

echo "`n"
# Set up a new Backup Policy
$policy = New-WBPolicy

# Set the backup backup location
$backupLocation = New-WBBackupTarget -VolumePath $driveletter

# Define VSS WBBackup type
Set-WBVssBackupOptions -Policy $policy -VssCopyBackup

# Add the Virtual machines to the list
$VMtoBackup = Get-WBVirtualMachine | where vmname -like $vmName1
Add-WBVirtualMachine -Policy $policy -VirtualMachine $VMtoBackup
Add-WBBackupTarget -Policy $policy -Target $backupLocation

# Display the Backup policy
Write-Output "Backup policy is: `n$policy"

# Start the backup
Write-Output "Backing to $driveletter"
Start-WBBackup -Policy $policy

# Review the results            
Get-WBSummary            
Get-WBBackupSet -BackupTarget $backupLocation        
Get-WBJob -Previous 1 >> $summaryLog

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
Start-WBHyperVRecovery -BackupSet $BackupSet -VMInBackup $BackupSet.Application[0].Component[0] -Force
$sts=Get-WBJob -Previous 1
if ($sts.JobState -ne "Completed")
{
    Write-Output "ERROR: VSS WB Restore failed"
    $retVal = $false
    return $retVal
}

# Review the results  
Get-WBSummary            
Get-WBBackupSet -BackupTarget $backupLocation        
Get-WBJob -Previous 1 >> $summaryLog

# Make sure VM exist after VSS backup/restore operation 
$vm = Get-VM -Name $vmName1 -ComputerName $hvServer
    if (-not $vm)
    {
        Write-Output "ERROR: VM ${vmName1} does not exist after restore"
        return $False
    }
Write-Output "Restore success!"

# After Backup Restore VM must be off make sure that.
if ( $vm.state -ne "Off" )  
{
    Write-Output "ERROR: VM is not in OFF state, current state is " + $vm.state
    return $False
}

# Now Start the VM
$timeout = 500
$sts = Start-VM -Name $vmName1 -ComputerName $hvServer 
if (-not (WaitForVMToStartKVP $vmName1 $hvServer $timeout ))
{
    Write-Output "ERROR: ${vmName1} failed to start"
    return $False
}
else
{
    Write-Output "INFO: Started VM ${vmName1}"
}

# Get new IPV4
$ipv4 =  GetIPv4 $vmName1 $hvServer
if (-not $?)
    {
       Write-Output "Error: Getting IPV4 of New VM"
       return $False
    }

Write-Output "INFO: New VM's IP is $ipv4" 

# Now Check the boot logs in VM to verify if there is no Recovering journals in it . 
$recovery=CheckRecoveringJ $ipv4
if ($recovery[-1])
{
    Write-Output "ERROR: Recovering Journals in Boot log file, VSS backup/restore failed!"
    Write-Output "No Recovering Journal in boot logs: Failed" >> $summaryLog
    return $False
}
else 
{
    $results = "Passed"
    $retVal = $True
    Write-Output "`nINFO: VSS Back/Restore: Success"   
    Write-Output "No Recovering Journal in boot msg: Success" >> $summaryLog
}

Write-Output "INFO: Test ${results}"

$sts = Stop-VM –Name $vmName1 -TurnOff
if (-not $?)
    {
       Write-Output "Error: Unable to Shut Down VM $vmName1" 
       
    }

# Remove Existing Backups
Write-Output "Removing old backups from $backupLocation"
try { Remove-WBBackupSet -BackupTarget $backupLocation -Force }
Catch { Write-Output "No existing backup's to remove"}

# Clean Delete New VM created 
$sts = Remove-VM -Name $vmName1 -Confirm:$false -Force
if (-not $?)
    {
      Write-Output "Error: Deleting New VM $vmName1"  
    } 

Write-Output "INFO: Deleted VM $vmName1"

if ($recovery[-1])
{
    return $false
}

return $retVal