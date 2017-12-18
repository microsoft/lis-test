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
    Verify basic VHDx Hard Disk resizing.
.Description
    This is a PowerShell test case script that implements Dynamic
    Resizing of VHDX test case 2.3.1 and 2.3.2.
    Ensures that the VM sees the newly attached VHDx Hard Disk
    Creates partitions, filesytem, mounts partitions, sees if it can perform
    Read/Write operations on the newly created partitions and deletes partitions
    A typical test case definition for this test script would look
    similar to the following:
        <test>
            <testName>VHDXResizeBasic</testName>
            <testScript>SetupScripts\VHDxResizeToBigger.ps1</testScript>
            <setupScript>SetupScripts\Add-VHDXHardDisk.ps1</setupScript>
            <cleanupScript>SetupScripts\Remove-VHDXHardDisk.ps1</cleanupScript>
            <timeout>600</timeout>
            <onError>Continue</onError>
            <testparams>
                <param>SCSI=0,0,Dynamic,512</param>
                <param>NewSize=4GB</param>
                <param>ControllerType=SCSI</param>
                <param>Type=Dynamic</param>
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
    setupScripts\STOR_VHDXResize_Basic.ps1 -vmName "VM-Name" -hvServer "HYPERV_SERVER" -TestParams "ipv4=255.255.255.255;sshKey=YOUR_KEY.ppk;TC_COVERED=STOR-VHDx-01"
#>

param( [String] $vmName,
       [String] $hvServer,
       [String] $testParams
)

$sshKey     = $null
$ipv4       = $null
$newSize    = $null
$sectorSize = $null
$DefaultSize = $null
$rootDir    = $null
$TC_COVERED = $null
$TestLogDir = $null
$TestName   = $null
$vhdxDrive  = $null

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
    $value = $fields[1].Trim()

    switch ($fields[0].Trim())
    {
    "SSHKey"    { $sshKey  = $fields[1].Trim() }
    "ipv4"      { $ipv4    = $fields[1].Trim() }
    "newSize"   { $newSize = $fields[1].Trim() }
    "rootDIR"   { $rootDir = $fields[1].Trim() }
    "sectorSize"   { $sectorSize = $fields[1].Trim() }
    "DefaultSize"   { $DefaultSize = $fields[1].Trim() }
    "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    "TestLogDir" { $TestLogDir = $fields[1].Trim() }
    "TestName"   { $TestName = $fields[1].Trim() }
    "ControllerType"   { $controllerType = $fields[1].Trim() }
    "Type"   { $type = $fields[1].Trim() }
    default     {}  # unknown param - just ignore it
    }
}

if (-not $rootDir)
{
    "Warn: no rootdir was specified"
}
else
{
    cd $rootDir }

# Source TCUtils.ps1
if (Test-Path ".\setupScripts\TCUtils.ps1")
{
    . .\setupScripts\TCUtils.ps1
}
else
{
    "Error: Could not find setupScripts\TCUtils.ps1" | Tee-Object -Append -file $summaryLog
    return $false
}

# if host build number lower than 9600, skip test
$BuildNumber = GetHostBuildNumber $hvServer

if ($BuildNumber -eq 0)
{
    return $false
}
elseif ($BuildNumber -lt 9600)
{
    return $Skipped
}

if ( $controllerType -eq "IDE" )
{
    $vmGeneration = GetVMGeneration $vmName $hvServer
    if ($vmGeneration -eq 2 )
    {
         Write-Output "Generation 2 VM does not support IDE disk, skip test" | Tee-Object -Append -file $summaryLog
         return $Skipped
    }
}

# Source STOR_VHDXResize_Utils.ps1
if (Test-Path ".\setupScripts\STOR_VHDXResize_Utils.ps1")
{
    . .\setupScripts\STOR_VHDXResize_Utils.ps1
}
else
{
    "Error: Could not find setupScripts\STOR_VHDXResize_Utils.ps1" | Tee-Object -Append -file $summaryLog
    return $false
}

Write-Output "Covers: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Convert the new size
#
$newVhdxSize = ConvertStringToUInt64 $newSize
$sizeFlag = ConvertStringToUInt64 "50GB"
#
# Make sure the VM has a SCSI 0 controller, and that
# Lun 0 on the controller has a .vhdx file attached.
#

"Info : Check if VM ${vmName} has a $controllerType drive"
$vhdxName = $vmName + "-" + $DefaultSize + "-" + $sectorSize + "-test"
$vhdxDisks = Get-VMHardDiskDrive -VMName $vmName -ComputerName $hvServer

foreach ($vhdx in $vhdxDisks)
{
    $vhdxPath = $vhdx.Path
    if ($vhdxPath.Contains($vhdxName))
    {
        $vhdxDrive = Get-VMHardDiskDrive -VMName $vmName -Controllertype $controllertype -ControllerNumber $vhdx.ControllerNumber -ControllerLocation $vhdx.ControllerLocation -ComputerName $hvServer -ErrorAction SilentlyContinue
    }
}
if (-not $vhdxDrive)
{
    "Error: VM ${vmName} does not have a $controllertype $vhdxDrive.ControllerNumber lun $vhdxDrive.ControllerLocation drive on ${hvServer}" | Tee-Object -Append -file $summaryLog
    $error[0].Exception.Message
    return $False
}

