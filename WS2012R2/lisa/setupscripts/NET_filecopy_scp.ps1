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
    This script tests the functionality of copying a 10GB large file using pscp.

.Description
    The script will copy a random generated 10GB file from a Windows host to
	the Linux VM, and then checks if the size is matching.

    A typical XML definition for this test case would look similar
    to the following:
		<test>
            <testName>CopyFileScp</testName>
            <setupScript>setupScripts\Add-VHDXForResize.ps1</setupScript>
            <testScript>setupscripts\NET_filecopy_scp.ps1</testScript>
            <files>remote-Scripts/ica/NET_scp_check_md5.sh</files>
            <cleanupScript>SetupScripts\Remove-VHDXHardDisk.ps1</cleanupScript>
            <timeout>2500</timeout>
            <testParams>
                <param>TC_COVERED=FCopy-04</param>
                    <param>Type=Fixed</param>
                    <param>SectorSize=512</param>
                    <param>DefaultSize=15GB</param>
                <param>SCSI=1,0,Dynamic,512,15GB</param>
                <param>bandwidth=4096</param>
            </testParams>
        </test>

.Parameter vmName
    Name of the VM to test.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case.

.Example
    setupScripts\NET_filecopy_scp.ps1 -vmName NameOfVm -hvServer localhost -testParams 'sshKey=path/to/ssh;ipv4=ipaddress'
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$testfile = $null
# 10GB file size
$filesize = 10737418240

#######################################################################
#
#	Checks if test file is present
#
#######################################################################
function check_file([String] $testfile)
{
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "wc -c < /mnt/$testfile"
    if (-not $?) {
        Write-Output "ERROR: Unable to read file /mnt/$testfile." -ErrorAction SilentlyContinue
        return $False
    }
	return $True
}

#######################################################################
#
#	Mount disk
#
#######################################################################
function mount_disk()
{
	. .\setupScripts\TCUtils.ps1
    $driveName = "/dev/sdb"

    $sts = SendCommandToVM $ipv4 $sshKey "(echo d;echo;echo w)|fdisk ${driveName}"
    if (-not $sts) {
		Write-Output "ERROR: Failed to format the disk in the VM $vmName."
		return $False
    }

    $sts = SendCommandToVM $ipv4 $sshKey "(echo n;echo p;echo 1;echo;echo;echo w)|fdisk ${driveName}"
    if (-not $sts) {
		Write-Output "ERROR: Failed to format the disk in the VM $vmName."
		return $False
    }

    $sts = SendCommandToVM $ipv4 $sshKey "mkfs.ext3 ${driveName}1"
    if (-not $sts) {
		Write-Output "ERROR: Failed to make file system in the VM $vmName."
		return $False
    }

    $sts = SendCommandToVM $ipv4 $sshKey "mount ${driveName}1 /mnt"
    if (-not $sts) {
		Write-Output "ERROR: Failed to mount the disk in the VM $vmName."
		return $False
    }

    "Info: $driveName has been mounted to /mnt in the VM $vmName."

    return $True
}

#######################################################################
#
#	Main body script

#######################################################################

$retVal = $false

# Checking the input arguments
if (-not $vmName) {
    "Error: VM name is null!"
    return $retVal
}

if (-not $hvServer) {
    "Error: hvServer is null!"
    return $retVal
}

if (-not $testParams) {
    "Error: No testParams provided!"
    "This script requires the test case ID and VM details as the test parameters."
    return $retVal
}

#
# Checking the mandatory testParams. New parameters must be validated here.
#

$bandwidth=2048
$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")

    if ($fields[0].Trim() -eq "TC_COVERED") {
        $TC_COVERED = $fields[1].Trim()
    }
	if ($fields[0].Trim() -eq "rootDir") {
        $rootDir = $fields[1].Trim()
    }
	if ($fields[0].Trim() -eq "ipv4") {
		$IPv4 = $fields[1].Trim()
    }
	if ($fields[0].Trim() -eq "sshkey") {
        $sshkey = $fields[1].Trim()
    }
	if ($fields[0].Trim() -eq "bandwidth") {
        $bandwidth = $fields[1].Trim()
    }
}

#
# Change the working directory for the log files
# Delete any previous summary.log file, then create a new one
#
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist"
    return $retVal
}
cd $rootDir

# Delete any previous summary.log file, then create a new one
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

$retVal = $True

#
# Verify the Putty utilities exist.  Without them, we cannot talk to the Linux VM.
#
if (-not (Test-Path -Path ".\bin\pscp.exe"))
{
	LogMsg 0 "Error: The putty utility .\bin\pscp.exe does not exist"
	return
}

# Get VHD path of tested server; file will be copied there
$vhd_path = Get-VMHost -ComputerName $hvServer | Select -ExpandProperty VirtualHardDiskPath

