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
    Parse the network bandwidth data from the iPerf test log.

.Description
    Parse the network bandwidth data from the iPerf test log.
    
.Parameter XMLFileName
    The LISA XML file. 

.Exmple
    Run-TestSpecificLogger.ps1 D:\Lisa\XML\Perf_iPerf.xml

#>

param([string]$XMLFileName)

#----------------------------------------------------------------------------
# Start a new PowerShell log.
#----------------------------------------------------------------------------
Start-Transcript ".\Run-TestSpecificLogger.ps1.log" -force

#----------------------------------------------------------------------------
# Print running information
#----------------------------------------------------------------------------
Write-Host "Running [Run-TestSpecificLogger.ps1]..." -foregroundcolor cyan
Write-Host "`$XMLFileName      = $XMLFileName" 

#----------------------------------------------------------------------------
# Check the parameters
#----------------------------------------------------------------------------
# check the XML file provided
if ($XMLFileName -eq $null -or $XMLFileName -eq "")
{
    Throw "Parameter XMLFileName is required."
}
$xmlConfig = [xml] (Get-Content -Path $xmlFilename)
if ($null -eq $xmlConfig)
{
    write-host -f Red "Error: Unable to parse the .xml file"
    return $false
}
# Get the Log Folder defined in the XML file
$LogFolder = $xmlConfig.config.global.logfileRootDir
Write-Host "Log Folder defined in the XML file: $LogFolder"

#----------------------------------------------------------------------------
# Check the test specific log parser
# the log parser should be Parse-Log.XMLFileName.ps1
#----------------------------------------------------------------------------
Write-Host "Current test running folder:"
$PWD

$XMLFileNameWithoutExt = [io.path]::GetFileNameWithoutExtension($XMLFileName)
#Update - if there are more xml files defined for different test scenarios
#example: Perf_IOZone.l4u4-r32k.xml to test the scenario with 4 IOzone processes and 32KB record size.
$XMLFileNameWithoutExt = $XMLFileNameWithoutExt.split(".")[0]
$lisaInfrsFolder = $PWD.ToString() + "\Infrastructure"

$parserFileName = ".\Infrastructure\Parse-Log." + $XMLFileNameWithoutExt + ".ps1"
if (test-path($parserFileName))
{
    Write-Host "The test specific log parser is found: " $parserFileName
}
else
{
    Write-Host "The test specific log parser does not exist: " $parserFileName 
    Write-Host "Treat this as Feature test result. Parse the XML log file ..."
    $parserFileName = ".\Infrastructure\Parse-Log.FeatureTest.ps1"
	if ($(test-path($parserFileName)) -eq $false)
	{
		Write-Host "The feature test log parser is not found: " $parserFileName
		Throw "No log parser found." 
	}
}

#----------------------------------------------------------------------------
# Run the log parser to parse test results and record them into database
#----------------------------------------------------------------------------
Write-Host "Executing the test specific log parser with below args:"
Write-Host "LogFolder=" $LogFolder
Write-Host "XmlFileName=" $XmlFileName
Write-Host "LisaInfrsFolder=" $lisaInfrsFolder

$job = Start-Job -filepath $parserFileName -argumentList $LogFolder,$XmlFileName,$lisaInfrsFolder
Wait-Job $job | Out-Null

Write-Host "Executing the test specific log parser finished. See the executing log as below:"
Write-Host "--------------------------------------------------------------------------------"
#receive the content (array) *Return*ed from the job script (not *exit*)
$returnsFromlogger = Receive-Job $job
Write-Host "--------------------------------------------------------------------------------"

Remove-Job $job
#the last line of the content is the script exit code
$loggerExitCode = $returnsFromlogger[-1]
Write-Host "The logger returned error code: " $loggerExitCode

Write-Host "Running [Run-TestSpecificLogger] FINISHED (NOT VERIFIED)."
Stop-Transcript
move ".\Run-TestSpecificLogger.ps1.log" $LogFolder -force
exit $loggerExitCode