"Info: Check if the virtual disk file exists"
$vhdPath = $vhdxDrive.Path
$vhdxInfo = GetRemoteFileInfo $vhdPath $hvServer
if (-not $vhdxInfo)
{
    "Error: The vhdx file (${vhdPath} does not exist on server ${hvServer}" | Tee-Object -Append -file $summaryLog
    return $False
}

"Info: Verify the file is a .vhdx"
if (-not $vhdPath.EndsWith(".vhdx") -and -not $vhdPath.EndsWith(".avhdx"))
{
    "Error: $controllertype $vhdxDrive.ControllerNumber lun $vhdxDrive.ControllerLocation virtual disk is not a .vhdx file." | Tee-Object -Append -file $summaryLog
    "       Path = ${vhdPath}"
    return $False
}

#
# Make sure there is sufficient disk space to grow the VHDX to the specified size
#
$deviceID = $vhdxInfo.Drive
$diskInfo = Get-WmiObject -Query "SELECT * FROM Win32_LogicalDisk Where DeviceID = '${deviceID}'" -ComputerName $hvServer
if (-not $diskInfo)
{
    "Error: Unable to collect information on drive ${deviceID}" | Tee-Object -Append -file $summaryLog
    return $False
}

# if disk is very large, e.g. 2T with dynamic, require less disk free space
if ($diskInfo.FreeSpace -le $sizeFlag + 10MB)
{
    "Error: Insufficent disk free space" | Tee-Object -Append -file $summaryLog
    "       This test case requires ${newSize} free"
    "       Current free space is $($diskInfo.FreeSpace)"
    return $False
}

#
# Make sure if we can perform Read/Write operations on the guest VM
#

$guest_script = "STOR_VHDXResize_PartitionDisk"


$sts = RunRemoteScriptCheckResult $guest_script
if (-not $($sts[-1]))
{
  "Error: Running '${guest_script}'script failed on VM. check VM logs , exiting test case execution " | Tee-Object -Append -file $summaryLog
  return $False
}

# for IDE need to stop VM before resize

write-output "Controller type is $controllerType"
if ( $controllerType -eq "IDE" )
{
  "Info: Resize IDE disck needs to turn off VM"
  Stop-VM -VMName $vmName -ComputerName $hvServer -force
}

Resize-VHD -Path $vhdPath -SizeBytes ($newVhdxSize) -ComputerName $hvServer -ErrorAction SilentlyContinue

if (-not $?)
{
   "Error: Unable to grow VHDX file '${vhdPath}" | Tee-Object -Append -file $summaryLog
   return $False
}

# Now start the VM if IDE disk attached
if ( $controllerType -eq "IDE" )
{
  $timeout = 300
  $sts = Start-VM -Name $vmName -ComputerName $hvServer
  if (-not (WaitForVMToStartKVP $vmName $hvServer $timeout ))
  {
      Write-Output "ERROR: ${vmName} failed to start" | Tee-Object -Append -file $summaryLog
      return $False
  }
  else
  {
      Write-Output "INFO: Started VM ${vmName}"
  }

}

# check file size after resize
$vhdxInfoResize = Get-VHD -Path $vhdPath -ComputerName $hvServer -ErrorAction SilentlyContinue

if ( $newSize.contains("GB") -and $vhdxInfoResize.Size/1gb -ne $newSize.Trim("GB") )
{
  "Error: Failed to Resize Disk to new Size" | Tee-Object -Append -file $summaryLog
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
"Info: Check if the guest sees the new space"
# Older kernels might require a few requests to refresh the disks info
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "fdisk -l > /dev/null"

.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "echo 1 > /sys/block/sdb/device/rescan"
if (-not $?)
{
    "Error: Failed to force $controllerType device rescan" | Tee-Object -Append -file $summaryLog
    return $False
}


$diskSize = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "fdisk -l /dev/sdb  2> /dev/null | grep Disk | grep sdb | cut -f 5 -d ' '"
if (-not $?)
{
    "Error: Unable to determine disk size from within the guest after growing the VHDX" | Tee-Object -Append -file $summaryLog
    return $False
}

if ($diskSize -ne $newVhdxSize)
{
    "Error: VM ${vmName} sees a disk size of ${diskSize}, not the expected size of ${newVhdxSize}" | Tee-Object -Append -file $summaryLog
    return $False
}

#
# Make sure if we can perform Read/Write operations on the guest VM
#

if ([int]($newVhdxGrowSize/1gb) -gt 2048)
{
  $guest_script = "STOR_VHDXResize_PartitionDiskOver2TB"
}

else
{
 $guest_script = "STOR_VHDXResize_PartitionDiskAfterResize"
}

$sts = RunRemoteScriptCheckResult $guest_script
if (-not $($sts[-1]))
{
  "Error: Running '${guest_script}'script failed on VM. check VM logs , exiting test case execution " | Tee-Object -Append -file $summaryLog
  return $False
}
"Info : The guest sees the new size after resizing ($diskSize)" | Tee-Object -Append -file $summaryLog
"Info : VHDx Resize - ${TC_COVERED} is Done"

return $True
