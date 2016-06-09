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
    Parse the ICMP ping data from the test log results.

.Parameter XMLFileName
    The LISA XML file used for the test run. 

.Exmple
    Parse-Log.Perf_Ping.ps1 D:\Lisa\XML\ping_icmp.xml
#>

function ParseBenchmarkLogFile( [string]$LogFolder, [string]$XMLFileName ) {
    $latencyInMS = $null
    
    #----------------------------------------------------------------------------
    # The log file pattern. The log is produced by the Ping tool
    #----------------------------------------------------------------------------
    $PingLogFile = "*__Ping_IPv4_summary.log"

    #----------------------------------------------------------------------------
    # Read the Ping log file
    #----------------------------------------------------------------------------
    $icaLogs = Get-ChildItem "$LogFolder\$PingLogFile" -Recurse
    Write-Host "Number of log files found: "
    Write-Host $icaLogs.Count

    if($icaLogs.Count -eq 0) {
        return $false
    }

    # should only have one file. but in case there are more than one files, just simply use the last one
    foreach ($logFile  in $icaLogs) {
        Write-Host "One log file has been found: $logFile" 
        
        #we should find the results in the second line
        #results example: rtt min/avg/max/mdev = 0.280/1.121/4.796/1.644 ms
        [string]$line = (Get-Content $logFile | Select-String -pattern "rtt min/avg/max/mdev")
        Write-Host "Found line that contains the results: $line"

        $element = $line.Split('=')
        $elementValue = $element[1].Split('/')
        $latencyInMS = $elementValue[0].Trim()
        Write-Host "The min latency is: " $latencyInMS  "(ms)"
    }

    Write-Host "LatencyInMS = $latencyInMS"
    if ($latencyInMS -eq $null) {
        Write-Host "ERROR: Cannot find performance result from the log file!"
        return $false
    }

    #----------------------------------------------------------------------------
    # Return to caller script
    #----------------------------------------------------------------------------
    #1st element: the DataTable Name
    $dataTableName = "LisPerfTest_Ping"
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
