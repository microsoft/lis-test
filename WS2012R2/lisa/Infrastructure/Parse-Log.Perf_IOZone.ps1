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
    Parse the network bandwidth data from the IOZone test log.

.Description
    Parse the network bandwidth data from the IOZone test log.
    
.Parameter LogFolder
    The LISA log folder. 

.Parameter XMLFileName
    The LISA XML file. 

.Parameter LisaInfraFolder
    The LISA Infrastructure folder. This is used to located the LisaRecorder.exe when running by Start-Process 

.Exmple
    Parse-Log.Perf_IOZone.ps1 C:\Lisa\TestResults D:\Lisa\XML\Perf_IOZone.xml D:\Lisa\Infrastructure

#>

param( [string]$LogFolder, [string]$XMLFileName, [string]$LisaInfraFolder )

#----------------------------------------------------------------------------
# Print running information
#----------------------------------------------------------------------------
Write-Host "Running [Parse-Log.Perf_IOZone.ps1]..." -foregroundcolor cyan
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
# The log file pattern. The log is produced by the IOZone tool
#----------------------------------------------------------------------------
$IOZoneLofFile = "*_IOZoneLog.log"

#----------------------------------------------------------------------------
# Read the IOZone log file
#----------------------------------------------------------------------------
$icaLogs = Get-ChildItem "$LogFolder\$IOZoneLofFile" -Recurse
Write-Host "Number of Log files found: "
Write-Host $icaLogs.Count

if($icaLogs.Count -eq 0)
{
    return -1
}

$Initialwrite = "0"
$Rewrite = "0"
$Read = "0"
$Reread = "0"
$Randomread = "0"
$Randomwrite = "0"
# should only have one file. but in case there are more than one files, just use the last one simply
foreach ($logFile  in $icaLogs)
{
    Write-Host "One log file has been found: $logFile" 
    
    #we should find the result in the last 17 lines
    #result example: 
    #"Throughput report Y-axis is type of test X-axis is number of processes"
    #"Record size = 4 Kbytes "
    #"Output is in Kbytes/sec"
    #    
    #"  Initial write "  761841.69 
    #
    #"        Rewrite "  520879.19 
    #
    #"           Read "  724325.25 
    #
    #"        Re-read "  797489.25 
    #
    #"    Random read "  656360.38 
    #
    #"   Random write " 1125040.50 
    #
    #    
    #iozone test complete.
    #
    
    $resultFound = $false
    $iTry=1
    while (($resultFound -eq $false) -and ($iTry -lt 18))
    {
        $line = (Get-Content $logFile)[-1* $iTry]
        Write-Host $line
        $line=$line.Trim().Replace(" ","")
        
        $iTry++
        if ($line.Trim() -eq "")
        {
            continue
        }
        elseif ( $line.Contains("Initialwrite") -eq $true )
        {
            $Initialwrite =$line.Split("`"")[2]
            continue
        }
        elseif ( $line.Contains("Rewrite") -eq $true )
        {
            $Rewrite =$line.Split("`"")[2]
            continue
        }
        elseif ( $line.Contains("Read") -eq $true )
        {
            $Read =$line.Split("`"")[2]
            continue
        }
        elseif ( $line.Contains("Re-read") -eq $true )
        {
            $Reread =$line.Split("`"")[2]
            continue
        }
        elseif ( $line.Contains("Randomread") -eq $true )
        {
            $Randomread =$line.Split("`"")[2]
            continue
        }
        elseif ( $line.Contains("Randomwrite") -eq $true )
        {
            $Randomwrite =$line.Split("`"")[2]
            continue
        }
        else
        {
            continue
        }
    }
}

#----------------------------------------------------------------------------
# Read IOZone configuration from XML file
#----------------------------------------------------------------------------
#get the VM name
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

#get IOZone parameters
$RecordSize = ""
$NProcLowLimit = 1
$NProcUpperLimit = 1
$NPosixAsyncIO = 8
$IOZoneParams = ""
foreach($param in $xmlConfig.config.testCases.test.testParams.ChildNodes)
{
    $paramText = $param.InnerText
    if ($paramText.ToUpper().StartsWith("IOZONE_PARAMS="))
    {
        $IOZoneParams = $paramText.Split('=')[1]
        break
    }
}
if ($IOZoneParams -ne "")
{
    $IOZoneParams = $IOZoneParams.Replace("'","")
    $listParams = $IOZoneParams.split("-")
    foreach ($p in $listParams)
    {
        if ($p.StartsWith("r"))
        {
            $RecordSize = $p.Replace("r","").Trim()
        }
        elseif ($p.StartsWith("l"))
        {
            $NProcLowLimit = $p.Replace("l","").Trim()
        }
        elseif ($p.StartsWith("u"))
        {
            $NProcUpperLimit = $p.Replace("u","").Trim()
        }
        elseif ($p.StartsWith("k"))
        {
            $NPosixAsyncIO = $p.Replace("k","").Trim()
        }
    }
}

Write-Host "IOZoneParams: " $IOZoneParams
Write-Host "RecordSize:" $RecordSize
Write-Host "NProcLowLimit:" $NProcLowLimit 
Write-Host "NProcUpperLimit:" $NProcUpperLimit 
Write-Host "NPosixAsyncIO:" $NPosixAsyncIO 
$XMLFileNameWithoutExt = [io.path]::GetFileNameWithoutExtension($XMLFileName)

#----------------------------------------------------------------------------
# Call LisaRecorder to log data into database
#----------------------------------------------------------------------------
$LisaRecorder = "$LisaInfraFolder\LisaLogger\LisaRecorder.exe"
$params = "LisPerfTest_IOZone"
$params = $params+" "+"hostos:`"" + (Get-WmiObject -class Win32_OperatingSystem).Caption + "`""
$params = $params+" "+"hostname:`"" + "$env:computername.$env:userdnsdomain" + "`""
$params = $params+" "+"guestos:`"" + "Linux" + "`""
$params = $params+" "+"linuxdistro:`"" + "$VMName" + "`""
$params = $params+" "+"testcasename:`"" + $XMLFileNameWithoutExt + "`""

$params = $params+" "+"initialwritekbsec:`"" + $Initialwrite + "`""
$params = $params+" "+"rewritekbsec:`"" + $Rewrite + "`""
$params = $params+" "+"readkbsec:`"" + $Read + "`""
$params = $params+" "+"rereadkbsec:`"" + $Reread + "`""
$params = $params+" "+"randomreadkbsec:`"" + $Randomread + "`""
$params = $params+" "+"randomwritekbsec:`"" + $Randomwrite + "`""

$params = $params+" "+"recordsize:`"" + $RecordSize + "`""
$params = $params+" "+"nproclowlimit:`"" + $NProcLowLimit + "`""
$params = $params+" "+"nprocupperlimit:`"" + $NProcUpperLimit + "`""
$params = $params+" "+"nposixasyncio:`"" + $NPosixAsyncIO + "`""
$params = $params+" "+"iozoneparams:`"" + $IOZoneParams + "`""

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

