################################################################################
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
################################################################################

<#
.Synopsis
    This test script will dettach VHDx disk(s) from VM and reattach them while vm is running.

.Description
    The first .vhdx file will be dettached, then the second .vhdx.
    The VM should not have attached disks anymore.
    Then the first .vhdx will be attached back, and then the second .vhdx.
    The VM should recognize the disks attached.
    Will do add/remove two disks based on LoopCount parameter.

    A typical test case definition for this test script would look
    similar to the following:
        <test>
            <testName>VHDx_DiskHotPlugUnplug</testName>
            <setupScript>SetupScripts\AddVhdxHardDisk.ps1</setupScript>
            <testScript>setupscripts\STOR_unPlug_Plug.ps1</testScript>
            <files>remote-scripts/ica/STOR_hot_remove.sh</files>
            <files>remote-scripts/ica/check_traces.sh</files>
            <cleanupScript>SetupScripts\RemoveVhdxHardDisk.ps1</cleanupScript>
            <testparams>
                <param>TC_COVERED=STOR-31b,STOR-42b</param>
                <param>SCSI=0,0,Dynamic,512,1GB</param>
                <param>SCSI=0,1,Dynamic,512,2GB</param>
                <param>LoopCount=5</param>
            </testparams>
            <timeout>800</timeout>
            <onError>Continue</onError>
        </test>

.Parameter vmName
    Name of the VM to add disk to.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\STOR_unPlug_Plug.ps1 `
    -vmName VM_NAME
    -hvServer HYPERV_SERVER `
    -testParams "SCSI=0,0,Dynamic,512,1GB;SCSI=0,1,Dynamic,512,2GB;LoopCount=5"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

