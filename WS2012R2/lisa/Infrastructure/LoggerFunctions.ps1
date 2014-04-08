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
    Helper functions for the Lisa automation log parser.

.Description
    The functions in this file are helper functions for the
    the log parsers.

.Link
    None.
#>

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
