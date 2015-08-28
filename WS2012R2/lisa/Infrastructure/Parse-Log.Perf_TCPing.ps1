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
    Parse the network bandwidth data from the TCPing test log.

.Description
    Parse the network bandwidth data from the TCPing test log.
    
.Parameter LogFolder
    The LISA log folder. 

.Parameter XMLFileName
    The LISA XML file. 

.Parameter LisaInfraFolder
    The LISA Infrastructure folder. This is used to located the LisaRecorder.exe when running by Start-Process 

.Exmple
    Parse-Log.Perf_TCPing.ps1 C:\Lisa\TestResults D:\Lisa\XML\Perf_TCPing.xml D:\Lisa\Infrastructure

#>

function ParseBenchmarkLogFile( [string]$LogFolder, [string]$XMLFileName )
{
    #----------------------------------------------------------------------------
    # The log file pattern. The log is produced by the TCPing tool
    #----------------------------------------------------------------------------
    $TCPingLofFile = "*_tcping.log"

    #----------------------------------------------------------------------------
    # Read the TCPing log file
    #----------------------------------------------------------------------------
    $icaLogs = Get-ChildItem "$LogFolder\$TCPingLofFile" -Recurse
    Write-Host "Number of Log files found: "
    Write-Host $icaLogs.Count

    if($icaLogs.Count -eq 0)
    {
        return $false
    }

    $latencyInMS = $null
    # should only have one file. but in case there are more than one files, just use the last one simply
    foreach ($logFile  in $icaLogs)
    {
        Write-Host "One log file has been found: $logFile" 
        
        #we should find the result in the last line
        #use the "min" as the factor
        #result example:   min = 1.213, avg = 1.778, max = 1.923
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
            elseif ( ($line.StartsWith("min") -eq $false) -or ($line.Contains("avg") -eq $false) -or ($line.Contains("max") -eq $false))
            {
                $iTry++
                continue
            }
            else
            {
                $element = $line.Split(',')
                $latencyInMS = $element[0].Replace("min","").Replace("=","").Trim()
                Write-Host "The min latency is: " $latencyInMS  "(ms)"
                break
            }
        }
    }
    Write-Host "LatencyInMS = $latencyInMS"
    if ($latencyInMS -eq $null)
    {
        Write-Host "ERROR: Cannot find performance result from the log file"
        return $false
    }

    #----------------------------------------------------------------------------
    # Return to caller script
    #----------------------------------------------------------------------------
    #1st element: the DataTable Name
    $dataTableName = "LisPerfTest_TCPing"
    #2nd element: an array of datatable field names for String columns
    $stringFieldNames = $null 
    #3rdd element: an array of datatable values for String columns
    $stringFieldValues = $null
    #4th element: an array of datatable field names for Non-String columns
    $nonStringFieldNames = New-Object System.Collections.Specialized.StringCollection
    $nonStringFieldNames.Add("LatencyInMS")
    #5th element: an array of datatable values for Non-String columns
    $nonStringFieldValues = New-Object System.Collections.Specialized.StringCollection
    $nonStringFieldValues.Add($latencyInMS)

    $array = $dataTableName, $stringFieldNames, $stringFieldValues, $nonStringFieldNames, $nonStringFieldValues
    #return the results:
    $array
    return $true
}
