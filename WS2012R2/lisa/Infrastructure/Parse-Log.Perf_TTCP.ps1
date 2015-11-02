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
    Parse the network bandwidth data from the TTCP test log.

.Description
    Parse the network bandwidth data from the TTCP test log.
    
.Parameter LogFolder
    The LISA log folder. 

.Parameter XMLFileName
    The LISA XML file. 

.Parameter LisaInfraFolder
    The LISA Infrastructure folder. This is used to located the LisaRecorder.exe when running by Start-Process 

.Exmple
    Parse-Log.Perf_TTCP.ps1 C:\Lisa\TestResults D:\Lisa\XML\Perf_TTCP.xml D:\Lisa\Infrastructure

#>

function ParseBenchmarkLogFile( [string]$LogFolder, [string]$XMLFileName )
{
    #----------------------------------------------------------------------------
    # The log file pattern. The log is produced by the TTCP tool
    #----------------------------------------------------------------------------
    $TTCPLofFile = "*_ttcp.log"

    #----------------------------------------------------------------------------
    # Read the TTCP log file
    #----------------------------------------------------------------------------
    $icaLogs = Get-ChildItem "$LogFolder\$TTCPLofFile" -Recurse
    Write-Host "Number of Log files found: "
    Write-Host $icaLogs.Count

    if($icaLogs.Count -eq 0)
    {
        return $false
    }

    $throughputinkbsec = $null
    # should only have one file. but in case there are more than one files, just use the last one simply
    foreach ($logFile  in $icaLogs)
    {
        Write-Host "One log file has been found: $logFile" 
        
        #we should find the result in the second line
        #result example: ttcp-t: 536870912 bytes in 2.61 real seconds = 200675.18 KB/sec +++
        $line = (Get-Content $logFile)[1]
        Write-Host $line

        $line = $line.Trim()
        if ($line.Trim() -eq "")
        {
            continue
        }
        elseif ( ($line.StartsWith("ttcp-t:") -eq $false) -or ($line.Contains("bytes in") -eq $false) -or ($line.Contains("real seconds") -eq $false))
        {
            continue
        }
        else
        {
            $element = $line.Split(' ')
            $throughputinkbsec = $element[$element.Length-3]
            Write-Host "The networking throughput is: " $throughputinkbsec  "(KB/sec)"
            break
        }
    }
    Write-Host "ThroughputInKBSec = $throughputinkbsec"
    if ($throughputinkbsec -eq $null)
    {
        Write-Host "ERROR: Cannot find performance result from the log file"
        return $false
    }

    #----------------------------------------------------------------------------
    # Return to caller script
    #----------------------------------------------------------------------------
    #1st element: the DataTable Name
    $dataTableName = "LisPerfTest_TTCP"
    #2nd element: an array of datatable field names for String columns
    $stringFieldNames = $null 
    #3rdd element: an array of datatable values for String columns
    $stringFieldValues = $null
    #4th element: an array of datatable field names for Non-String columns
    $nonStringFieldNames = New-Object System.Collections.Specialized.StringCollection
    $nonStringFieldNames.Add("throughputinkbsec")
    #5th element: an array of datatable values for Non-String columns
    $nonStringFieldValues = New-Object System.Collections.Specialized.StringCollection
    $nonStringFieldValues.Add($throughputinkbsec)

    $array = $dataTableName, $stringFieldNames, $stringFieldValues, $nonStringFieldNames, $nonStringFieldValues
    #return the results:
    $array
    return $true
}