function AttachVHDxDiskDrive( [string] $vmName, [string] $hvServer,
                        [string] $vhdxPath, [string] $controllerType,[string] $controllerID,[string] $lun )
{
    $error.Clear()
    Add-VMHardDiskDrive -VMName $vmName `
                        -ComputerName $hvServer `
                        -Path $vhdxPath `
                        -ControllerType $controllerType `
                        -ControllerNumber $controllerID `
                        -ControllerLocation $lun
    if ($error.Count -gt 0)
    {
        Write-Output "Error: Add-VMHardDiskDrive failed to add drive on SCSI controller $error[0].Exception"
        $error[0].Exception
        return $False
    }
    return $True
}

function RemoveVHDxDiskDrive( [string] $vmName, [string] $hvServer,
                        [string] $controllerType,[string] $controllerID,[string] $lun)
{
    $error.Clear()
    Remove-VMHardDiskDrive -VMName $vmName `
                           -ComputerName $hvServer `
                           -ControllerType $controllerType `
                           -ControllerLocation $lun `
                           -ControllerNumber $controllerID
    if ($error.Count -gt 0)
    {
        Write-Output "Error: Remove-VMHardDiskDrive failed to remove drive on SCSI controller $error[0].Exception"
        $error[0].Exception
        return $False
    }
    return $True
}

################################################################################
#
# Main script
#
################################################################################

$scsi=$true
$remoteScript="STOR_hot_remove.sh"

# Check input arguments
if ($vmName -eq $null -or $vmName.Length -eq 0)
{
    Write-Output "Error: VM name is null"
    return $False
}
if ($hvServer -eq $null -or $hvServer.Length -eq 0)
{
    Write-Output "Error: hvServer is null"
    return $False
}
if ($testParams -eq $null -or $testParams.Length -lt 3)
{
    Write-Output "Error: setupScript requires test params"
    return $False
}

# Parse the testParams string
$params = $testParams.TrimEnd(";").Split(";")

foreach ($p in $params)
{
    $fields = $p.Split("=")
    $value = $fields[1].Trim()
    switch ($fields[0].Trim())
    {
    "SshKey"  { $sshKey  = $fields[1].Trim() }
    "ipv4"    { $ipv4    = $fields[1].Trim() }
    "rootDIR"   { $rootDir = $fields[1].Trim() }
    "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    "LoopCount" { $loopCount = $fields[1].Trim() }
    default     {}  # unknown param - just ignore it
    }
}

if (-not (Test-Path $rootDir))
{
    Write-Output "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

cd $rootDir

# Source TCUtils.ps1
if (Test-Path ".\setupScripts\TCUtils.ps1")
{
    . .\setupScripts\TCUtils.ps1
}
else
{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}

# Delete any summary.log from a previous test run, then create a new file
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
$Error.Clear()

Write-Output "Covers: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

foreach ($p in $params){
    $p -match '^([^=]+)=(.+)' | Out-Null
    if ($Matches[1,2].Length -ne 2)
    {
        "Warn : test parameter '$p' is being ignored because it appears to be malformed"
        continue
    }

    # Matches[1] represents the parameter name
    # Matches[2] is the value content of the parameter
    $controller = $Matches[1].Trim()
    if ("SCSI" -notcontains $controller)
    {
        # Not a test parameter we are concerned with
        continue
    }

    $controllerType=$controller
    $diskArgs = $Matches[2].Trim().Split(',')
    if ($diskArgs.Length -lt 3 -or $diskArgs.Length -gt 5)
    {
        "Error: Incorrect number of arguments: $p"
        return $False
    }
    $vmGeneration = GetVMGeneration $vmName $hvServer
    if($scsi){
        $controllerID1 = $diskArgs[0].Trim()
        if ($vmGeneration -eq 1){$lun1 = [int]($diskArgs[1].Trim())}
        else{$lun1 = [int]($diskArgs[1].Trim()) +1}
        $scsi=$false
        }
    else{
        $controllerID2 = $diskArgs[0].Trim()
        if ($vmGeneration -eq 1){$lun2 = [int]($diskArgs[1].Trim())}
        else{$lun2 = [int]($diskArgs[1].Trim()) +1}
        }
    $vhdType = $diskArgs[2].Trim()
}

$path1=(Get-VMHardDiskDrive -VMName $vmName -ComputerName $hvServer -ControllerLocation $lun1 -ControllerNumber $controllerID1 -ControllerType $controllerType).Path
$path2=(Get-VMHardDiskDrive -VMName $vmName -ComputerName $hvServer -ControllerLocation $lun2 -ControllerNumber $controllerID2 -ControllerType $controllerType).Path

for ($i=0; $i -lt $loopCount; $i++)
{
    #Remove the 1st VHDx
    Write-Output "Current loop number is $i."
    $retVal = RemoveVHDxDiskDrive $vmName $hvServer $controllerType $controllerID1 $lun1
    if (-not $retVal[-1])
    {
        Write-Output "Error: Failed to remove first VHDx with path $path1!" | Tee-Object -Append -file $summaryLog
        return $False
    }
    Write-Output "Removed first VHDx with path $path1"

    #Remove the 2nd VHDx
    $retVal = RemoveVHDxDiskDrive $vmName $hvServer $controllerType $ccontrollerID2 $lun2
    if (-not $retVal[-1])
    {
        Write-Output "Error: Failed to remove second VHDx with path $path2!" | Tee-Object -Append -file $summaryLog
        return $False
    }
    Write-Output "Removed second VHDx with path $path2"

    #verify if vm sees that disks were dettached
    $sts = RunRemoteScript $remoteScript
    if (-not $sts[-1])
    {
        Write-Output "ERROR executing $remoteScript on VM. Exiting test case!" | Tee-Object -Append -file $summaryLog
        Write-Output "ERROR: Running $remoteScript script failed on VM!"
        return $False
    }

    #Attaching the 1st VHDx again
    $retVal = AttachVHDxDiskDrive $vmName $hvServer $path1 $controllerType $controllerID1 $lun1
    if (-not $retVal[-1])
    {
        Write-Output "Error: Failed to attach first VHDx with path $path1!" | Tee-Object -Append -file $summaryLog
        return $False
    }
    Write-Output "Attached first VHDx with path $path1"

    #Attaching the 2nd VHDx again
    $retVal = AttachVHDxDiskDrive $vmName $hvServer $path2 $controllerType $controllerID2 $lun2
    if (-not $retVal[-1])
    {
        Write-Output "Error: Failed to attach second VHDx with path $pat2!" | Tee-Object -Append -file $summaryLog
        return $False
    }
    Write-Output "Attached second VHDx with path $path2"

    #wait for vm to see the disks
    Start-Sleep 5

    $diskNumber = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "fdisk -l | grep 'Disk /dev/sd*' | grep -v 'Disk /dev/sda' | wc -l"
    if ( $diskNumber -ne 2)
    {
        Write-Output "Error: Failed to attach VHDx "| Tee-Object -Append -file $summaryLog
        return $False
    }
}
return $true
