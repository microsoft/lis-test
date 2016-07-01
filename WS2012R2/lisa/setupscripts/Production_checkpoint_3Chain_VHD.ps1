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

<#
.Synopsis
    Verify Production Checkpoint feature.

.Description
    This script will create a new VM with a 3-chained differencing disk 
    attached based on the source vm vhd/x. 
    If the source Vm has more than 1 snapshot, they will be removed except
    the latest one. If the VM has no snapshots, the script will create one.
    After that it will proceed with making a Production Checkpoint on the
    new VM.

    A typical test case definition for this test script would look
    similar to the following:
        <test>
            <testName>ProductionCheckpoint_3Chain_VHD</testName>
            <setupScript>setupscripts\RevertSnapshot.ps1</setupScript>
            <testScript>setupscripts\Production_checkpoint_3Chain_VHD.ps1</testScript> 
            <testParams>
                <param>TC_COVERED=PC-09</param>
                <param>snapshotName=ICABase</param>
            </testParams>
            <timeout>2400</timeout>
            <OnError>Continue</OnError>
        </test>

.Parameter vmName
    Name of the VM to perform the test with.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.

.Example
    setupScripts\Production_checkpoint_3Chain_VHD.ps1 -vmName "myVm" -hvServer "localhost"
     -TestParams "TC_COVERED=PC-09;snapshotname=ICABase"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

#######################################################################
# Runs a remote script on the VM an returns the log.
#######################################################################
function RunRemoteScript($remoteScript)
{
    $retValue = $False
    $stateFile     = "state.txt"
    $TestCompleted = "TestCompleted"
    $TestAborted   = "TestAborted"
    $TestRunning   = "TestRunning"
    $timeout       = 6000

    "./${remoteScript} > ${remoteScript}.log" | out-file -encoding ASCII -filepath runtest.sh

    .\bin\pscp -i ssh\${sshKey} .\runtest.sh root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy runtest.sh to the VM"
       return $False
    }

    .\bin\pscp -i ssh\${sshKey} .\remote-scripts\ica\${remoteScript} root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy ${remoteScript} to the VM"
       return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix ${remoteScript} 2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to run dos2unix on ${remoteScript}"
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to run dos2unix on runtest.sh"
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x ${remoteScript}   2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to chmod +x ${remoteScript}"
        return $False
    }
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to chmod +x runtest.sh " -
        return $False
    }

    # Run the script on the vm
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "./runtest.sh"

    # Return the state file
    while ($timeout -ne 0 )
    {
    .\bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${stateFile} . #| out-null
    $sts = $?
    if ($sts)
    {
        if (test-path $stateFile)
        {
            $contents = Get-Content -Path $stateFile
            if ($null -ne $contents)
            {
                    if ($contents -eq $TestCompleted)
                    {
                        Write-Output "Info : state file contains Testcompleted"
                        $retValue = $True
                        break

                    }

                    if ($contents -eq $TestAborted)
                    {
                         Write-Output "Info : State file contains TestAborted failed. "
                         break

                    }
                    #Start-Sleep -s 1
                    $timeout--

                    if ($timeout -eq 0)
                    {
                        Write-Output "Error : Timed out on Test Running , Exiting test execution."
                        break
                    }

            }
            else
            {
                Write-Output "Warn : state file is empty"
                break
            }

        }
        else
        {
             Write-Host "Warn : ssh reported success, but state file was not copied"
             break
        }
    }
    else #
    {
         Write-Output "Error : pscp exit status = $sts"
         Write-Output "Error : unable to pull state.txt from VM."
         break
    }
    }

    # Get the logs
    $remoteScriptLog = $remoteScript+".log"

    bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${remoteScriptLog} .
    $sts = $?
    if ($sts)
    {
        if (test-path $remoteScriptLog)
        {
            $contents = Get-Content -Path $remoteScriptLog
            if ($null -ne $contents)
            {
                    if ($null -ne ${TestLogDir})
                    {
                        move "${remoteScriptLog}" "${TestLogDir}\${remoteScriptLog}"

                    }

                    else
                    {
                        Write-Output "INFO: $remoteScriptLog is copied in ${rootDir}"
                    }

            }
            else
            {
                Write-Output "Warn: $remoteScriptLog is empty"
            }
        }
        else
        {
             Write-Output "Warn: ssh reported success, but $remoteScriptLog file was not copied"
        }
    }

    # Cleanup
    del state.txt -ErrorAction "SilentlyContinue"
    del runtest.sh -ErrorAction "SilentlyContinue"

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
                            if ([string]::IsNullOrEmpty($Path.ParentPath))
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
                            if ([string]::IsNullOrEmpty($Path.ParentPath))
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

