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
    Parse the network bandwidth data from the Ping test log.

.Description
    Parse the network bandwidth data from the Ping test log.
    
.Parameter LogFolder
    The LISA log folder. 

.Parameter XMLFileName
    The LISA XML file. 

.Parameter LisaInfraFolder
    The LISA Infrastructure folder. This is used to located the LisaRecorder.exe when running by Start-Process 

.Exmple
    Parse-Log.Perf_Ping.ps1 C:\Lisa\TestResults D:\Lisa\XML\Perf_Ping.xml D:\Lisa\Infrastructure

#>

param( [string]$LogFolder, [string]$XMLFileName, [string]$LisaInfraFolder )

#----------------------------------------------------------------------------
# Print running information
#----------------------------------------------------------------------------
Write-Host "Running [Parse-Log.Perf_Ping.ps1]..." -foregroundcolor cyan
Write-Host "`$LogFolder        = $LogFolder" 
Write-Host "`$XMLFileName      = $XMLFileName" 
Write-Host "`$LisaInfraFolder  = $LisaInfraFolder" 

#----------------------------------------------------------------------------
# Verify required parameters
#----------------------------------------------------------------------------
if ($LogFolder -eq $null -or $LogFolder -eq "")
{
    Throw "Parameter LogFolder is required."
}

# check the XML file provided
if ($XMLFileName -eq $null -or $XMLFileName -eq "")
{
    Throw "Parameter XMLFileName is required."
}
else
{
    if (! (test-path $XMLFileName))
    {
        write-host -f Red "Error: XML config file '$XMLFileName' does not exist."
        Throw "Parameter XmlFilename is required."
    }
}

$xmlConfig = [xml] (Get-Content -Path $xmlFilename)
if ($null -eq $xmlConfig)
{
    write-host -f Red "Error: Unable to parse the .xml file"
    return $false
}

if ($LisaInfraFolder -eq $null -or $LisaInfraFolder -eq "")
{
    Throw "Parameter LisaInfraFolder is required."
}

#----------------------------------------------------------------------------
# The log file pattern. The log is produced by the Ping tool
#----------------------------------------------------------------------------
$PingLofFile = "*_ping.log"

#----------------------------------------------------------------------------
# Read the Ping log file
#----------------------------------------------------------------------------
$icaLogs = Get-ChildItem "$LogFolder\$PingLofFile" -Recurse
Write-Host "Number of Log files found: "
Write-Host $icaLogs.Count

if($icaLogs.Count -eq 0)
{
    return -1
}

$latencyInMS = "0"
# should only have one file. but in case there are more than one files, just use the last one simply
foreach ($logFile  in $icaLogs)
{
    Write-Host "One log file has been found: $logFile" 
    
    #we should find the result in the second line
    #result example: rtt min/avg/max/mdev = 0.280/1.121/4.796/1.644 ms
    $resultFound = $false
    $iTry=1
    while (($resultFound -eq $false) -and ($iTry -lt 3))
    {
        $line = (Get-Content $logFile)[-1* $iTry]
        Write-Host $line

        if ($line.Trim() -eq "")
        {
            $iTry++
            continue
        }
        elseif ( ($line.StartsWith("rtt min/avg/max/mdev") -eq $false) -or ($line.Contains("=") -eq $false) -or ($line.Contains("ms") -eq $false))
        {
            $iTry++
            continue
        }
        else
        {
            $element = $line.Split('=')
            $elementValue = $element[1].Split('/')
            $latencyInMS = $elementValue[0].Trim()
            Write-Host "The min latency is: " $latencyInMS  "(ms)"
            break
        }
    }
}

#----------------------------------------------------------------------------
# Read Ping configuration from XML file
#----------------------------------------------------------------------------
$VMName = [string]::Empty
$numberOfVMs = $xmlConfig.config.VMs.ChildNodes.Count
Write-Host "Number of VMs defined in the XML file: $numberOfVMs"
if ($numberOfVMs -eq 0)
{
    Throw "No VM is defined in the LISA XML file."
}
elseif ($numberOfVMs -gt 1)
{
    foreach($node in $xmlConfig.config.VMs.ChildNodes)
    {
        if (($node.role -eq $null) -or ($node.role.ToLower() -ne "nonsut"))
        {
            #just use the 1st SUT VM name
            $VMName = $node.vmName
            break
        }
    }
}
else
{
    $VMName = $xmlConfig.config.VMs.VM.VMName
}
if ($VMName -eq [string]::Empty)
{
    Write-Host "!!! No VM is found from the LISA XML file."
}
Write-Host "VMName: " $VMName
$XMLFileNameWithoutExt = [io.path]::GetFileNameWithoutExtension($XMLFileName)

#----------------------------------------------------------------------------
# Call LisaRecorder to log data into database
#----------------------------------------------------------------------------
$LisaRecorder = "$LisaInfraFolder\LisaLogger\LisaRecorder.exe"
$params = "LisPerfTest_Ping"
$params = $params+" "+"hostos:`"" + (Get-WmiObject -class Win32_OperatingSystem).Caption + "`""
$params = $params+" "+"hostname:`"" + "$env:computername.$env:userdnsdomain" + "`""
$params = $params+" "+"guestos:`"" + "Linux" + "`""
$params = $params+" "+"linuxdistro:`"" + "$VMName" + "`""
$params = $params+" "+"testcasename:`"" + $XMLFileNameWithoutExt + "`""

$params = $params+" "+"latencyinms:`"" + $latencyInMS + "`""

Write-Host "Executing LisaRecorder to record test result into database"
Write-Host $params

$result = Start-Process -FilePath $LisaRecorder -Wait -ArgumentList $params -PassThru -RedirectStandardOutput "$LogFolder\LisaRecorderOutput.log" -RedirectStandardError "$LogFolder\LisaRecorderError.log"
if ($result.ExitCode -eq 0)
{
    Write-Host "Executing LisaRecorder finished with Success."
}
else
{
    Write-Host "Executing LisaRecorder failed with exit code: " $result.ExitCode
}

return $result.ExitCode

