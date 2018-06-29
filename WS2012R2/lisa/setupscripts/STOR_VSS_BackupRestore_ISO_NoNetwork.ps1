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
    This script will stop networking and attach a CD ISO to the vm.
    After that it will perform the backup/restore operation.

    It uses a second partition as target.

    Note: The script has to be run on the host. A second partition
    different from the Hyper-V one has to be available.

    A typical xml entry looks like this:

    <test>
    <testName>VSS_BackupRestore_ISO_NoNetwork</testName>
        <testScript>setupscripts\VSS_BackupRestore_ISO_NoNetwork.ps1</testScript>
        <testParams>
            <param>driveletter=F:</param>
            <param>TC_COVERED=VSS-11</param>
        </testParams>
        <timeout>1200</timeout>
        <OnERROR>Continue</OnERROR>
    </test>

    The iOzoneVers param is needed for the download of the correct iOzone version.

.Parameter vmName
    Name of the VM to backup/restore.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\VSS_BackupRestore_ISO_NoNetwork.ps1 -hvServer localhost -vmName NameOfVm -testParams 'sshKey=path/to/ssh;rootdir=path/to/testdir;ipv4=ipaddress;driveletter=D:'

#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false
$remoteScript = "STOR_VSS_StopNetwork.sh"

######################################################################
# Runs a remote script on the VM without checking the log
#######################################################################
function RunRemoteScriptNoState($remoteScript)
{

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
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "at -f runtest.sh now + 1 minutes"

    del runtest.sh
    return $True
}

#######################################################################
#
# Main script body
#
#######################################################################

# Check input arguments
if ($vmName -eq $null)
{
    Write-Output "ERROR: VM name is null"
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
        "IsoFilename" {$isoFilename = $fields[1].Trim() }
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

if ($null -eq $rootdir)
{
    Write-Output "ERROR: Test parameter rootdir was not specified"
    return $False
}

if ($null -eq $TestLogDir)
{
    $TestLogDir = $rootdir
}

# Change the working directory to where we need to be
cd $rootDir
# Source TCUtils.ps1 for common functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
	. .\setupScripts\TCUtils.ps1
	"Info: Sourced TCUtils.ps1"
}
else {
	"Error: Could not find setupScripts\TCUtils.ps1"
	return $false
}

$loggerManager = [LoggerManager]::GetLoggerManager($vmName, $testParams)
$global:logger = $loggerManager.TestCase

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

$sts = runSetup $vmName $hvServer
if (-not $sts[-1])
{
    return $False
}

$driveletter = $global:driveletter
Write-Output "Driveletter in VSS_BackupRestore_ISO_NoNetwork is $driveletter"

if ($null -eq $driveletter)
{
    Write-Output "ERROR: Test parameter driveletter was not specified."
    return $False
}

#
# Make sure the .iso file exists on the HyperV server
#
if (-not ([System.IO.Path]::IsPathRooted($isoFilename)))
{
    $obj = Get-WmiObject -ComputerName $hvServer -Namespace "root\virtualization\v2" -Class "MsVM_VirtualSystemManagementServiceSettingData"

    $defaultVhdPath = $obj.DefaultVirtualHardDiskPath

    if (-not $defaultVhdPath)
    {
        $logger.error("Unable to determine VhdDefaultPath on HyperV server ${hvServer}")
        $logger.error($error[0].Exception)
        return $False
    }

    if (-not $defaultVhdPath.EndsWith("\"))
    {
        $defaultVhdPath += "\"
    }

    $isoFilename = $defaultVhdPath + $isoFilename
}

$isoFileInfo = GetRemoteFileInfo $isoFilename $hvServer
if (-not $isoFileInfo)
{
    $logger.error("The .iso file $isoFilename does not exist on HyperV server ${hvServer}")
    return $False
}


Set-VMDvdDrive -VMName $vmName -ComputerName $hvServer -Path $isoFilename
if (-not $?)
{
        $logger.error("Unable to Add ISO $isoFilename")
        return $False
}

$logger.info("Attached DVD: Success")

# Bring down the network.
RunRemoteScriptNoState $remoteScript

Start-Sleep -Seconds 65
# echo $x
# return $False

# Make sure network is down.
$sts = ping $ipv4
$pingresult = $False
foreach ($line in $sts)
{
   if (( $line -Like "*unreachable*" ) -or ($line -Like "*timed*"))

   {
       $pingresult = $True
   }
}

if ($pingresult)
{
    $logger.info("Network Down: Success")
}
else
{
    $logger.error("Network Down: Failed")
    return $False
}

$sts = startBackup $vmName $driveletter

if (-not $sts[-1])
{
    return $False
}
else
{
    $backupLocation = $sts
}

$sts = restoreBackup $backupLocation
if (-not $sts[-1])
{
    return $False
}

$sts = checkResults $vmName $hvServer
if (-not $sts[-1])
{
    $retVal = $False
}
else
{
	$retVal = $True
    $results = $sts
}

runCleanup $backupLocation

$logger.info("Test ${results}")
return $retVal
