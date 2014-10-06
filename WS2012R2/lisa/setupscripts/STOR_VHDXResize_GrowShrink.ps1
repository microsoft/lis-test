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
    Verify basic VHDx Hard Disk resizing(increase and then shrink).
.Description
    This is a PowerShell test case script that implements Dynamic
    Resizing of VHDX.
    Ensures that the VM sees the newly attached VHDx Hard Disk
    Creates partitions, filesytem, mounts partitions, sees if it can perform
    Read/Write operations on the newly created partitions and deletes partitions

    A typical test case definition for this test script would look
    similar to the following:
        <test>
            <testName>ResizeVHDXGrowShrink</testName>
            <testScript>SetupScripts\STOR_VHDXResize_GrowShrink.ps1</testScript>
            <setupScript>SetupScripts\Add-VhdxHardDisk.ps1</setupScript>
            <cleanupScript>SetupScripts\Remove-VhdxHardDisk.ps1</cleanupScript>
            <timeout>600</timeout>
            <onError>Continue</onError>
            <testparams>
                <param>SCSI=0,0,Dynamic,512</param>
                <param>shrinkSize=3GB</param>
                <param>growSize=4GB</param>
                <param>TC_COVERED=STOR-VHDx-01</param>
            </testparams>
        </test>
.Parameter vmName
    Name of the VM to attached and resize the VHDx Hard Disk.
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
.Parameter testParams
    Test data for this test case
.Example
    setupScripts\STOR_VHDXResize_GrowShrink.ps1 -vmName "VM_Name" -hvServer "HYPERV_SERVER" -TestParams "ipv4=255.255.255.255;sshKey=YOUR_KEY.ppk;growSize=4GB;shrinkSize=3GB;TC_COVERED=STOR-VHDx-01"
#>

param( [String] $vmName,
       [String] $hvServer,
       [String] $testParams
)

$sshKey     = $null
$ipv4       = $null
$newGrowSize    = $null
$newShrinkSize    = $null
$rootDir    = $null
$TC_COVERED = $null
$TestLogDir = $null
$TestName   = $null

#######################################################################
#
# Main script body
#
#######################################################################

#
# Make sure the required arguments were passed
#
if (-not $vmName)
{
    "Error: no VMName was specified"
    return $False
}

if (-not $hvServer)
{
    "Error: No hvServer was specified"
    return $False
}

if (-not $testParams)
{
    "Error: No test parameters specified"
    return $False
}

#
# Debug - display the test parameters so they are captured in the log file
#
Write-Output "TestParams : '${testParams}'"

$summaryLog  = "${vmName}_summary.log"
Del $summaryLog -ErrorAction SilentlyContinue

#
# Parse the test parameters
#
$params = $testParams.TrimEnd(";").Split(";")

foreach ($p in $params)
{
    $fields = $p.Split("=")

    switch ($fields[0].Trim())
    {
    "SSHKey"    { $sshKey  = $fields[1].Trim() }
    "ipv4"      { $ipv4    = $fields[1].Trim() }
    "growSize"  { $newGrowSize = $fields[1].Trim() }
    "shrinkSize"       { $newShrinkSize = $fields[1].Trim() }
    "rootDIR"   { $rootDir = $fields[1].Trim() }
    "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    "TestLogDir" { $TestLogDir = $fields[1].Trim() }
    "TestName"   { $TestName = $fields[1].Trim() }
    default     {}  # unknown param - just ignore it
    }
}

# Source STOR_VHDXResize_Utils.ps1
if (Test-Path ".\setupScripts\STOR_VHDXResize_Utils.ps1")
{
    . .\setupScripts\STOR_VHDXResize_Utils.ps1
}
else
{
    "Error: Could not find setupScripts\STOR_VHDXResize_Utils.ps1"
    return $false
}

if (-not $rootDir)
{
    "Warn : no rootdir was specified"
}
else
{
    cd $rootDir
}

Write-Output "Covers: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Convert the new size
#
$newVhdxGrowSize = ConvertStringToUInt64 $newGrowSize
$newVhdxShrinkSize = ConvertStringToUInt64 $newShrinkSize

#
# Make sure the VM has a SCSI 0 controller, and that
# Lun 0 on the controller has a .vhdx file attached.
#
"Info : Check if VM ${vmName} has a SCSI 0 Lun 0 drive"
$scsi00 = Get-VMHardDiskDrive -VMName $vmName -Controllertype SCSI -ControllerNumber 0 -ControllerLocation 0 -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $scsi00)
{
    "Error: VM ${vmName} does not have a SCSI 0 Lun 0 drive"
    $error[0].Exception.Message
    return $False
}

"Info : Check if the virtual disk file exists"
$vhdPath = $scsi00.Path
$vhdxInfo = GetRemoteFileInfo $vhdPath $hvServer
if (-not $vhdxInfo)
{
    "Error: The vhdx file (${vhdPath} does not exist on server ${hvServer}"
    return $False
}

"Info : Verify the file is a .vhdx"
if (-not $vhdPath.EndsWith(".vhdx") -and -not $vhdPath.EndsWith(".avhdx"))
{
    "Error: SCSI 0 Lun 0 virtual disk is not a .vhdx file."
    "       Path = ${vhdPath}"
    return $False
}

