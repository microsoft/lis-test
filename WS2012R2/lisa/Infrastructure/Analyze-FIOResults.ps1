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

param([string] $testParams)

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
    "Error: RootDir = $rootDir is not a valid path"
    return $false
}

# Source TCUitls.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1")
{
    . .\setupScripts\TCUtils.ps1
}
else
{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}


$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")

    switch ($fields[0].Trim())
    {

    "TestLogDir"                  { $workDir = $fields[1].Trim() }
    default   {}  # unknown param - just ignore it
    }
}
$logDir = $workDir

Write-Host ("--------FIO RESULTS---------")
[regex]$regex = "iops=[0-9]*"


$outItems = New-Object System.Collections.Generic.List[System.Object]

$directories = ls -recurse $logDir\Perf-FIO_Performance_FIO_FIOLog*.log
foreach ( $file in $directories )
{
	$result = @{}
	#write-host ("$file")

	#seq-read:
	$linenumbers = select-string "seq-read:" $file.Fullname | select LineNumber
	write-host ("seq-read:")
	foreach ($line in $LineNumbers)
	{
		$w = select-string $regex -InputObject (get-content $file.Fullname)[$line.LineNumber] -All
		if ($w.matches.value)
		{
			write-host $w.matches.value.split("=")[1]
			$result['seq-read']=$w.matches.value.split("=")[1]
		}
	}

	#rand-read:
	$linenumbers = select-string "rand-read:" $file.Fullname | select LineNumber
	write-host ("")
	write-host ("rand-read:")
	foreach ($line in $LineNumbers)
	{
		$w = select-string $regex -InputObject (get-content $file.Fullname)[$line.LineNumber] -All
		if ($w.matches.value)
		{
			write-host $w.matches.value.split("=")[1]
			$result['rand-read']=$w.matches.value.split("=")[1]
		}
	}

	#seq-write:
	$linenumbers = select-string "seq-write:" $file.Fullname | select LineNumber
	write-host ("")
	write-host ("seq-write:")
	foreach ($line in $LineNumbers)
	{
		$w = select-string $regex -InputObject (get-content $file.Fullname)[$line.LineNumber] -All
		if ($w.matches.value)
		{
			write-host $w.matches.value.split("=")[1]
			$result['seq-write']=$w.matches.value.split("=")[1]
		}
	}

	#rand-write:
	$linenumbers = select-string "rand-write:" $file.Fullname | select LineNumber
	write-host ("")
	write-host ("rand-write:")
	foreach ($line in $LineNumbers)
	{
		$w = select-string $regex -InputObject (get-content $file.Fullname)[$line.LineNumber] -All
		if ($w.matches.value)
		{
			write-host $w.matches.value.split("=")[1]
			$result['rand-write']=$w.matches.value.split("=")[1]
		}
	}
	$a = New-Object System.Management.Automation.PSObject -Property $result
	Export-CSV -InputObject $a -Path $logDir\FIO-Results.csv -Append
}
Write-Host ("--------FIO RESULTS---------")
Write-Host "Archive logs and CSV  are here: $logDir."
Write-Host "------------------------------"