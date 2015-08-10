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
    The script will generate a 100MB file with non-ascii characters. Then
    it will copy the file to the Linux VM. Finally, the script will verify 
    both checksums (on host and guest).

    A typical XML definition for this test case would look similar
    to the following:
		<test>
			<testName>FCOPY_non_ascii</testName>
			<testScript>setupscripts\FCOPY_non_ascii.ps1</testScript>
			<timeout>900</timeout>
			<testParams>
				<param>TC_COVERED=FCopy-05</param>
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
    setupScripts\FCOPY_non_ascii.ps1 -vmName NameOfVm -hvServer localhost -testParams 'sshKey=path/to/ssh;ipv4=ipaddress'
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
    
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "ps -ef | grep '[h]v_fcopy_daemon\|[h]ypervfcopyd' > /root/fcopy_present"
    if (-not $?) {
        Write-Error -Message  "ERROR: Unable to verify if the fcopy daemon is running" -ErrorAction SilentlyContinue
        Write-Output "ERROR: Unable to verify if the fcopy daemon is running"
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
    $localChksum = Get-FileHash .\$testfile -Algorithm MD5 | Out-String
    $localChksum = $localChksum.Substring(450,32)
    Write-Output "Checksum on host: $localChksum" 
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "openssl md5 $testfile  | grep -i $localChksum"
    if ($?) {
        Write-Output "Checksum is good. File copy was successful" 
        return $True  
    }
    else {
        Write-Output "ERROR: Checksum not matching"
        return $False  
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
    $MyDir= "$pwd\"
	$testfile = "testfile-$(get-date -uformat '%H-%M-%S-%Y-%m-%d').file" 
    $pathToFile="$MyDir"+"$testfile" 

	# Create a ~100MB sample file with non-ascii characters
    $stream = [System.IO.StreamWriter] $pathToFile
    $s="¡¢£¤¥§¨©ª«¬®¯±µ¶←↑ψχφυ"
    1..1000000 | % {
          $stream.Write($s)
    }
    if (-not $?){
        "ERROR: Unable to create the file" | Tee-Object -Append -file $summaryLog
        $retVal = $False   
    }
    $stream.close()
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

# Verifying MD5 checksum
check_file $testfile

# Removing the temporary test file
Remove-Item -Path $testfile -Force
if ($? -ne "True") {
    Write-Output "ERROR: cannot remove the test file '${testfile}'!" | Tee-Object -Append -file $summaryLog
    $retVal = $False
}

return $retVal
