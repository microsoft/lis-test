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

param([string] $vmName, [string] $testParams)

# Write out test Params
$testParams

# change working directory to root dir
$testParams -match "RootDir=([^;]+)"
if (-not $?)
{
    "Mandatory param RootDir=Path; not found!"
    return $false
}
$rootDir = $Matches[1]

if (Test-Path $rootDir)
{
    Set-Location -Path $rootDir
    if (-not $?)
    {
        "Error: Could not change directory to $rootDir !"
        return $false
    }
    "Changed working directory to $rootDir"
}
else
{
    "Error: RootDir $rootDir is not a valid path"
    return $false
}

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {
    "TestLogDir" { $workDir = $fields[1].Trim() }
    default      {}  # unknown param - just ignore it
    }
}

#Initialize variables
$logDir = $workDir

$data = new-object PSObject
$tokens = New-Object System.Collections.ArrayList
$tokens.Add("pipelines") | out-null
$tokens.Add("set-time") | out-null
$tokens.Add("set-requests") | out-null
$tokens.Add("get-time") | out-null
$tokens.Add("get-requests") | out-null

$default_percent = "99.95"
$min_diff = 1
$token_rotation = 0

$content = Get-Content $logDir\${vmName}_Perf_Redis_redis.log

foreach ($line in $content)
{
    $aux = $tokens[0]
    if ($aux -match "time")
    {
        if ($line -match "99.9[0-9]%.*")
        {
            $percent = $line.Substring(0,5)
            if ([math]::abs($default_percent - $percent) -lt $min_diff)
            {
                $min_diff = [math]::abs($default_percent - $percent)
                $time = $line.Split(" ")[2]
            }
        }
        else
        {
            if ($line -match "100.00%")
            {
                $percent = $line.Substring(0,5)
                if ([math]::abs($default_percent - $percent) -lt $min_diff)
                {
                    $min_diff = [math]::abs($default_percent - $percent)
                    $time = $line.Split(" ")[2]
                }
                # Change token
                $tokens.Remove($aux) | out-null
                $tokens.Add($aux) | out-null
                $token_rotation = $token_rotation + 1
                $data | add-member -type NoteProperty -Name $aux -Value $time
                $min_diff = 1
            }
        }
    }

    if ($aux -match "pipelines" -And $line -match $aux)
    {
        $tokens.Remove($aux) | out-null
        $tokens.Add($aux) | out-null
        $token_rotation = $token_rotation + 1
        $pipelines = $line.Split(" ")[1]
        $data | add-member -type NoteProperty -Name $aux -Value $pipelines
    }

    if ($aux -match "requests" -And $line -match $aux.Substring(4))
    {
        $tokens.Remove($aux) | out-null
        $tokens.Add($aux) | out-null
        $token_rotation = $token_rotation + 1
        $requests_per_second = $line.Split(" ")[0]
        $data | add-member -type NoteProperty -Name $aux -Value $requests_per_second
    }

    if ($token_rotation -eq 5)
    {
        #Reset the rotation value
        $token_rotation = 0
        Export-CSV -InputObject $data -Path $logDir\Redis-Results.csv -Append
        $data = new-object PSObject
    }
}

Write-Host ("--------FIO RESULTS---------")
Write-Host "Archive logs and CSV are here: $logDir"
Write-Host "------------------------------"
return $True