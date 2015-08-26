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
    setupScripts\FCOPY_non_ascii.ps1 -vmName NameOfVm -hvServer localhost -testParams 'sshKey=path/to/ssh;ipv4=ipaddress;rootDir=path/to/dir'
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

######################################################################
# Runs a remote script on the VM an returns the log.
#######################################################################
function RunRemoteScript($remoteScript)
{
    $retValue = $False
    $stateFile     = "state.txt"
    $TestCompleted = "TestCompleted"
    $TestAborted   = "TestAborted"
    $TestRunning   = "TestRunning"
    $timeout       = 6000    

    "./${remoteScript} > ${remoteScript}.log" | out-file -encoding ASCII -filepath runtest.sh 

    echo y | .\bin\pscp -i ssh\${sshKey} .\runtest.sh root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy runtest.sh to the VM"
       return $False
    }      

    echo y | .\bin\pscp -i ssh\${sshKey} .\remote-scripts\ica\${remoteScript} root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy ${remoteScript} to the VM"
       return $False
    }

    echo y | .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix ${remoteScript} 2> /dev/null"
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
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "./runtest.sh 2> /dev/null"
    
    # Return the state file
    while ($timeout -ne 0 )
    {
    .\bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${stateFile} . #| out-null
    $sts = $?
    if ($sts)
    {
        if (test-path $stateFile)
        {
            $contents = Get-Content -Path $stateFile
            if ($null -ne $contents)
            {
                    if ($contents -eq $TestCompleted)
                    {                    
                        Write-Output "Info : state file contains Testcompleted"              
                        $retValue = $True
                        break                                             
                                     
                    }

                    if ($contents -eq $TestAborted)
                    {
                         Write-Output "Info : State file contains TestAborted failed. "                                  
                         break
                          
                    }
                    #Start-Sleep -s 1
                    $timeout-- 

                    if ($timeout -eq 0)
                    {                        
                        Write-Output "Error : Timed out on Test Running , Exiting test execution."                    
                        break                                               
                    }                                
                  
            }    
            else
            {
                Write-Output "Warn : state file is empty"
                break
            }
           
        }
        else
        {
             Write-Host "Warn : ssh reported success, but state file was not copied"
             break
        }
    }
    else #
    {
         Write-Output "Error : pscp exit status = $sts"
         Write-Output "Error : unable to pull state.txt from VM." 
         break
    }     
    }

    # Get the logs
    $remoteScriptLog = $remoteScript+".log"
    
    bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${remoteScriptLog} . 
    $sts = $?
    if ($sts)
    {
        if (test-path $remoteScriptLog)
        {
            $contents = Get-Content -Path $remoteScriptLog
            if ($null -ne $contents)
            {
                    if ($null -ne ${TestLogDir})
                    {
                        move "${remoteScriptLog}" "${TestLogDir}\${remoteScriptLog}"
                
                    }

                    else 
                    {
                        Write-Output "INFO: $remoteScriptLog is copied in ${rootDir}"                                
                    }                              
                  
            }    
            else
            {
                Write-Output "Warn: $remoteScriptLog is empty"                
            }           
        }
        else
        {
             Write-Output "Warn: ssh reported success, but $remoteScriptLog file was not copied"             
        }
    }
    
    # Cleanup 
    del state.txt -ErrorAction "SilentlyContinue"
    del runtest.sh -ErrorAction "SilentlyContinue"

    return $retValue
}

####################################################################### 
# Delete temporary test file
#######################################################################
function RemoveTestFile()
{
    Remove-Item -Path $pathToFile -Force
    if ($? -ne "True") {
        Write-Output "ERROR: cannot remove the test file '${testfile}'!" >> $summaryLog
        return $False
    }
    else{
        return $True
    }
}

####################################################################### 
# 
# Main script body 
# 
#######################################################################
$retVal = $false

# Define and cleanup the summaryLog
$summaryLog  = "${vmName}_summary.log"

$remoteScript = "FCOPY_non_ascii.sh"

