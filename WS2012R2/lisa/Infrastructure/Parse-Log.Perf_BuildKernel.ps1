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

function GetValueFromLog([String] $logFilePath, [String] $key)
{
    <#
    .Synopsis
        Get the value of a key from the specified log file.
        
    .Description
        From the specified text log file, find the key-value pair and return the value part.
        Only return the first item if multiple key-value items existing in the log file.
        The key-value item is formatted as:TheKey=TheValue.
        For example: LinuxRelease=Linux-3.14
        
    .Parameter logFilePath
        A string representing the full path of the text log file.
        Type : [String]
        
    .Parameter key
        A string representing the key.
        Type : [String]
        
    .ReturnValue
        Return the value of the key if found in the log file;
               return empty otherwise.
        Output type : [String]
        
    .Example
        GetValueFromLog $summary.log $linuxRelease
    #>
    
    $retVal = [string]::Empty

    if (-not $logFilePath)
    {
        return $retVal    
    }

    if (-not $key)
    {
        return $retVal
    }

    $resultsMatched = Select-String "$logFilePath" -pattern "$key"
    Write-Host "Number of matches found: " $resultsMatched.Count
    
    $found = $false
    foreach($line in $resultsMatched)
    {
        Write-Host $line
        if ($found -eq $false)
        {
            $lineContent = $line.Line
            if ($lineContent.StartsWith($key + "="))
            {           
                $retVal = $lineContent.Split("=")[1].Trim()
            }
            $found = $true
        }
    }
    
    return $retVal
}


function ParseTimeInSec([string] $rawTime)
{
    <#
    .Synopsis
        Parse the network bandwidth data from the BuildKernel test log.

    .Description
        Parse the network bandwidth data from the BuildKernel test log.
    
    .Parameter LogFolder
        The LISA log folder. 

    .Parameter XMLFileName
        The LISA XML file. 

    .Parameter LisaInfraFolder
        The LISA Infrastructure folder. This is used to located the LisaRecorder.exe when running by Start-Process 

    .Exmple
        Parse-Log.Perf_BuildKernel.ps1 C:\Lisa\TestResults D:\Lisa\XML\Perf_BuildKernel.xml D:\Lisa\Infrastructure

    #>

    #Function to parse time from string
    #result example: 
    #real    4m32.412s
    #user    0m2.388s
    #sys    0m5.832s
    $elements = $rawTime -split '\s+'
    $timeString = $elements[1]
    
    $timeString = $timeString.Trim()
    $posM = $timeString.IndexOf("m")
    $posS = $timeString.IndexOf("s")

    $timeM = $timeString.Substring(0, $posM)
    $timeS = $timeString.Substring($posM + 1, $posS - $posM -1)
    return  [int]$timeM * 60 + [double]$timeS
}


