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
    This script tests the file copy functionality.

.Description
    The script will copy a random generated 10MB file from a Windows host to 
	the Linux VM, and then checks if the size is matching.

    A typical XML definition for this test case would look similar
    to the following:
		<test>
			<testName>FCOPY_basic</testName>
			<testScript>setupscripts\FCOPY_basic.ps1</testScript>
			<timeout>900</timeout>
			<testParams>
				<param>TC_COVERED=FCopy-01</param>
			</testParams>
			<noReboot>True</noReboot>
		</test>

.Parameter vmName
    Name of the VM to test.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case.

.Example
    setupScripts\FCOPY_basic.ps1 -vmName NameOfVm -hvServer localhost -testParams 'sshKey=path/to/ssh;rootdir=path/to/testdir;ipv4=ipaddress'
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false
$testfile = $null
$gsi = $null

#######################################################################
#
#	Checks if the file copy daemon is running on the Linux guest
#
#######################################################################
function check_fcopy_daemon()
{
	$filename = ".\fcopy_present"
    
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "ps -ef | grep '[h]v_fcopy_daemon' > /root/fcopy_present"
    if (-not $?) {
        Write-Error -Message  "ERROR: Unable to run ps -ef | grep hv_fcopy_daemon" -ErrorAction SilentlyContinue
        Write-Output "ERROR: Unable to run ps -ef | grep hv_fcopy_daemon"
        return $False
    }

    .\bin\pscp -i ssh\${sshKey} root@${ipv4}:/root/fcopy_present .
    if (-not $?) {
		Write-Error -Message "ERROR: Unable to copy the confirmation file from the VM" -ErrorAction SilentlyContinue
		Write-Output "ERROR: Unable to copy the confirmation file from the VM"
		return $False
    }

    # When using grep on the process in file, it will return 1 line if the daemon is running
    if ((Get-Content $filename  | Measure-Object -Line).Lines -eq  "1" ) {
		Write-Output "Info: hv_fcopy_daemon process is running."  
		$retValue = $True
    }
	
    del $filename   
    return $retValue 
}

#######################################################################
#
#	Checks if test file is present
#
#######################################################################
function check_file([String] $testfile)
{
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "wc -c < /root/$testfile"
    if (-not $?) {
        Write-Output "ERROR: Unable to read file" -ErrorAction SilentlyContinue
        return $False
    }
	elseif ($? -eq 10485760) {
		return $True
	}
}

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

# Delete any previous summary.log file, then create a new one
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

$retVal = $True

#
# Verify if the Guest services are enabled for this VM
#
$gsi = Get-VMIntegrationService -vmName $vmName -ComputerName $hvServer -Name "Guest Service Interface"
if (-not $gsi) {
    "Error: Unable to retrieve Integration Service status from VM '${vmName}'" | Tee-Object -Append -file $summaryLog
    return $False
}

if (-not $gsi.Enabled) {
    "Warning: The Guest services are not enabled for VM '${vmName}'" | Tee-Object -Append -file $summaryLog
	if ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Off") {
		Stop-VM -ComputerName $hvServer -Name $vmName -Force -Confirm:$false
	}

	# Waiting until the VM is off
	while ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Off") {
		Start-Sleep -Seconds 5
	}
	
	Enable-VMIntegrationService -Name "Guest Service Interface" -vmName $vmName -ComputerName $hvServer 
	Start-VM -Name $vmName -ComputerName $hvServer

	# Waiting for the VM to run again and respond to SSH - port 22
	do {
		sleep 5
	} until (Test-NetConnection $IPv4 -Port 22 -WarningAction SilentlyContinue | ? { $_.TcpTestSucceeded } )
}

if ($gsi.OperationalStatus -ne "OK") {
    "Error: The Guest services are not working properly for VM '${vmName}'!" | Tee-Object -Append -file $summaryLog
	$retVal = $False
}
else {
	# Define the file-name to use with the current time-stamp
	$testfile = "testfile-$(get-date -uformat '%H-%M-%S-%Y-%m-%d').file" 

	# Create a 10MB sample file
	$createfile = fsutil file createnew $testfile 10485760

	if ($createfile -notlike "File *testfile-*.file is created") {
		"Error: Could not create the sample test file in the working directory!" | Tee-Object -Append -file $summaryLog
		$retVal = $False
	}
}

# The fcopy daemon must be running on the Linux guest VM
$sts = check_fcopy_daemon
if (-not $sts[-1]) {
    Write-Output "ERROR: file copy daemon is not running inside the Linux guest VM!" | Tee-Object -Append -file $summaryLog
    $retVal = $False
}

# If we got here then all checks have passed and we can copy the file to the Linux guest VM
$Error.Clear()
Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $testfile -DestinationPath "/root/" -FileSource host -ErrorAction SilentlyContinue
if ($Error.Count -eq 0) {
	Write-Output "File has been successfully copied to guest VM '${vmName}'" | Tee-Object -Append -file $summaryLog
}
elseif (($Error.Count -gt 0) -and ($Error[0].Exception.Message -like "*failed to initiate copying files to the guest: The file exists. (0x80070050)*")) {
	Write-Output "Test failed! File could not be copied as it already exists on guest VM '${vmName}'" | Tee-Object -Append -file $summaryLog
	$retVal = $False
}

# Checking if the file size is matching
$sts = check_file $testfile
if (-not $sts[-1]) {
	Write-Output "ERROR: File is not present on the guest VM '${vmName}'!" | Tee-Object -Append -file $summaryLog
	$retVal = $False
}
elseif ($sts[1]) {
	Write-Output "Info: The file copied matches the 10MB size." | Tee-Object -Append -file $summaryLog
}

# Removing the temporary test file
Remove-Item -Path $testfile -Force
if ($? -ne "True") {
    Write-Output "ERROR: cannot remove the test file '${testfile}'!" | Tee-Object -Append -file $summaryLog
}

return $retVal
