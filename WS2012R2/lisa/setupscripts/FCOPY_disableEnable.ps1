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
 This script tests the file copy functionality after a cycle of disable and
 enable of the Guest Service Integration.

.Description
 This script will disable and reenable Guest Service Interface for a number
 of times, it will check the service and daemon integrity and if everything is
 fine it will copy a 5GB large file from host to guest and then check if the size
 is matching.

 A typical XML definition for this test case would look similar to the following:

        <test>
            <testName>FCOPY_disableEnable</testName>
            <setupScript>setupScripts\Add-VHDXForResize.ps1</setupScript>
            <testScript>setupscripts\FCOPY_disableEnable.ps1</testScript>
            <cleanupScript>SetupScripts\Remove-VHDXHardDisk.ps1</cleanupScript>
            <files>remote-scripts\ica\utils.sh,remote-scripts\ica\check_traces.sh</files>
            <timeout>1200</timeout>
            <testParams>
                <param>TC_COVERED=FCopy-99</param>
                <param>Type=Fixed</param>
                <param>SectorSize=512</param>
                <param>DefaultSize=7GB</param>
                <param>ControllerType=SCSI</param>
                <param>FcopyFileSize=5GB</param>
                <param>CycleCount=20</param>
            </testParams>
            <noReboot>False</noReboot>
        </test>

.Parameter vmName
 Name of the VM to test.

.Parameter hvServer
 Name of the Hyper-V server hosting the VM.

.Parameter testParams
 Test data for this test case

.Example
 setupScripts\FCOPY_disableEnable.ps1 -vmName NameOfVm -hvServer localhost -testParams 'sshKey=path/to/ssh;ipv4=ipaddress'
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

function Mount-Disk()
{

    $driveName = "/dev/sdb"

    $sts = SendCommandToVM $ipv4 $sshKey "(echo d;echo;echo w)|fdisk ${driveName}"
    if (-not $sts) {
        Write-Output "ERROR: Failed to format the disk in the VM $vmName."
        return $Failed
    }

    $sts = SendCommandToVM $ipv4 $sshKey "(echo n;echo p;echo 1;echo;echo;echo w)|fdisk ${driveName}"
    if (-not $sts) {
        Write-Output "ERROR: Failed to format the disk in the VM $vmName."
        return $Failed
    }

    $sts = SendCommandToVM $ipv4 $sshKey "mkfs.ext4 ${driveName}1"
    if (-not $sts) {
        Write-Output "ERROR: Failed to make file system in the VM $vmName."
        return $Failed
    }

    $sts = SendCommandToVM $ipv4 $sshKey "mount ${driveName}1 /mnt"
    if (-not $sts) {
        Write-Output "ERROR: Failed to mount the disk in the VM $vmName."
        return $Failed
    }

    "Info: $driveName has been mounted to /mnt in the VM $vmName."

    return $True
}

function Check-Systemd()
{
    $check1 = $true
    $check2 = $true
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "ls -l /sbin/init | grep systemd"
    if ($? -ne "True"){
        Write-Output "Systemd not found on VM"
        $check1 = $false
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "systemd-analyze --help"
    if ($? -ne "True"){
        Write-Output "Systemd-analyze not present on VM."
        $check2 = $false
    }

    if (($check1 -and $check2) -eq $true) {
        return $true
    } else {
        return $Failed
    }
}

# Read parameters
$params = $testParams.TrimEnd(";").Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")
    $value = $fields[1].Trim()

    switch ($fields[0].Trim()) {
        "sshKey"    { $sshKey  = $fields[1].Trim() }
        "ipv4"      { $ipv4    = $fields[1].Trim() }
        "rootDIR"   { $rootDir = $fields[1].Trim() }
        "DefaultSize"   { $DefaultSize = $fields[1].Trim() }
        "TC_COVERED"    { $TC_COVERED = $fields[1].Trim() }
        "Type"          { $Type = $fields[1].Trim() }
        "SectorSize"    { $SectorSize = $fields[1].Trim() }
        "ControllerType"{ $controllerType = $fields[1].Trim() }
        "CycleCount"    { $CycleCount = $fields[1].Trim() }
        "FcopyFileSize" { $FcopyFileSize = $fields[1].Trim() }
        default     {}  # unknown param - just ignore it
    }
}

# Main script body

# Validate parameters
if (-not $vmName) {
    Write-Output "Error: VM name is null!"
    return $Failed
}

if (-not $hvServer) {
    Write-Output "Error: hvServer is null!"
    return $Failed
}