function ParseBenchmarkLogFile( [string]$LogFolder, [string]$XMLFileName )
{
    #----------------------------------------------------------------------------
    # The log file pattern. The log is produced by the BuildKernel tool
    #----------------------------------------------------------------------------
    $BuildKernelLofFiles = "*_BuildKernel_*.log"

    #----------------------------------------------------------------------------
    # Read the BuildKernel log file
    #----------------------------------------------------------------------------
    $icaLogs = Get-ChildItem "$LogFolder\$BuildKernelLofFiles" -Recurse
    Write-Host "Number of Log files found: "
    Write-Host $icaLogs.Count
    
    # there should be 3 log files:
    # Perf_BuildKernel_make.log
    # Perf_BuildKernel_makemodulesinstall.log
    # Perf_BuildKernel_makeinstall.log
    if($icaLogs.Count -ne 3)
    {
        Write-Host "Expecting 3 log files for make, make modulesinstall, and make install."
        return $false
    }

    $realTimeInSec = $null
    $userTimeInSec = $null
    $sysTimeInSec = $null
    foreach ($logFile  in $icaLogs)
    {
        Write-Host "One log file has been found: $logFile" 
        
        #we should find the result in the last 4 line
        #result example: 
        #real    4m32.412s
        #user    0m2.388s
        #sys    0m5.832s
        $resultFound = $false
        $iTry=1
        while (($resultFound -eq $false) -and ($iTry -lt 4))
        {
            $line = (Get-Content $logFile)[-1* $iTry]
            Write-Host $line

            $iTry++
            $line = $line.Trim()
            if ($line.Trim() -eq "")
            {
                continue
            }
            elseif ($line.StartsWith("sys") -eq $true)
            {
                $sysTimeInSec += ParseTimeInSec($line)
                Write-Host "sys time parsed in seconds: $sysTimeInSec" 
                continue
            }
            elseif ($line.StartsWith("user") -eq $true)
            {
                $userTimeInSec += ParseTimeInSec($line)
                Write-Host "user time parsed in seconds: $userTimeInSec" 
                continue
            }
            elseif ($line.StartsWith("real") -eq $true)
            {
                $realTimeInSec += ParseTimeInSec($line)
                Write-Host "real time parsed in seconds: $realTimeInSec" 
                continue
            }
            else
            {
                break
            }
        }
    }
    Write-Host "realTimeInSec = $realTimeInSec"
    Write-Host "userTimeInSec = $userTimeInSec"
    Write-Host "sysTimeInSec  = $sysTimeInSec"
    if (($realTimeInSec -eq $null) -or ($userTimeInSec -eq $null) -or ($sysTimeInSec -eq $null))
    {
        Write-Host "ERROR: Cannot find performance result from the log file"
        return $false
    }
    
    #----------------------------------------------------------------------------
    # Read the test summary log file
    #----------------------------------------------------------------------------
    $TestSummaryLogPattern = "$LogFolder\*\*_summary.log"
   
    $kernelRelease = GetValueFromLog $TestSummaryLogPattern "KernelRelease"
    $processorCount = GetValueFromLog $TestSummaryLogPattern "ProcessorCount"
    if ($kernelRelease -eq [string]::Empty)
    { 
        $kernelRelease = "Unknown"
    }
    if ($processorCount -eq [string]::Empty)
    { 
        $processorCount = "0"
    }

    #----------------------------------------------------------------------------
    # Read BuildKernel configuration from XML file
    #----------------------------------------------------------------------------
    $newLinuxKernel = [string]::Empty
    $xmlConfig = [xml] (Get-Content -Path $xmlFilename)
    foreach($param in $xmlConfig.config.testCases.test.testParams.ChildNodes)
    {
        $paramText = $param.InnerText
        if ($paramText.ToUpper().StartsWith("KERNEL_VERSION="))
        {
            $newLinuxKernel = $paramText.Split('=')[1]
            break
        }
    }

    Write-Host "KernelVersion" $newLinuxKernel

    #----------------------------------------------------------------------------
    # Return to caller script
    #----------------------------------------------------------------------------
    #1st element: the DataTable Name
    $dataTableName = "LisPerfTest_BuildKernel"
    #2nd element: an array of datatable field names for String columns
    $stringFieldNames = New-Object System.Collections.Specialized.StringCollection
    $stringFieldNames.Add("newlinuxkernel")
    #3rdd element: an array of datatable values for String columns
    $stringFieldValues = New-Object System.Collections.Specialized.StringCollection
    $stringFieldValues.Add($newLinuxKernel)
    #4th element: an array of datatable field names for Non-String columns
    $nonStringFieldNames = New-Object System.Collections.Specialized.StringCollection
    $nonStringFieldNames.Add("realtimeinsec")
    $nonStringFieldNames.Add("usertimeinsec")
    $nonStringFieldNames.Add("systimeinsec")
    $nonStringFieldNames.Add("processorcount")
    #5th element: an array of datatable values for Non-String columns
    $nonStringFieldValues = New-Object System.Collections.Specialized.StringCollection
    $nonStringFieldValues.Add($realtimeinsec)
    $nonStringFieldValues.Add($usertimeinsec)
    $nonStringFieldValues.Add($systimeinsec)
    $nonStringFieldValues.Add($processorcount)
    $array = $dataTableName, $stringFieldNames, $stringFieldValues, $nonStringFieldNames, $nonStringFieldValues
    #return the results:
    $array
    return $true
}