#######################################################################
# Create a file on the VM.
#######################################################################
function CreateFile([string] $fileName)
{
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "touch ${fileName}" 
    if (-not $?)
    {
        Write-Output "ERROR: Unable to create file" | Out-File -Append $summaryLog
        return $False
    }

    return  $True
}

#######################################################################
# Checks if test file is present or not.
#######################################################################
function CheckFile([string] $fileName)
{
    $retVal = $true
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "stat ${fileName} 2>/dev/null" | out-null
    if (-not $?)
    {
        $retVal = $false
    }

    return  $retVal
}

#######################################################################
#
# Main script body
#
#######################################################################
$retVal = $false

# Define and cleanup the summaryLog
$summaryLog  = "${vmName}_summary.log"
echo "Covers Production Checkpoint Testing" > $summaryLog

$vmNameChild = "${vmName}_ChildVM"

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
    "TC_COVERED"  { $TC_COVERED = $fields[1].Trim() }
    "sshKey"      { $sshKey = $fields[1].Trim() }
    "ipv4"        { $ipv4 = $fields[1].Trim() }
    "rootdir"     { $rootDir = $fields[1].Trim() }
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

echo $params

# Change the working directory to where we need to be
cd $rootDir

Write-output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Source the TCUtils.ps1 file
. .\setupscripts\TCUtils.ps1

#Check if the host supports production checkpoints
$osInfo = GWMI Win32_OperatingSystem -ComputerName $hvServer
if (-not $osInfo)
{
    "Error: Unable to collect Operating System information"
    return $False
}

[System.Int32]$buildNR = $osInfo.BuildNumber

if ($buildNR -le 10500){
    Write-Output "ERROR: This Windows Server version doesn't support production checkpoints"
    return $false
}

# Check if the Vm VHD in not on the same drive as the backup destination
$vm = Get-VM -Name $vmName -ComputerName $hvServer
if (-not $vm)
{
    "Error: VM '${vmName}' does not exist"
    return $False
}

# Send utils.sh to VM
echo y | .\bin\pscp -i ssh\${sshKey} .\remote-scripts\ica\utils.sh root@${ipv4}:
if (-not $?)
{
    Write-Output "ERROR: Unable to copy utils.sh to the VM"
    return $False
}

# Check to see Linux VM is running VSS backup daemon
$sts = RunRemoteScript "STOR_VSS_Check_VSS_Daemon.sh"
if (-not $sts[-1])
{
    Write-Output "ERROR executing $remoteScript on VM. Exiting test case!" >> $summaryLog
    Write-Output "ERROR: Running $remoteScript script failed on VM!"
    return $False
}

Write-Output "VSS Daemon is running " >> $summaryLog

# Stop the running VM so we can create New VM from this parent disk.
$timeout = 50
StopVMViaSSH $vmName $hvServer $timeout $sshKey

# Add Check to make sure if the VM is shutdown then Proceed
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
$ParentVHD = GetParentVHD $vmName -$hvServer
if(-not $ParentVHD)
{
    "Error: Error getting Parent VHD of VM $vmName"
    return $False
} 

Write-Output "INFO: Successfully Got Parent VHD"

# Create Child and Grand Child VHD
$CreateVHD = CreateGChildVHD $ParentVHD
if(-not $CreateVHD)
{
    Write-Output "Error: Error Creating Child and Grand Child VHD of VM $vmName"
    return $False
} 

Write-Output "INFO: Successfully Created GrandChild VHD"

# Now create New VM out of this VHD.
# New VM is static hardcoded since we do not need it to be dynamic
$GChildVHD = $CreateVHD[-1]

# Get-VM 
$vm = Get-VM -Name $vmName -ComputerName $hvServer

# Get the VM Network adapter so we can attach it to the new vm.
$VMNetAdapter = Get-VMNetworkAdapter $vmName
if (-not $?)
    {
       Write-Output "Error: Get-VMNetworkAdapter" 
       return $false
    }

# Get VM Generation
$vm_gen = $vm.Generation

# Create the GChildVM
$newVm = New-VM -Name $vmNameChild -VHDPath $GChildVHD -MemoryStartupBytes 1024MB -SwitchName $VMNetAdapter[0].SwitchName -Generation $vm_gen
if (-not $?)
    {
       Write-Output "Error: Creating New VM" 
       return $False
    }