if (-not $testParams) {
    Write-Output"Error: No testParams provided!"
    return $Failed
}

# Change directory
cd $rootDir

# Source TCUtils.ps1
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
} else {
    "Error: Could not find setupScripts\TCUtils.ps1"
}

# if host build number lower than 9600, skip test
$BuildNumber = GetHostBuildNumber $hvServer
if ($BuildNumber -eq 0)
{
    return $Failed
}
elseif ($BuildNumber -lt 9600)
{
    return $Skipped
}

# Create log file
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Delete previous summary on the VM
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "rm -rf ~/summary.log"

# Check VM state
$currentState = CheckVMState $vmName $hvServer
if ($? -ne "True") {
    Write-Output "Error: Cannot check VM state" | Tee-Object -Append -file $summaryLog
    return $Failed
}

# If the VM is in any state other than running power it ON
if ($currentState -ne "Running") {
    Write-Output "Found $vmName in $currentState state. Powering ON ... " | Tee-Object -Append -file $summaryLog
    Start-VM $vmName
    if ($? -ne "True") {
        Write-Output "Error: Unable to Power ON the VM" | Tee-Object -Append -file $summaryLog
        return $Failed
    }
    Start-Sleep 60
}

$checkVM = Check-Systemd
if ($checkVM -eq "True") {

    # Get Integration Services status
    $gsi = Get-VMIntegrationService -vmName $vmName -ComputerName $hvServer -Name "Guest Service Interface"
    if ($? -ne "True") {
            Write-Output "Error: Unable to run Get-VMIntegrationService on $vmName ($hvServer)" | Tee-Object -Append -file $summaryLog
            return $Failed
    }

    # If guest services are not enabled, enable them
    if ($gsi.Enabled -ne "True") {
        Enable-VMIntegrationService -Name "Guest Service Interface" -vmName $vmName -ComputerName $hvServer
        if ($? -ne "True") {
            Write-Output "Error: Unable to enable VMIntegrationService on $vmName ($hvServer)" | Tee-Object -Append -file $summaryLog
            return $Failed
        }
    }

    # Disable and Enable Guest Service according to the given parameter
    $counter = 0
    while ($counter -lt $CycleCount) {
        Disable-VMIntegrationService -Name "Guest Service Interface" -vmName $vmName -ComputerName $hvServer
        if ($? -ne "True") {
            Write-Output "Error: Unable to disable VMIntegrationService on $vmName ($hvServer) on $counter run" | Tee-Object -Append -file $summaryLog
            return $Failed
        }
        Start-Sleep 5

        Enable-VMIntegrationService -Name "Guest Service Interface" -vmName $vmName -ComputerName $hvServer
        if ($? -ne "True") {
            Write-Output "Error: Unable to enable VMIntegrationService on $vmName ($hvServer) on $counter run" | Tee-Object -Append -file $summaryLog
            return $Failed
        }
        Start-Sleep 5
        $counter += 1
    }

    Write-Output "Disabled and Enabled Guest Services $counter times" | Tee-Object -Append -file $summaryLog

    # Get VHD path of tested server; file will be copied there
    $hvPath = Get-VMHost -ComputerName $hvServer | Select -ExpandProperty VirtualHardDiskPath
    if ($? -ne "True") {
        Write-Output "Error: Unable to get VM host" | Tee-Object -Append -file $summaryLog
        return $Failed
    }

    # Fix path format if it's broken
    if ($hvPath.Substring($hvPath.Length - 1, 1) -ne "\") {
        $hvPath = $hvPath + "\"
    }

    $hvPathFormatted = $hvPath.Replace(':','$')

    # Define the file-name to use with the current time-stamp
    $testfile = "testfile-$(get-date -uformat '%H-%M-%S-%Y-%m-%d').file"
    $filePath = $hvPath + $testfile
    $filePathFormatted = $hvPathFormatted + $testfile

    # Make sure the fcopy daemon is running and Integration Services are OK
    $timer = 0
    while ((Get-VMIntegrationService $vmName | ?{$_.name -eq "Guest Service Interface"}).PrimaryStatusDescription -ne "OK")
    {
        Start-Sleep -Seconds 5
        Write-Output "Waiting for VM Integration Services $timer"
        $timer += 1
        if ($timer -gt 20) {
            break
        }
    }

    $operStatus = (Get-VMIntegrationService -vmName $vmName -ComputerName $hvServer -Name "Guest Service Interface").PrimaryStatusDescription
    Write-Output "Current Integration Services PrimaryStatusDescription is: $operStatus"
    if ($operStatus -ne "Ok") {
        Write-Output "Error: The Guest services are not working properly for VM $vmName!" | Tee-Object -Append -file $summaryLog
        return $Failed
    }
    else {
        . .\setupscripts\STOR_VHDXResize_Utils.ps1
        $fileToCopySize = ConvertStringToUInt64 $FcopyFileSize

        # Create a 5GB sample file
        $createFile = fsutil.exe file createnew \\$hvServer\$filePathFormatted $fileToCopySize
        if ($createFile -notlike "File *testfile-*.file is created") {
            Write-Output "Error: Could not create the sample test file in the working directory!" | Tee-Object -Append -file $summaryLog
            return $Failed
        }
    }

    # Mount attached VHDX
    $sts = Mount-Disk
    if (-not $sts[-1]) {
        Write-Output "Error: Failed to mount the disk in the VM." | Tee-Object -Append -file $summaryLog
        return $Failed
    }

    # Daemon name might vary. Get the correct daemon name based on systemctl output
    $daemonName = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "systemctl list-unit-files | grep fcopy"
    $daemonName = $daemonName.Split(".")[0]

    $checkProcess = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "systemctl is-active $daemonName"
    if ($checkProcess -ne "active") {
         Write-Output "Warning: $daemonName was not automatically started by systemd. Will start it manually." | Tee-Object -Append -file $summaryLog
         $startProcess = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "systemctl start $daemonName"
    }

    $gsi = Get-VMIntegrationService -vmName $vmName -ComputerName $hvServer -Name "Guest Service Interface"
    if ($gsi.Enabled -ne "True") {
        Write-Output "Error: FCopy Integration Service is not enabled" | Tee-Object -Append -file $summaryLog
        return $Failed
    }

    # Check for the file to be copied
    Test-Path $filePathFormatted
    if ($? -ne "True") {
        Write-Output "Error: File to be copied not found." | Tee-Object -Append -file $summaryLog
        return $Failed
    }

    $Error.Clear()
    $copyDuration = (Measure-Command { Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $filePath -DestinationPath `
        "/mnt/" -FileSource host -ErrorAction SilentlyContinue }).totalseconds

    if ($Error.Count -eq 0) {
        Write-Output "Info: File has been successfully copied to guest VM '${vmName}'" | Tee-Object -Append -file $summaryLog
    } else {
        Write-Output "Error: File could not be copied!" | Tee-Object -Append -file $summaryLog
        return $Failed
    }

    [int]$copyDuration = [math]::floor($copyDuration)
    Write-Output "Info: The file copy process took ${copyDuration} seconds" | Tee-Object -Append -file $summaryLog

    # Checking if the file is present on the guest and file size is matching
    $sts = CheckFile /mnt/$testfile
    if (-not $sts[-1]) {
        Write-Output "Error: File is not present on the guest VM" | Tee-Object -Append -file $summaryLog
        return $Failed
    }
    elseif ($sts[0] -eq $fileToCopySize) {
        Write-Output "Info: The file copied matches the $FcopyFileSize size." | Tee-Object -Append -file $summaryLog
        return $true
    }
    else {
        Write-Output "Error: The file copied doesn't match the $FcopyFileSize size!" | Tee-Object -Append -file $summaryLog
        return $Failed
    }

    # Removing the temporary test file
    Remove-Item -Path \\$hvServer\$filePathFormatted -Force
    if (-not $?) {
        Write-Output "Error: Cannot remove the test file '${testfile}'!" | Tee-Object -Append -file $summaryLog
        return $Failed
    }

    # Check if there were call traces during the test
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix -q check_traces.sh"
    if (-not $?) {
        Write-Output "Error: Unable to run dos2unix on check_traces.sh" | Tee-Object -Append -file $summaryLog
    }
    $sts = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "echo 'sleep 5 && bash ~/check_traces.sh ~/check_traces.log &' > runtest.sh"
    $sts = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "chmod +x ~/runtest.sh"
    $sts = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "./runtest.sh > check_traces.log 2>&1"
    Start-Sleep 6
    $sts = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "cat ~/check_traces.log | grep ERROR"
    if ($sts.Contains("ERROR")) {
       Write-Output "Warning: Call traces have been found on VM" | Tee-Object -Append -file $summaryLog
    }
    if ($sts -eq $NULL) {
        Write-Output "Info: No Call traces have been found on VM" | Tee-Object -Append -file $summaryLog
    }
    return $Passed
}
else {
    Write-Output "Systemd is not being used. Test Skipped" | Tee-Object -Append -file $summaryLog
    return $Skipped
}
