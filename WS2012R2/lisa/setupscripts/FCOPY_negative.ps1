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
    This script tests the file copy negative functionality test.

.Description
    The script will verify fail to copy a random generated 10MB file from Windows host to
	the Linux VM, when target folder is immutable, 'Guest Service Interface' disabled and
	hyperverfcopyd is disabled.

    A typical XML definition for this test case would look similar
    to the following:
	<test>
		<testName>FCOPY_negative</testName>
		<testScript>setupscripts\FCOPY_negative.ps1</testScript>
		<timeout>900</timeout>
		<testParams>
			<param>TC_COVERED=FCopy-08</param>
		</testParams>
		<noReboot>False</noReboot>
	</test>

.Parameter vmName
    Name of the VM to test.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case.

.Example
    setupScripts\FCOPY_negative.ps1 -vmName NameOfVm -hvServer localhost -testParams 'sshKey=path/to/ssh;ipv4=ipaddress'
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false
$testfile = $null

#######################################################################
#
#	Main body script
#
#######################################################################

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

# Source TCUtils.ps1
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
} else {
    "Error: Could not find setupScripts\TCUtils.ps1"
}

# If host build number lower than 9600, skip test
$BuildNumber = GetHostBuildNumber $hvServer
if ($BuildNumber -eq 0){
    return $false
}
elseif ($BuildNumber -lt 9600){
    return $Skipped
}

# Source FCOPY_Utils.ps1
. .\setupScripts\FCOPY_utils.ps1

# If vm does not support systemd, skip test.
$sts = Check-Systemd
if ($sts[-1] -eq $false){
	return $Skipped
}

# Delete any previous summary.log file, then create a new one
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Setup: Create temporary test file in the host
#
# Get VHD path of tested server; file will be created there
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

# Create a 10MB sample file
$createfile = fsutil file createnew \\$hvServer\$file_path_formatted 10485760

if ($createfile -notlike "File *testfile-*.file is created") {
    "Error: Could not create the sample test file in the working directory!" | Tee-Object -Append -file $summaryLog
    return $false
}

Enable-VMIntegrationService -Name "Guest Service Interface" -vmName $vmName -ComputerName $hvServer

if ( $? -ne $true) {
    "Error: The Guest services are not working properly for VM!" | Tee-Object -Append -file $summaryLog
    return $false
}

#
# Step 1: verify the file cannot copy to vm when target folder is immutable
#
Write-Output "Info: Step 1: fcopy file to vm when target folder is immutable"

# Verifying if /tmp folder on guest exists; if not, it will be created
echo y | bin\plink.exe -i ssh\${sshKey} root@${ipv4} exit
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "[ -d /test ] || mkdir /test ; chattr +i /test"

if (-not $?){
    Write-Output "Error: Fail to change the permission for /test"
}

$Error.Clear()
Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $filePath -DestinationPath "/test" -FileSource host -ErrorAction SilentlyContinue

if ( $? -eq $true ) {
    Write-Output "Error: File has been copied to guest VM even  target folder immutable " | Tee-Object -Append -file $summaryLog
    return $false
}
elseif (($Error.Count -gt 0) -and ($Error[0].Exception.Message -like "*failed to initiate copying files to the guest*")) {
	Write-Output $Error[0].Exception.Message
    Write-Output "Info: File could not be copied to VM as expected since target folder immutable" | Tee-Object -Append -file $summaryLog
}

#
# Step 2: verify the file cannot copy to vm when "Guest Service Interface" is disabled
#
Write-Output "Info: Step 2: fcopy file to vm when 'Guest Service Interface' is disabled"
Disable-VMIntegrationService -Name "Guest Service Interface" -vmName $vmName -ComputerName $hvServer
if ( $? -eq $false) {
    "Error: Fail to disable 'Guest Service Interface'" | Tee-Object -Append -file $summaryLog
    return $false
}

$Error.Clear()
Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $filePath -DestinationPath "/tmp/" -FileSource host -ErrorAction SilentlyContinue

if ( $? -eq $true ) {
    Write-Output "Error: File has been copied to guest VM even 'Guest Service Interface' disabled" | Tee-Object -Append -file $summaryLog
    return $false
}
elseif (($Error.Count -gt 0) -and ($Error[0].Exception.Message -like "*Failed to initiate copying files to the guest*")) {
    Write-Output $Error[0].Exception.Message
    Write-Output "Info: File could not be copied to VM as expected since 'Guest Service Interface' disabled" | Tee-Object -Append -file $summaryLog
}

#
# Step 3: verify the file cannot copy to vm when hypervfcopyd is stopped
#
Write-Output "Info: Step 3: fcopy file to vm when hypervfcopyd stopped"
Enable-VMIntegrationService -Name "Guest Service Interface" -vmName $vmName -ComputerName $hvServer
if ( $? -ne $true) {
    "Error: Fail to enable 'Guest Service Interface'"  | Tee-Object -Append -file $summaryLog
    return $false
}

# Stop fcopy daemon to do negative test
$sts = stop_fcopy_daemon
if (-not $sts[-1]) {
    Write-Output "ERROR: Failed to stop hypervfcopyd inside the VM!" | Tee-Object -Append -file $summaryLog
    return $false
}

$Error.Clear()
Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $filePath -DestinationPath "/tmp/" -FileSource host -ErrorAction SilentlyContinue

if ( $? -eq $true ) {
    Write-Output "Error: file has been copied to guest VM even hypervfcopyd stopped" | Tee-Object -Append -file $summaryLog
    return $false
}
elseif (($Error.Count -gt 0) -and ($Error[0].Exception.Message -like "*failed to initiate copying files to the guest*")) {
    Write-Output $Error[0].Exception.Message
    Write-Output "Info: File could not be copied to VM as expected since hypervfcopyd stopped " | Tee-Object -Append -file $summaryLog
}

# Verify the file does not exist after hypervfcopyd start
$daemonName = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "systemctl list-unit-files | grep fcopy"
$daemonName = $daemonName.Split(".")[0]
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "systemctl start $daemonName"
start-sleep -s 2
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "ls /tmp/testfile-*"
if ($? -eq $true) {
    Write-Output "Error: File has been copied to guest vm after restart hypervfcopyd"
    return $false
}
# Removing the temporary test file
Remove-Item -Path \\$hvServer\$file_path_formatted -Force
if ($? -ne "True") {
    Write-Output "ERROR: cannot remove the test file '${testfile}'!" | Tee-Object -Append -file $summaryLog
}

return $true
