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
			<files>remote-scripts/ica/utils.sh</files>
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
    setupScripts\FCOPY_non_ascii.ps1 -vmName NameOfVm -hvServer localhost -testParams 'sshKey=path/to/ssh;ipv4=ipaddress;rootDir=path/to/dir'
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false

####################################################################### 
# Delete temporary test file
#######################################################################
function RemoveTestFile()
{
    Remove-Item -Path $pathToFile -Force
    if ($? -ne "True") {
        Write-Output "Error: cannot remove the test file '${testfile}'!" | Tee-Object -Append -file $summaryLog
        return $False
    }
}

####################################################################### 
# 
# Main script body 
# 
#######################################################################
#
# Checking the input arguments
#
if (-not $vmName) {
    "Error: VM name is null!"
    return $retVal
}

if (-not $hvServer) {
    "Error: hvServer is null!"
    return $retVal
}

# Check input params
$params = $testParams.Split(";")

foreach ($p in $params)
{
    $fields = $p.Split("=")
        switch ($fields[0].Trim())
        {
        "sshKey" { $sshKey = $fields[1].Trim() }
        "ipv4" { $ipv4 = $fields[1].Trim() }
        "rootdir" { $rootDir = $fields[1].Trim() }
        "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
        default  {}          
        }
}

if ($null -eq $sshKey)
{
    "Error: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4)
{
    "Error: Test parameter ipv4 was not specified"
    return $False
}

if ($null -eq $rootdir)
{
    "Error: Test parameter rootdir was not specified"
    return $False
}

# Change the working directory to where we need to be
cd $rootDir

# Source TCUtils.ps1 for test related functions
if (Test-Path ".\setupscripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
}
else {
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}

# Delete any previous summary.log file, then create a new one
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Verify if the Guest services are enabled for this VM
#
$gsi = Get-VMIntegrationService -vmName $vmName -ComputerName $hvServer -Name "Guest Service Interface"
if (-not $gsi) {
    Write-Output "Error: Unable to retrieve Integration Service status for VM '${vmName}'" | Tee-Object -Append -file $summaryLog
    return $False
}

if (-not $gsi.Enabled) {
    Write-Output "Warning: The Guest services are not enabled for VM '${vmName}'" | Tee-Object -Append -file $summaryLog
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
else {
    Write-Output "Info: Guest services are enabled on VM '${vmName}'"       
}

# Check to see if the fcopy daemon is running on the VM
$sts = RunRemoteScript "FCOPY_Check_Daemon.sh"
if (-not $sts[-1])
{
    Write-Output "Error executing FCOPY_Check_Daemon.sh on VM. Exiting test case!" | Tee-Object -Append -file $summaryLog
    return $False
}

Remove-Item -Path "FCOPY_Check_Daemon.sh.log" -Force
Write-Output "Info: fcopy daemon is running on VM '${vmName}'"

#
# Creating the test file for sending on VM
#
if ($gsi.OperationalStatus -ne "OK") {
    Write-Output "Error: The Guest services are not working properly for VM '${vmName}'!" | Tee-Object -Append -file $summaryLog
    $retVal = $False
}
else {
    # Define the file-name to use with the current time-stamp
    $CurrentDir= "$pwd\"
    $testfile = "testfile-$(get-date -uformat '%H-%M-%S-%Y-%m-%d').file" 
    $pathToFile="$CurrentDir"+"$testfile" 

    # Sample string with non-ascii chars
    $nonAsciiChars="¡¢£¤¥§¨©ª«¬®¡¢£¤¥§¨©ª«¬®¯±µ¶←↑ψχφυ¯±µ¶←↑ψ¶←↑ψχφυ¯±µ¶←↑ψχφυχφυ"
    
    # Create a ~2MB sample file with non-ascii characters
    $stream = [System.IO.StreamWriter] $pathToFile
    1..8000 | % {
        $stream.WriteLine($nonAsciiChars)
    }
    $stream.close()

    # Checking if sample file was successfully created
    if (-not $?){
        Write-Output "Error: Unable to create the 2MB sample file" | Tee-Object -Append -file $summaryLog
        return $False   
    }
    else {
        Write-Output "Info: initial 2MB sample file $testfile successfully created"
    }

    # Multiply the contents of the sample file up to an 100MB auxiliary file
    New-Item $MyDir"auxFile" -type file | Out-Null
    2..130| % {
        $testfileContent = Get-Content $pathToFile
        Add-Content $MyDir"auxFile" $testfileContent
    }

    # Checking if auxiliary file was successfully created
    if (-not $?){
        Write-Output "Error: Unable to create the extended auxiliary file!" | Tee-Object -Append -file $summaryLog
        return $False   
    }

    # Move the auxiliary file to testfile
    Move-Item -Path $MyDir"auxFile" -Destination $pathToFile -Force

    # Checking file size. It must be over 85MB
    $testfileSize = (Get-Item $pathToFile).Length 
    if ($testfileSize -le 85mb) {
        Write-Output "Error: File not big enough. File size: $testfileSize MB" | Tee-Object -Append -file $summaryLog
        $testfileSize = $testfileSize / 1MB
        $testfileSize = [math]::round($testfileSize,2)
        Write-Output "Error: File not big enough (over 85MB)! File size: $testfileSize MB" | Tee-Object -Append -file $summaryLog
        RemoveTestFile
        return $False   
    }
    else {
        $testfileSize = $testfileSize / 1MB
        $testfileSize = [math]::round($testfileSize,2)
		Write-Output "Info: $testfileSize MB auxiliary file successfully created"
    }

    # Getting MD5 checksum of the file
    $local_chksum = Get-FileHash .\$testfile -Algorithm MD5 | Select -ExpandProperty hash
    if (-not $?){
        Write-Output "Error: Unable to get MD5 checksum!" | Tee-Object -Append -file $summaryLog
        RemoveTestFile
        return $False   
    }
    else {
        Write-Output "MD5 file checksum on the host-side: $local_chksum" | Tee-Object -Append -file $summaryLog
    }

    # Get vhd folder
    $vhd_path = Get-VMHost -ComputerName $hvServer | Select -ExpandProperty VirtualHardDiskPath

    # Fix path format if it's broken
    if ($vhd_path.Substring($vhd_path.Length - 1, 1) -ne "\"){
        $vhd_path = $vhd_path + "\"
    }

    $vhd_path_formatted = $vhd_path.Replace(':','$')
    
    $filePath = $vhd_path + $testfile
    $file_path_formatted = $vhd_path_formatted + $testfile

    # Copy file to vhd folder
    Copy-Item -Path .\$testfile -Destination \\$hvServer\$vhd_path_formatted
}

# Removing previous test files on the VM
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "rm -f /tmp/testfile-*"

#
# Sending the test file to VM
#
$Error.Clear()
Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $filePath -DestinationPath "/tmp/" -FileSource host -ErrorAction SilentlyContinue
if ($Error.Count -eq 0) {
    Write-Output "File has been successfully copied to guest VM '${vmName}'" | Tee-Object -Append -file $summaryLog
}
elseif (($Error.Count -gt 0) -and ($Error[0].Exception.Message -like "*failed to initiate copying files to the guest: The file exists. (0x80070050)*")) {
    Write-Output "Test failed! File could not be copied as it already exists on guest VM '${vmName}'" | Tee-Object -Append -file $summaryLog
    return $False
}
RemoveTestFile

#
# Verify if the file is present on the guest VM
#
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "stat /tmp/testfile-* > /dev/null" 2> $null
if (-not $?) {
	Write-Output "Error: Test file is not present on the guest VM!" | Tee-Object -Append -file $summaryLog
	return $False
}

#
# Verify if the file is present on the guest VM
#
$remote_chksum=.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "openssl MD5 /tmp/testfile-* | cut -f2 -d' '"
if (-not $?) {
	Write-Output "Error: Could not extract the MD5 checksum from the VM!" | Tee-Object -Append -file $summaryLog
	return $False
}

Write-Output "MD5 file checksum on guest VM: $remote_chksum" | Tee-Object -Append -file $summaryLog

#
# Check if checksums are matching
#
$MD5IsMatching = @(Compare-Object $local_chksum $remote_chksum -SyncWindow 0).Length -eq 0
if ( -not $MD5IsMatching) {
    Write-Output "Error: MD5 checksum missmatch between host and VM test file!" | Tee-Object -Append -file $summaryLog
    return $False
}

Write-Output "Info: MD5 checksums are matching between the host-side and guest VM file." | Tee-Object -Append -file $summaryLog

# Removing the temporary test file
Remove-Item -Path \\$hvServer\$file_path_formatted -Force
if ($? -ne "True") {
    Write-Output "Error: cannot remove the test file '${testfile}'!" | Tee-Object -Append -file $summaryLog
	return $False
}

#
# If we made it here, everything worked
#
Write-Output "Test completed successfully"
return $True