# Fix path format if it's broken
if ($vhd_path.Substring($vhd_path.Length - 1, 1) -ne "\"){
    $vhd_path = $vhd_path + "\"
}

$vhd_path_formatted = $vhd_path.Replace(':','$')

# Define the file-name to use with the current time-stamp
$testfile = "testfile-$(get-date -uformat '%H-%M-%S-%Y-%m-%d').file"

$filePath = $vhd_path + $testfile
$file_path_formatted = $vhd_path_formatted + $testfile

# Create a 10GB sample file
$createfile = fsutil file createnew \\$hvServer\$file_path_formatted $filesize

if ($createfile -notlike "File *testfile-*.file is created") {
	"Error: Could not create the sample test file in the working directory!" | Tee-Object -Append -file $summaryLog
	$retVal = $False
}

$sts = mount_disk
if (-not $sts[-1]) {
    Write-Output "ERROR: Failed to mount the disk in the VM." | Tee-Object -Append -file $summaryLog
    $retVal = $False
}

#
#Getting MD5 checksum of the file
#
$localChksum = Get-FileHash $filePath -Algorithm MD5 | select -ExpandProperty hash
if (-not $?){
	Write-Output "ERROR: Unable to get MD5 checksum"
	Write-Output "ERROR: Unable to get MD5 checksum" >> $summaryLog
	RemoveTestFile
	return $False   
}
else {
	Write-Output "MD5 checksum on Hyper-V: $localChksum"
}

#
# Copy the file to the Linux guest VM
#
$Error.Clear()

$copyDuration = (Measure-Command { bin\pscp -i ssh\${sshKey} -l ${bandwidth} ${filePath} root@${ipv4}:/mnt/ }).totalseconds

if ($Error.Count -eq 0) {
	Write-Output "Info: File has been successfully copied to guest VM '${vmName}'" | Tee-Object -Append -file $summaryLog
}
else {
	Write-Output "ERROR: File could not be copied!" | Tee-Object -Append -file $summaryLog
	$retVal = $False
}

[int]$copyDuration = [math]::floor($copyDuration)

Write-Output "The file copy process took ${copyDuration} seconds with bandwidth $bandwidth" | Tee-Object -Append -file $summaryLog

#
# Checking if the file is present on the guest and file size is matching
#
$sts = check_file $testfile
if (-not $sts[-1]) {
	Write-Output "ERROR: File is not present on the guest VM '${vmName}'!" | Tee-Object -Append -file $summaryLog
	$retVal = $False
}
elseif ($sts[0] -eq $filesize) {
	Write-Output "Info: The file copied matches the 10GB size." | Tee-Object -Append -file $summaryLog
}
else {
	Write-Output "ERROR: The file copied doesn't match the 10GB size!" | Tee-Object -Append -file $summaryLog
	$retVal = $False
}

#
# Run the remote script to get MD5 checksum on VM
#

.\bin\plink -i ssh\${sshKey} root@${ipv4} "dos2unix /root/NET_scp_check_md5.sh $testfile"
.\bin\plink -i ssh\${sshKey} root@${ipv4} "bash /root/NET_scp_check_md5.sh $testfile"
if (-not $?) {
    Write-Error -Message  "ERROR: Unable to compute md5 on vm file" -ErrorAction SilentlyContinue
    Write-Output "ERROR: Unable to compute md5 on vm file"
    return $False
}

.\bin\pscp -i ssh\${sshKey} root@${ipv4}:/root/summary.log .
if (-not $?) {
		Write-Error -Message "ERROR: Unable to copy the confirmation file from the VM" -ErrorAction SilentlyContinue
		Write-Output "ERROR: Unable to copy the confirmation file from the VM"
		return $False
    }

Write-Output "$remoteScript execution on VM: Success"
Write-Output "Here are the remote logs:`n`n"
$logfilename = ".\summary.log"
Get-Content $logfilename
Write-Output "$remoteScript execution on VM: Success" 

#
# Check if checksums are matching
#
$md5IsMatching = select-string -pattern $localChksum -path $logfilename
if ($md5IsMatching -eq $null) 
{ 
    Write-Output "ERROR: MD5 checksums are not matching" >> $summaryLog
    Remove-Item -Path "NET_scp_check_md5.sh.log" -Force
    return $False
} 
else 
{ 
    Write-Output "Info: MD5 checksums are matching" | Tee-Object -Append -file $summaryLog
    Remove-Item -Path "NET_scp_check_md5.sh.log" -Force
    $results = "Passed"
    $retVal = $True
}

#
# Removing the temporary test file
#
Remove-Item -Path \\$hvServer\$file_path_formatted -Force
if (-not $?) {
    Write-Output "ERROR: Cannot remove the test file '${testfile}'!" | Tee-Object -Append -file $summaryLog
}

return $retVal