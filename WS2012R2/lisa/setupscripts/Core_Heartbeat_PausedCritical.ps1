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
 Description:
   This script tests the VMs Heartbeat after the VM enters in PausedCritical state.
   For the VM to enter in PausedCritical state the disk where the VHD is has to be full.
   We create a new partition, copy the VHD and fill up the partition.
   After the VM enters in PausedCritical state we free some space and the VM
   should return to normal OK Heartbeat.

   .Parameter vmName
    Name of the VM to configure.
    .Parameter hvServer
    Name of the Hyper-V server hosting the VM.
    .Parameter testParams
    Test data for this test case
    .Example
    setupScripts\PausedCritical.ps1 -vmName vm -hvServer localhost -testParams "sshkey=linux_id_rsa;"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$ipv4vm1 = $null
$vm_gen = $null
$retVal = $true
$foundName = $false
$driveletter = $null

# Check input arguments
if ($vmName -eq $null)
{
    "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null)
{
    "Error: hvServer is null"
    return $retVal
}

$params = $testParams.Split(';')
foreach ($p in $params)
{
  $fields = $p.Split("=")

  switch ($fields[0].Trim())
    {
    "sshKey" { $sshKey  = $fields[1].Trim() }
    "ipv4"   { $ipv4    = $fields[1].Trim() }
    "rootDir" { $rootDir = $fields[1].Trim() }
    "TC_COVERED" { $tcCovered = $fields[1].Trim() }
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

# Change the working directory to where we need to be
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

cd $rootDir

# Delete any previous summary.log file, then create a new one
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${tcCovered}" | Tee-Object -Append -file $summaryLog

#######################################################################
#
# Main script body
#
#######################################################################
# Source the TCUtils.ps1 file
. .\setupscripts\TCUtils.ps1

# Check host version and skipp TC in case of WS2012 or older
$hostVersion = GetHostBuildNumber $hvServer
if ($hostVersion -le 9200) {
    Write-Output "Info: Host is WS2012 or older. Skipping test case." | Tee-Object -Append -file $summaryLog
    return $Skipped
}

# check what drive letter is available and pick one randomly
$driveletter = ls function:[g-y]: -n | ?{ !(test-path $_) } | random

if ([string]::IsNullOrEmpty($driveletter)) {
    Write-Host "Error: The driveletter variable is empty!"
    exit 1
} else {
    Write-Output "The drive letter of test volume is $driveletter" | Tee-Object -Append -file $summaryLog
}

# Shutdown gracefully so we dont corrupt VHD
Stop-VM -Name $vmName -ComputerName $hvServer
if (-not $?)
{
    Write-Output "Error: Unable to Shut Down VM" | Tee-Object -Append -file $summaryLog
    return $False
}

# Get Parent VHD
$ParentVHD = GetParentVHD $vmName $hvServer
if(-not $ParentVHD) {
    Write-Output "Error getting Parent VHD of VM $vmName" | Tee-Object -Append -file $summaryLog
    return $False
}

# Get VHD size
$VHDSize = (Get-VHD -Path $ParentVHD -ComputerName $hvServer).FileSize
# [uint64]$newsize = [math]::round($VHDSize /1Gb, 1)

$baseVhdPath = $(Get-VMHost).VirtualHardDiskPath
if (-not $baseVhdPath.EndsWith("\")) {
    $baseVhdPath += "\"
}

$newsize = ($VHDSize + 1GB)

# Check if VHD path exists and is being used by another process
while(-not $foundName) {
    $vhdName = $(-join ((48..57) + (97..122) | Get-Random -Count 10 | % {[char]$_}))
    $vhdpath = "${baseVhdPath}${vhdName}.vhdx"
    if(Test-Path $vhdpath) {   
        try {
            [IO.File]::OpenWrite($file).close()
            Write-Host "Deleting existing VHD $vhdpath"
            del $vhdpath
            $foundName = $true
        } catch {
            $foundName = $false
        }
    } else {
        $foundName = $true
    }
}

Get-Partition -DriveLetter $driveletter[0] -ErrorAction SilentlyContinue
if ($?)
{
    Dismount-VHD -Path $vhdpath -ComputerName $hvServer -ErrorAction SilentlyContinue 
}

# Create the new partition
New-VHD -Path $vhdpath -Dynamic -SizeBytes $newsize -ComputerName $hvServer | Mount-VHD -Passthru | Initialize-Disk -Passthru |
New-Partition -DriveLetter $driveletter[0] -UseMaximumSize | Format-Volume -FileSystem NTFS -Confirm:$false -Force
if (-not $?)
{
    Write-Output "Error: Failed to create the new partition $driveletter" | Tee-Object -Append -file $summaryLog
    return $False
}

"hvServer=$hvServer" | Out-File './heartbeat_params.info'
$test_vhd = [regex]::escape($vhdpath)
"test_vhd=$test_vhd" | Out-File './heartbeat_params.info' -Append
# Copy parent VHD to partition
# this will be appended the .vhd or .vhdx file extension
$ChildVHD = CreateChildVHD $ParentVHD $driveletter\child_disk $hvServer
if(-not $ChildVHD)
{
    Write-Output "Error: Creating Child VHD of VM $vmName" | Tee-Object -Append -file $summaryLog
    return $False
}
$child_vhd = [regex]::escape($ChildVHD)
"child_vhd=$child_vhd" | Out-File "./heartbeat_params.info" -Append

# Get the VM Network adapter so we can attach it to the new VM
$VMNetAdapter = Get-VMNetworkAdapter $vmName -ComputerName $hvServer
if (-not $?)
{
    Write-Output "Error: Failed to run Get-VMNetworkAdapter to obtain the source VM configuration" | Tee-Object -Append -file $summaryLog
    return $false
}

#Get VM Generation
$vm_gen = GetVMGeneration $vmName $hvServer

$vmName1 = "${vmName}_ChildVM"
# Remove old VM
if ( Get-VM $vmName1 -ComputerName $hvServer -ErrorAction SilentlyContinue ) {
    Remove-VM -Name $vmName1 -ComputerName $hvServer -Confirm:$false -Force
}

# Create the ChildVM
New-VM -Name $vmName1 -ComputerName $hvServer -VHDPath $ChildVHD -MemoryStartupBytes 2048MB -SwitchName $VMNetAdapter[0].SwitchName -Generation $vm_gen
if (-not $?)
{
   Write-Output "Error: Creating new VM $vmName1 failed!" | Tee-Object -Append -file $summaryLog
   return $False
}
"vm_name=$vmName1" | Out-File './heartbeat_params.info' -Append
# Disable secure boot
if ($vm_gen -eq 2)
{
    Set-VMFirmware -VMName $vmName1 -ComputerName $hvServer -EnableSecureBoot Off
    if(-not $?)
    {
        Write-Output "Error: Unable to disable secure boot!" | Tee-Object -Append -file $summaryLog
        return $false
    }
}

Write-Output "Info: Child VM $vmName1 created"

$timeout = 300
$sts = Start-VM -Name $vmName1 -ComputerName $hvServer
if (-not (WaitForVMToStartKVP $vmName1 $hvServer $timeout ))
{
    Write-Output "Error: ${vmName1} failed to start" | Tee-Object -Append -file $summaryLog
    return $False
}
Write-Output "Info: New VM $vmName1 started"

# Get the VM1 ip
$ipv4vm1 = GetIPv4 $vmName1 $hvServer
Start-Sleep 15

# Get partition size
$disk = Get-WmiObject Win32_LogicalDisk -ComputerName $hvServer -Filter "DeviceID='${driveletter}'" | Select-Object FreeSpace

# Leave 52428800 bytes (50 MB) of free space after filling the partition
$filesize = $disk.FreeSpace - 52428800
$file_path_formatted = $driveletter[0] + '$\' + 'testfile'

# Fill up the partition
$createfile = fsutil file createnew \\$hvServer\$file_path_formatted $filesize
if ($createfile -notlike "File *testfile* is created")
{
    Write-Output "Error: Could not create the sample test file in the working directory! $file_path_formatted" | Tee-Object -Append -file $summaryLog
    return $False
}
Write-Output "Info: Created test file on \\$hvServer\$file_path_formatted with the size $filesize"
Write-Output "Info: Writing data on the VM disk in order to hit the disk limit"

# Get the used space reported by the VM on the root partition
$usedSpaceVM = .\bin\plink.exe -i ssh\$sshKey root@$ipv4vm1 "df -B1 | grep '[A-Za-z]*root'| awk '/root/ {print `$3}'"
if (-not $usedSpaceVM) {
    # If the used space cannot be found using the above query, try searching for sda2 disk
    $usedSpaceVM = (.\bin\plink.exe -i ssh\$sshKey root@$ipv4vm1 "df -B1| grep 'sda2'| awk '{print `$3}'")[0]
}
# Divide by 1 to convert string to double
$usedSpaceVM = ($usedSpaceVM/1)
$vmFileSize = ($VHDSize - $usedSpaceVM)
$ddFileSize = [math]::Round($vmFileSize/1MB) #The value supplied to dd command has to be in MB

if ($ddFileSize -le 0) {
    Write-Output "Warning: The difference between the created partition size and the used VM space is negative."
    # If the number is negative, convert it to possitive and if it is a one or two digit number use the filesize value
    $ddFileSize = $ddFileSize * -1
    if ($ddFileSize.length -eq 1 -or $ddFileSize.length -eq 2) {
        $ddFileSize = $filesize
    }
}

Write-Output "Info: Filling $vmName with $ddFileSize MB of data."
SendCommandToVM $ipv4vm1 $sshKey "nohup dd if=/dev/urandom of=/root/data2 bs=1M count=$ddFileSize &>/dev/null &"
if ($? -ne "True") {
    Write-Output "Error: Unable to send dd command to $vmName ."
}
Start-Sleep 90

$vm1 = Get-VM -Name $vmName1 -ComputerName $hvServer
if ($vm1.State -ne "PausedCritical")
{
    Write-Output "Error: VM $vmName1 is not in Paused-Critical after we filled the disk" | Tee-Object -Append -file $summaryLog
    return $False
}
Write-Output "Info: VM $vmName1 entered in Paused-Critical state, as expected." | Tee-Object -Append -file $summaryLog

# Create space on partition
Remove-Item -Path \\$hvServer\$file_path_formatted -Force
if (-not $?) {
    Write-Output "ERROR: Cannot remove the test file '${testfile1}'!" | Tee-Object -Append -file $summaryLog
    return $False
}
Write-Output "Info: Test file deleted from mounted VHDx"

# Resume VM after we created space on the partition
Resume-VM -Name $vmName1 -ComputerName $hvServer
if (-not $?)
{
    Write-Output "Error: Failed to resume the vm $vmName1" | Tee-Object -Append -file $summaryLog
}

# Check Heartbeat
Start-Sleep 5
if ($vm1.Heartbeat -eq "OkApplicationsUnknown")
{
    "Info: Heartbeat detected, status OK."
    Write-Output "Info: Test Passed. Heartbeat is again reported as OK." | Tee-Object -Append -file $summaryLog
    return $true
}
else
{
    Write-Output "Error: Heartbeat is not in the OK state." | Out-File -Append $summaryLog
    return $False
}
