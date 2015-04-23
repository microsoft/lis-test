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
    This script tests the file copy from host to guest overwrite functionality.

.Description
    The script will copy a text file from a Windows host to the Linux VM,
    and checks if the size and content are correct.
	Then it modifies the content of the file to a smaller size on host,
    and then copy it to the VM again, with parameter -Force, to overwrite
    the file, and then check if the size and content are correct.

    A typical XML definition for this test case would look similar
    to the following:
		<test>
			<testName>FCOPY_overwrite</testName>
			<testScript>setupscripts\FCOPY_overwrite.ps1</testScript>
			<timeout>900</timeout>
			<testParams>
				<param>TC_COVERED=FCopy-03</param>
			</testParams>
		</test>

.Parameter vmName
    Name of the VM to test.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case.

.Example
    setupScripts\FCOPY_overwrite.ps1 -vmName NameOfVm -hvServer localhost -testParams 'sshKey=path/to/ssh;ipv4=ipaddress'
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
    
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "ps -ef | grep "[h]v_fcopy_daemon\|[h]ypervfcopyd" > /root/fcopy_present"
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
#	Check if the test file is present, and get the size and content
#
#######################################################################
function check_file([String] $testfile)
{
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "wc -c < /root/$testfile"
    if (-not $?) {
        Write-Output "ERROR: Unable to read file /root/$testfile." -ErrorAction SilentlyContinue
        return $False
    }

    $sts = SendCommandToVM $ipv4 $sshKey "dos2unix /root/$testfile"
    if (-not $sts) {
        Write-Output "ERROR: Failed to convert file /root/$testfile to unix format." -ErrorAction SilentlyContinue
        return $False
    }

	.\bin\plink -i ssh\${sshKey} root@${ipv4} "cat /root/$testfile"
    if (-not $?) {
        Write-Output "ERROR: Unable to read file /root/$testfile." -ErrorAction SilentlyContinue
        return $False
    }
    return $True
}

#######################################################################
#
#	Generate random string
#
#######################################################################
function generate_random_string([Int] $length)
{
    $set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
    $result = ""
    for ($x = 0; $x -lt $length; $x++)
    {
        $result += $set | Get-Random
    }
    return $result
}

#######################################################################
#
#	Write, copy and check file
#
#######################################################################
function copy_and_check_file([String] $testfile, [Boolean] $overwrite, [Int] $contentlength)
{
    # Write the file
    $filecontent = generate_random_string $contentlength

    $filecontent | Out-File $testfile
    if (-not $?) {
        Write-Output "ERROR: Cannot create file $testfile'." | Tee-Object -Append -file $summaryLog
        return $False
    }

    $filesize = (Get-Item $testfile).Length
    if (-not $filesize){
        Write-Output "ERROR: Cannot get the size of file $testfile'." | Tee-Object -Append -file $summaryLog
        return $False
    }

    # Copy the file and check copied file
    $Error.Clear()
    if ($overwrite) {
        Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $testfile -DestinationPath "/root/" -FileSource host -ErrorAction SilentlyContinue -Force       
    }
    else {
        Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $testfile -DestinationPath "/root/" -FileSource host -ErrorAction SilentlyContinue
    }
    if ($Error.Count -eq 0) {
        $sts = check_file $testfile
        if (-not $sts[-1]) {
            Write-Output "ERROR: File is not present on the guest VM '${vmName}'!" | Tee-Object -Append -file $summaryLog
            return $False
        }
        elseif ($sts[0] -ne $filesize) {
            Write-Output "ERROR: The copied file doesn't match the $filesize size." | Tee-Object -Append -file $summaryLog
            return $False
        }
        elseif ($sts[1] -ne $filecontent) {
            Write-Output "ERROR: The copied file doesn't match the content '$filecontent'." | Tee-Object -Append -file $summaryLog
            return $False
        }
        else {
            Write-Output "Info: The copied file matches the $filesize size and content '$filecontent'." | Tee-Object -Append -file $summaryLog
        }
    }
    else {
        Write-Output "ERROR: An error has occurred while copying the file to guest VM '${vmName}'." | Tee-Object -Append -file $summaryLog
	    $error[0] | Tee-Object -Append -file $summaryLog
	    return $False
    }
    return $True
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
	if ($fields[0].Trim() -eq "ipv4") {
		$IPv4 = $fields[1].Trim()
    }
	if ($fields[0].Trim() -eq "rootDir") {
        $rootDir = $fields[1].Trim()
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

. .\setupScripts\TCUtils.ps1

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

#
# The fcopy daemon must be running on the Linux guest VM
#
$sts = check_fcopy_daemon
if (-not $sts[-1]) {
    Write-Output "ERROR: file copy daemon is not running inside the Linux guest VM!" | Tee-Object -Append -file $summaryLog
    $retVal = $False
}

# Define the file-name to use with the current time-stamp
$testfile = "testfile-$(get-date -uformat '%H-%M-%S-%Y-%m-%d').file" 

#
# Initial file copy, which must be successful. Create a text file with 20 characters, and then copy it.
#
$sts = copy_and_check_file $testfile $False 20
if (-not $sts[-1]) {
    Write-Output "ERROR: Failed to initially copy the file '${testfile}' to the VM." | Tee-Object -Append -file $summaryLog
    $retVal = $False
}
else {
    Write-Output "Info: The file has been initially copied to the VM '${vmName}'." | Tee-Object -Append -file $summaryLog
}

#
# Second copy file overwrites the initial file. Re-write the text file with 15 characters, and then copy it with -Force parameter.
#
$sts = copy_and_check_file $testfile $True 15
if (-not $sts[-1]) {
    Write-Output "ERROR: Failed to overwrite the file '${testfile}' to the VM." | Tee-Object -Append -file $summaryLog
    $retVal = $False
}
else {
    Write-Output "Info: The file has been overwritten to the VM '${vmName}'." | Tee-Object -Append -file $summaryLog
}

# Removing the temporary test file
Remove-Item -Path $testfile -Force
if ($? -ne "True") {
    Write-Output "ERROR: cannot remove the test file '${testfile}'!" | Tee-Object -Append -file $summaryLog
}

return $retVal