#
# Make sure there is sufficient disk space to grow the VHDX to the specified size
#
$deviceID = $vhdxInfo.Drive
$diskInfo = Get-WmiObject -Query "SELECT * FROM Win32_LogicalDisk Where DeviceID = '${deviceID}'"
if (-not $diskInfo)
{
    "Error: Unable to collect information on drive ${deviceID}"
    return $False
}

if ($diskInfo.FreeSpace -le $newVhdxSize + 10MB)
{
    "Error: Insufficent disk free space"
    "       This test case requires ${newSize} free"
    "       Current free space is $($diskInfo.FreeSpace)"
    return $False
}

#
# Make sure if we can perform Read/Write operations on the guest VM
#
$guest_script = "STOR_VHDXResize_PartitionDisk"

$sts = RunTest $guest_script
if (-not $($sts[-1]))
{
    $sts = SummaryLog
	if (-not $($sts[-1]))
	{
		"Warning : Failed getting summary.log from VM"
	}
    "Error: Running '${guest_script}' script failed on VM "
    return $False
}

$CheckResultsts = CheckResult

$sts = RunTestLog $guest_script $TestLogDir $TestName
if (-not $($sts[-1]))
{
    "Warning : Getting RunTestLog.log from VM, will not exit test case execution "
}

if (-not $($CheckResultsts[-1]))
{
    "Error: Running '${guest_script}'script failed on VM. check VM logs , exiting test case execution "
    return $False
}

"Info : Growing the VHDX to ${growSize}"
Resize-VHD -Path $vhdPath -SizeBytes ($newVhdxGrowSize) -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $?)
{
   "Error: Unable to grow VHDX file '${vhdPath}"
   return $False
}

#
# Let system have some time for the volume change to be indicated
#
$sleepTime = 60
Start-Sleep -s $sleepTime

#
# Check if the guest sees the added space
#
"Info : Check if the guest sees the new space"
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "echo 1 > /sys/block/sdb/device/rescan"
if (-not $?)
{
    "Error: Failed to force SCSI device rescan"
    return $False
}

$growDiskSize = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "fdisk -l /dev/sdb  2> /dev/null | grep Disk | grep sdb | cut -f 5 -d ' '"
if (-not $?)
{
    "Error: Unable to determine disk size from within the guest after growing the VHDX"
    return $False
}

if ($growDiskSize -ne $newVhdxGrowSize)
{
    "Error: VM ${vmName} sees a disk size of ${diskSize}, not the expected size of ${newVhdxGrowSize}"
    return $False
}

#
# Make sure if we can perform Read/Write operations on the guest VM
#
$guest_script = "STOR_VHDXResize_PartitionDiskAfterResize"

$sts = RunTest $guest_script
if (-not $($sts[-1]))
{
    $sts = SummaryLog
	if (-not $($sts[-1]))
	{
		"Warning : Failed getting summary.log from VM"
	}
    "Error: Running '${guest_script}' script failed on VM "
    return $False
}

$CheckResultsts = CheckResult

$sts = RunTestLog $guest_script $TestLogDir $TestName
if (-not $($sts[-1]))
{
    "Warning : Getting RunTestLog.log from VM, will not exit test case execution "
}

if (-not $($CheckResultsts[-1]))
{
    "Error: Running '${guest_script}'script failed on VM. check VM logs , exiting test case execution "
    return $False
}

"Info : Shrinking the VHDX to ${shrinkSize}"
Resize-VHD -Path $vhdPath -SizeBytes ($newVhdxShrinkSize) -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $?)
{
   "Error: Unable to shrink VHDX file '${vhdPath}"
   return $False
}

#
# Let system have some time for the volume change to be indicated
#
$sleepTime = 60
Start-Sleep -s $sleepTime

#
# Check if the guest sees the added space
#
"Info : Check if the guest sees the new size"
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "echo 1 > /sys/block/sdb/device/rescan"
if (-not $?)
{
    "Error: Failed to force SCSI device rescan"
    return $False
}

$shrinkDiskSize = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "fdisk -l /dev/sdb  2> /dev/null | grep Disk | grep sdb | cut -f 5 -d ' '"
if (-not $?)
{
    "Error: Unable to determine disk size from within the guest after shrinking the VHDX"
    return $False
}

if ($shrinkDiskSize -ne $newVhdxShrinkSize)
{
    "Error: VM ${vmName} sees a disk size of ${diskSize}, not the expected size of ${newVhdxShrinkSize}"
    return $False
}

#
# Make sure if we can perform Read/Write operations on the guest VM
#
$guest_script = "STOR_VHDXResize_PartitionDiskAfterShrink"

$sts = RunTest $guest_script
if (-not $($sts[-1]))
{
    $sts = SummaryLog
	if (-not $($sts[-1]))
	{
		"Warning : Failed getting summary.log from VM"
	}
    "Error: Running '${guest_script}' script failed on VM "
    return $False
}

$CheckResultsts = CheckResult

$sts = RunTestLog $guest_script $TestLogDir $TestName
if (-not $($sts[-1]))
{
    "Warning : Getting RunTestLog.log from VM, will not exit test case execution "
}

if (-not $($CheckResultsts[-1]))
{
    "Error: Running '${guest_script}'script failed on VM. check VM logs , exiting test case execution "
    return $False
}

"Info : The guest sees the new grow size ($growDiskSize) and the new shrink size ($shrinkDiskSize)"
"Info : VHDx Resize - ${TC_COVERED} is Done"

return $True
