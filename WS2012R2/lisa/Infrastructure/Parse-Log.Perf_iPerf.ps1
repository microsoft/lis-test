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

.Parameter LisaInfraFolder
    The LISA Infrastructure folder. This is used to located the LisaRecorder.exe when running by Start-Process 

.Exmple
    Parse-Log.Perf_iPerf.ps1 C:\Lisa\TestResults D:\Lisa\XML\Perf_iPerf.xml D:\Lisa\Infrastructure

#>

function ParseBenchmarkLogFile( [string]$LogFolder, [string]$XMLFileName )
{
    #----------------------------------------------------------------------------
    # The log file pattern. The log is produced by the iPerf tool
    #----------------------------------------------------------------------------
    $iPerfLofFile = "*_iperfdata.log"

    #----------------------------------------------------------------------------
    # Read the iPerf log file
    #----------------------------------------------------------------------------
    $icaLogs = Get-ChildItem "$LogFolder\$iPerfLofFile" -Recurse
    Write-Host "Number of Log files found: "
    Write-Host $icaLogs.Count

    if($icaLogs.Count -eq 0)
    {
        return $false
    }

    $bandwidth = $null
    # should only have one file. but in case there are more than one files, just use the last one simply
    foreach ($logFile  in $icaLogs)
    {
        Write-Host "One log file has been found: $logFile" 
        
        #we should find the result in the last 2 lines
        #result example: [  3]  0.0-60.0 sec  11.9 GBytes  1.70 Gbits/sec
        #result example: [SUM]  0.0-60.0 sec  11.5 GBytes  1.65 Gbits/sec
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
            elseif ( ($line.Contains("sec") -eq $false) -or  ($line.Contains("bits/sec") -eq $false))
            {
                $iTry++
                continue
            }
            else
            {
                $element = $line.Split(' ')
                $bandwidth = $element[$element.Length-2]
                Write-Host "The bandwidth is: " $bandwidth  $element[$element.Length-1]
                break
            }
        }
    }
    Write-Host "bandwidth = $bandwidth"
    if ($bandwidth -eq $null)
    {
        Write-Host "ERROR: Cannot find performance result from the log file"
        return $false
    }

    #----------------------------------------------------------------------------
    # Read iPerf configuration from XML file
    #----------------------------------------------------------------------------
    $IPERF_THREADS = $null
    $IPERF_BUFFER = $null
    $IPERF_TCPWINDOW = $null
    $xmlConfig = [xml] (Get-Content -Path $xmlFilename)
    foreach($param in $xmlConfig.config.testCases.test.testParams.ChildNodes)
    {
        $paramText = $param.InnerText
        if ($paramText.ToUpper().StartsWith("IPERF_THREADS="))
        {
            $IPERF_THREADS = $paramText.Split('=')[1]
        }
        if ($paramText.ToUpper().StartsWith("IPERF_BUFFER="))
        {
            $IPERF_BUFFER = $paramText.Split('=')[1]
        }
        if ($paramText.ToUpper().StartsWith("IPERF_TCPWINDOW="))
        {
            $IPERF_TCPWINDOW = $paramText.Split('=')[1]
        }
    }

    Write-Host "IPERF_THREADS:   $IPERF_THREADS"
    Write-Host "IPERF_BUFFER:    $IPERF_BUFFER"
    Write-Host "IPERF_TCPWINDOW: $IPERF_TCPWINDOW"

    #----------------------------------------------------------------------------
    # Return to caller script
    #----------------------------------------------------------------------------
    #1st element: the DataTable Name
    $dataTableName = "LisPerfTest_iPerf"
    #2nd element: an array of datatable field names for String columns
    $stringFieldNames = New-Object System.Collections.Specialized.StringCollection 
    $stringFieldNames.Add("TCPWindowInKB")
    $stringFieldNames.Add("BufferLenInKB")
    #3rdd element: an array of datatable values for String columns
    $stringFieldValues = New-Object System.Collections.Specialized.StringCollection
    $stringFieldValues.Add($IPERF_TCPWINDOW)
    $stringFieldValues.Add($IPERF_BUFFER)
    #4th element: an array of datatable field names for Non-String columns
    $nonStringFieldNames = New-Object System.Collections.Specialized.StringCollection
    $nonStringFieldNames.Add("BandwidthInGbits")
    $nonStringFieldNames.Add("ParallelThreads")
    #5th element: an array of datatable values for Non-String columns
    $nonStringFieldValues = New-Object System.Collections.Specialized.StringCollection
    $nonStringFieldValues.Add($bandwidth)
    $nonStringFieldValues.Add($IPERF_THREADS)

    $array = $dataTableName, $stringFieldNames, $stringFieldValues, $nonStringFieldNames, $nonStringFieldValues
    #return the results:
    $array
    return $true
}