# Disable secure boot
if ($vm_gen -eq 2)
{
    Set-VMFirmware -VMName $vmNameChild -EnableSecureBoot Off
    if(-not $?)
    {
        Write-Output "Error: Unable to disable secure boot"
        return $false
    }
}

echo "New 3 Chain VHD VM $vmNameChild Created: Success" >> $summaryLog
Write-Output "INFO: New 3 Chain VHD VM $vmNameChild Created"

$timeout = 500
$sts = Start-VM -Name $vmNameChild -ComputerName $hvServer 
if (-not (WaitForVMToStartKVP $vmNameChild $hvServer $timeout ))
{
    Write-Output "Error: ${vmNameChild} failed to start"
    return $False
}

Write-Output "INFO: New VM $vmNameChild started"

#Check if we can set the Production Checkpoint as default
$vmChild = Get-VM -Name $vmNameChild -ComputerName $hvServer
if ($vmChild.CheckpointType -ne "ProductionOnly"){
    Set-VM -Name $vmNameChild -CheckpointType ProductionOnly
    if (-not $?)
    {
       Write-Output "Error: Could not set Production as Checkpoint type"  | Out-File -Append $summaryLog
       return $false
    }
}

# Get new IPV4
$ipv4 =  GetIPv4 $vmNameChild $hvServer
if (-not $?){
    Write-Output "Error: Getting IPV4 of New VM"
    return $False
}

Write-Output "INFO: New VM's IP is $ipv4" 
echo y | .\bin\plink -i ssh\${sshKey} root@${ipv4} "exit"

# Create a file on the child VM
$sts = CreateFile "TestFile1"
if (-not $sts[-1])
{
    Write-Output "ERROR: Can not create file"
    return $False
}


# Take a Production Checkpoint
$random = Get-Random -minimum 1024 -maximum 4096
$snapshot = "TestSnapshot_$random"
Checkpoint-VM -Name $vmNameChild -SnapshotName $snapshot -ComputerName $hvServer
if (-not $?)
{
    Write-Output "Error: Could not create checkpoint" | Out-File -Append $summaryLog
    $error[0].Exception.Message
    return $False
}

# Create another file on the VM
$sts = CreateFile "TestFile2"
if (-not $sts[-1])
{
    Write-Output "ERROR: Can not create file"
    return $False
}

Restore-VMSnapshot -VMName $vmNameChild -Name $snapshot -ComputerName $hvServer -Confirm:$false
if (-not $?)
{
    Write-Output "Error: Could not restore checkpoint" | Out-File -Append $summaryLog
    $error[0].Exception.Message
    return $False
}

#
# Starting the child VM
#
$sts = Start-VM -Name $vmNameChild -ComputerName $hvServer 
if (-not (WaitForVMToStartKVP $vmNameChild $hvServer $timeout ))
{
    Write-Output "Error: ${vmNameChild} failed to start"
     return $False
}

Write-Output "INFO: New VM ${vmNameChild} started"

# Check the files created earlier. The first one should be present, the second one shouldn't
$sts = CheckFile "TestFile1"
if (-not $sts)
{
    Write-Output "ERROR: TestFile1 is not present"
    Write-Output "TestFile1 should be present on the VM" >> $summaryLog
    return $False
}

$sts = CheckFile "TestFile2"
if ($sts)
{
    Write-Output "ERROR: TestFile2 is present"
    Write-Output "TestFile2 should not be present on the VM" >> $summaryLog
    return $False
}
Write-Output "Only the first file is present. Test succeeded" >> $summaryLog

#
# Delete the snapshot
#
"Info : Deleting Snapshot ${Snapshot} of VM ${vmName}"
Remove-VMSnapshot -VMName $vmNameChild -Name $snapshot -ComputerName $hvServer
if ( -not $?)
{
   Write-Output "Error: Could not delete snapshot"  | Out-File -Append $summaryLog
}

# Stop child VM
StopVMViaSSH $vmNameChild $hvServer $timeout $sshKey

# Add Check to make sure if the VM is shutdown then Proceed
$sts = WaitForVMToStop $vmNameChild $hvServer $timeout
if (-not $sts)
{
   Write-Output "Error: Unable to Shut Down VM"
   return $False
}

# Clean Delete New VM created 
$sts = Remove-VM -Name $vmNameChild -Confirm:$false -Force
if (-not $?)
    {
      Write-Output "Error: Deleting New VM $vmNameChild"  
    } 

Write-Output "INFO: Deleted VM $vmNameChild"

return $true