# Check input arguments
if ($vmName -eq $null)
{
    "ERROR: VM name is null"
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
    "ERROR: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4)
{
    "ERROR: Test parameter ipv4 was not specified"
    return $False
}

if ($null -eq $rootdir)
{
    "ERROR: Test parameter rootdir was not specified"
    return $False
}

echo $params

# Change the working directory to where we need to be
cd $rootDir

# Source the TCUtils.ps1 file
. .\setupscripts\TCUtils.ps1


Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog
#
# Verify if the Guest services are enabled for this VM
#
$gsi = Get-VMIntegrationService -vmName $vmName -ComputerName $hvServer -Name "Guest Service Interface"
if (-not $gsi) {
    Write-Output "ERROR: Unable to retrieve Integration Service status from VM '${vmName}'" >> $summaryLog
    return $False
}

if (-not $gsi.Enabled) {
    Write-Output "Warning: The Guest services are not enabled for VM '${vmName}'" >> $summaryLog
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
    Write-Output "Guest services are enabled on VM"       
}


# Check to see Linux VM is running FCOPY daemon 
$sts = RunRemoteScript "FCOPY_Check_Daemon.sh"
if (-not $sts[-1])
{
    Write-Output "ERROR executing FCOPY_Check_Daemon.sh on VM. Exiting test case!" >> $summaryLog
    Write-Output "ERROR: Running FCOPY_Check_Daemon.sh script failed on VM!"
    return $False
}
Remove-Item -Path "FCOPY_Check_Daemon.sh.log" -Force
Write-Output "FCOPY Daemon is running"

#
# Creating the test file for sending on VM
#

if ($gsi.OperationalStatus -ne "OK") {
    Write-Output "Error: The Guest services are not working properly for VM '${vmName}'!" >> $summaryLog
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
        Write-Output "ERROR: Unable to create the 2MB sample file"
        Write-Output "ERROR: Unable to create the 2MB sample file" >> $summaryLog
        return $False   
    }
    else {
        Write-Output "2MB sample file $testfile successfully created"
    }

    # Multiply the contents of the sample file up to an 100MB auxiliary file
    New-Item $MyDir"auxFile" -type file | Out-Null
    2..47| % {
        $testfileContent = Get-Content $pathToFile
        Add-Content $MyDir"auxFile" $testfileContent
    }

    # Checking if auxiliary file was successfully created
    if (-not $?){
        Write-Output "ERROR: Unable to create the 100 MB auxiliary file"
        Write-Output "ERROR: Unable to create the 100 MB auxiliary file" >> $summaryLog
        return $False   
    }
    else {
        Write-Output "100 MB auxiliary file auxFile successfully created"
    }

    # Remove the 2MB sample file
    RemoveTestFile

    # Rename the auxiliary file to testfile
    Rename-Item $MyDir"auxFile" $pathToFile

    #Checking file size. It must be around 100MB
    $testfileSize = (Get-Item $pathToFile).Length 
    if ($testfileSize -le 85mb) {
        Write-Output "ERROR: File not big enough!"
        Write-Output "ERROR: File not big enough!" >> $summaryLog
        RemoveTestFile
        return $False   
    }
    else {
        $testfileSize = $testfileSize / 1MB
        $testfileSize = [math]::round($testfileSize,2)
        Write-Output "File size : $testfileSize MB"    
    }

    #Getting MD5 checksum of the file
    $localChksum = Get-FileHash .\$testfile -Algorithm MD5 | select -ExpandProperty hash
    if (-not $?){
        Write-Output "ERROR: Unable to get MD5 checksum"
        Write-Output "ERROR: Unable to get MD5 checksum" >> $summaryLog
        RemoveTestFile
        return $False   
    }
    else {
        Write-Output "MD5 checksum on Hyper-V: $localChksum"
    }
}

# Removing previous test files on the VM
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "rm -f testfile-*"

#
# Sending the test file to VM
#

$Error.Clear()
Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $testfile -DestinationPath "/root/" -FileSource host -ErrorAction SilentlyContinue
if ($Error.Count -eq 0) {
    Write-Output "File has been successfully copied to guest VM '${vmName}'" >> $summaryLog
}
elseif (($Error.Count -gt 0) -and ($Error[0].Exception.Message -like "*failed to initiate copying files to the guest: The file exists. (0x80070050)*")) {
    Write-Output "Test failed! File could not be copied as it already exists on guest VM '${vmName}'" | Tee-Object -Append -file $summaryLog
    return $False
}
RemoveTestFile

#
# Run the remote script to get MD5 checksum on VM
#
$sts = RunRemoteScript $remoteScript
if (-not $sts[-1])
{
    Write-Output "ERROR executing $remoteScript on VM. Exiting test case!" >> $summaryLog
    Write-Output "ERROR: Running $remoteScript script failed on VM!"
    Write-Output "Here are the remote logs:`n`n###################"
    $logfilename = ".\$remoteScript.log"
    Get-Content $logfilename
    Write-Output "###################`n"
    return $False
}
Write-Output "$remoteScript execution on VM: Success"
Write-Output "Here are the remote logs:`n`n###################"
$logfilename = ".\$remoteScript.log"
Get-Content $logfilename
Write-Output "###################`n"
Write-Output "$remoteScript execution on VM: Success" 

#
# Check if checksums are matching
#
$md5IsMatching = select-string -pattern $localChksum -path $logfilename
if ($md5IsMatching -eq $null) 
{ 
    Write-Output "ERROR: MD5 checksums are not matching" >> $summaryLog
    Remove-Item -Path "FCOPY_non_ascii.sh.log" -Force
    return $False
} 
else 
{ 
    Write-Output "MD5 checksums are matching"
    Remove-Item -Path "FCOPY_non_ascii.sh.log" -Force
    $results = "Passed"
    $retVal = $True
}

Write-Output "INFO: Test ${results}"
return $retVal
