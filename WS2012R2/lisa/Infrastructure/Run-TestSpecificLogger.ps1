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
    
.Parameter LogFolder
    The LISA log folder. 

.Parameter XMLFileName
    The LISA XML file. 

.Exmple
    Run-TestSpecificLogger.ps1 C:\Lisa\TestResults D:\Lisa\XML\Perf_iPerf.xml

#>

param( [string]$LogFolder, [string]$XMLFileName)

#----------------------------------------------------------------------------
# Start a new PowerShell log.
#----------------------------------------------------------------------------
Start-Transcript "$LogFolder\Run-TestSpecificLogger.ps1.log" -force

#----------------------------------------------------------------------------
# Print running information
#----------------------------------------------------------------------------
Write-Host "Running [Run-TestSpecificLogger.ps1]..." -foregroundcolor cyan
Write-Host "`$LogFolder        = $LogFolder" 
Write-Host "`$XMLFileName      = $XMLFileName" 

#----------------------------------------------------------------------------
# If the test specific log parser exists, run it
# the log parser should be Parse-Log.XMLFileName.ps1
#----------------------------------------------------------------------------
# check the XML file provided
if ($XMLFileName -eq $null -or $XMLFileName -eq "")
{
    Throw "Parameter XMLFileName is required."
}
Write-Host "Current test running folder:"
$PWD

$XMLFileNameWithoutExt = [io.path]::GetFileNameWithoutExtension($XMLFileName)
$lisaInfrsFolder = $PWD.ToString() + "\Infrastructure"

$parserFileName = ".\Infrastructure\Parse-Log." + $XMLFileNameWithoutExt + ".ps1"
if (test-path($parserFileName))
{
    Write-Host "The test specific log parser is found: " $parserFileName
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
}
else
{
     Write-Host "The test specific log parser does not exist: " $parserFileName 
}

Write-Host "Running [Run-TestSpecificLogger] FINISHED (NOT VERIFIED)."

Stop-Transcript
exit $loggerExitCode