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

function ParseBenchmarkLogFile( [string]$LogFolder, [string]$XMLFileName )
{
    # this is the XML log file parsed from LISA log for Atlas use
    $xmlResultFiles = Get-ChildItem "$LogFolder\*-*-*-*-*.xml"

    #----------------------------------------------------------------------------
    # Read the log file
    #----------------------------------------------------------------------------
    Write-Host "Number of Log files found: "
    Write-Host $xmlResultFiles.Count

    if($xmlResultFiles.Count -eq 0)
    {
        return $false
    }

    $passed = 0
    $failed = 0
    $aborted = 0
    foreach ($logFile in $xmlResultFiles)
    {
        Write-Host "A XML result file was found: " $logFile.FullName
        $xmlFile = [xml] (Get-Content -Path $logFile)
        if ($null -eq $xmlFile)
        {
            continue
        }
        elseif ($xmlFile.FirstChild.Name -ne "TaskResult")
        {
            continue
        }
        else
        {
            $passed = $xmlFile.FirstChild.Pass
            $failed = $xmlFile.FirstChild.Failed
            $aborted = 0  #unused
        }
    }

    #----------------------------------------------------------------------------
    # Return to caller script
    #----------------------------------------------------------------------------
    #1st element: the DataTable Name
    $dataTableName = "LisFeatureTest"
    #2nd element: an array of datatable field names for String columns
    $stringFieldNames = New-Object System.Collections.Specialized.StringCollection
    $stringFieldNames.Add("TestTime")
    #3rdd element: an array of datatable values for String columns
    $stringFieldValues = New-Object System.Collections.Specialized.StringCollection
    $stringFieldValues.Add([DATETIME]::NOW.ToString("yyyy-MM-dd HH:mm:ss"))  
    #4th element: an array of datatable field names for Non-String columns
    $nonStringFieldNames = New-Object System.Collections.Specialized.StringCollection
    $nonStringFieldNames.Add("passed")
    $nonStringFieldNames.Add("failed")
    $nonStringFieldNames.Add("aborted")  
    #5th element: an array of datatable values for Non-String columns
    $nonStringFieldValues = New-Object System.Collections.Specialized.StringCollection
    $nonStringFieldValues.Add($passed)
    $nonStringFieldValues.Add($failed)
    $nonStringFieldValues.Add($aborted)
    
    $array = $dataTableName, $stringFieldNames, $stringFieldValues, $nonStringFieldNames, $nonStringFieldValues
    #return the results:
    $array
    return $true
}
