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
    Parse the LISA test log and create a simple XML log file.

.Description
    Parse the LISA test log (ica.log by default), create a simple XML log, and copy it to a test harness running folder.
    
.Parameter LisLogFileName
    The log file produced by LISA. By default it is named ica.log. 

.Parameter XMLLogFileName
    The XML log file name to be created.

.Parameter LogFolder
    A folder to save the script running logs.

.Parameter TestRunWorkingDir
    The test harness folder which needs the XML log file.

.Exmple
    Parse-LisaResultAsXmlLog.ps1 ica.log \\AB803750-2129-436B-AFE6-02F912A3155C.xml D:\Logs F:\TestRunWorkingDir

#>

param( [string]$LisLogFileName = "ica.log", [string]$XMLLogFileName, [string]$LogFolder, [string]$TestRunWorkingDir )

#----------------------------------------------------------------------------
# Start a new PowerShell log.
#----------------------------------------------------------------------------
Start-Transcript "$LogFolder\Parse-LisaResultAsXmlLog.ps1.log" -force

#----------------------------------------------------------------------------
# Print running information
#----------------------------------------------------------------------------
Write-Host "Running [Parse-LisaResultAsXmlLog.ps1]..." -foregroundcolor cyan
Write-Host "`$LisLogFileName   = $LisLogFileName" 
Write-Host "`$XMLLogFileName   = $XMLLogFileName" 
Write-Host "`$LogFolder        = $LogFolder" 
Write-Host "`$TestRunWorkingDir = $TestRunWorkingDir" 

#----------------------------------------------------------------------------
# Verify required parameters
#----------------------------------------------------------------------------
if ($LisLogFileName -eq $null -or $LisLogFileName -eq "")
{
    Throw "Parameter LisLogFileName is required."
}
if ($XMLLogFileName -eq $null -or $XMLLogFileName -eq "")
{
    Throw "Parameter XMLLogFileName is required."
}
if ($LogFolder -eq $null -or $LogFolder -eq "")
{
    Throw "Parameter LogFolder is required."
}
if ($TestRunWorkingDir -eq $null -or $TestRunWorkingDir -eq "")
{
    Throw "Parameter TestRunWorkingDir is required."
}


#----------------------------------------------------------------------------
# Read the Lisa log file
#----------------------------------------------------------------------------
$numberOfPassed = 0
$numberOfFailed = 0
$numberOfAborted = 0

$icaLogs = Get-ChildItem "$LogFolder\$LisLogFileName" -Recurse
Write-Host "Number of Log files found: "
Write-Host $icaLogs.Count

foreach ($logFile  in $icaLogs)
{
    Write-Host "One log file has been found: $logFile" 

    $logContent = get-content $logFile
	$beginToFind = $false
	foreach ($line in $logContent)
	{
	    if ($line -eq "Test Results Summary")
		{
		    $beginToFind = $true
             Write-Host "Starting to look for the test result from the log file..."   
		}
		if ($beginToFind -eq $true)
		{
            Write-host $line
		    if ($line.Trim().StartsWith("Test")) 
            {
                if ($line.Replace(" ", "").Contains(":Success"))
                {
                    $numberOfPassed ++
                    Write-Host ">>>>> One test passed"   
                }
                elseif ($line.Replace(" ", "").Contains(":Failed"))
                {
                    $numberOfFailed ++
                    Write-Host "!!!!! One test failed"   
                }
                elseif ($line.Replace(" ", "").Contains(":Aborted"))
                {
                    $numberOfAborted ++
                    Write-Host "!!!!! One test aborted"   
                }
                else
                {
                    $numberOfUnknown ++
                    Write-Host "!!!!! Cannot understand the test result. Currently accepted results: Success, Failed, Aborted. See the parse logic in StateEngine.ps1, the test completionCode."  
                }
            }
		}
	}
}
$totalTests = $numberOfPassed + $numberOfFailed + $numberOfAborted


#----------------------------------------------------------------------------
# Save it to the XML file format
#----------------------------------------------------------------------------
# Set the File Name
$XMLLogFilePath = "$LogFolder\$XMLLogFileName"
Write-Host "Starting create XML Log file: $XMLLogFilePath " 

# Create The Document
$XmlWriter = New-Object System.XMl.XmlTextWriter($XMLLogFilePath,$Null)
 
$xmlWriter.WriteStartElement("TaskResult")
$xmlWriter.WriteAttributeString("Total", $totalTests)
$xmlWriter.WriteAttributeString("Pass", $numberOfPassed)
$xmlWriter.WriteAttributeString("Failed", $numberOfFailed + $numberOfAborted)
$xmlWriter.WriteAttributeString("Blocked", "0")
$xmlWriter.WriteAttributeString("Warned", "0")
$xmlWriter.WriteAttributeString("Skipped", "0")
$xmlWriter.WriteEndElement()
				
# Finish The Document
$xmlWriter.Finalize
$xmlWriter.Flush
$xmlWriter.Close()

Copy-Item $XMLLogFilePath $TestRunWorkingDir

Write-Host "XML Log file has been created: $XMLLogFilePath " 
Write-Host "Running [Parse-LisaResultAsXmlLog] FINISHED (NOT VERIFIED)."

Stop-Transcript
exit 0