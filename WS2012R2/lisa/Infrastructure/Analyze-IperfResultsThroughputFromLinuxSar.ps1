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

param([string] $vmName, [string] $hvServer, [string] $testParams)

#
# Check input arguments
#
if ($vmName -eq $null)
{
    "Error: VM name is null"
    return $False
}

if ($hvServer -eq $null)
{
    "Error: hvServer is null"
    return $False
}

if ($testParams -eq $null)
{
    "Error: testParams is null"
    return $False
}

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
    "IPERF3_TEST_CONNECTION_POOL" { $testConnections = $fields[1].Trim() }
    "INDIVIDUAL_TEST_DURATION"    { $testDuration  = $fields[1].Trim() }
    "TEST_RUN_LOG_FOLDER"         { $logFolder    = $fields[1].Trim() }
    "VM2NAME"                     { $vm2Name    = $fields[1].Trim() }
    "VM2SERVER"                   { $vm2Server    = $fields[1].Trim() }
    "TestLogDir"                  { $testDirectory = $fields[1].Trim() }
    "testName"                    { $TestName = $fields[1].Trim() }
    default   {}  # unknown param - just ignore it
    }
}

if (-not $testConnections)
{
    "Error: test parameter IPERF3_TEST_CONNECTION_POOL was not specified"
    return $False
}

if (-not $testDuration)
{
    "Error: test parameter INDIVIDUAL_TEST_DURATION was not specified"
    return $False
}

if (-not $logFolder)
{
    "Error: test parameter TEST_RUN_LOG_FOLDER was not specified"
    return $False
}

if (-not $testDirectory)
{
    "Error: Could not find Test Results folder"
    return $False
}

if (-not $vm2Name)
{
    "Warning: vm2Name is missing!"
}

if (-not $vm2Server)
{
    "Warning: The second VMs server is not specified!"
}

$archive = "${testDirectory}\${vmName}_${TestName}_iPerf3_Server_Logs.zip"
$destination = "${testDirectory}\"

Add-Type -assembly "system.io.compression.filesystem"
[io.compression.zipfile]::ExtractToDirectory($archive, $destination)

if (-not $?) {
    write-host "Error: Could not extract the archive, try to extract it manually. If it doesn't exist, check on $vm2Name VM."
    return $False
}

#Get Test Interface and Distribution
$testInterface = Get-Content ${testDirectory}\*ServerSideScript.log | where { $_ -match "TestInterface" }
$testInterface = $testInterface.Substring(15)

$distro = Get-Content ${testDirectory}\*_summary.log | where { $_ -match "Distribution" }
$distro = $distro.Substring(14)

#set number of columns in sar log file according to distribution
if ($distro -like "suse_12") {
    [int] $columns = 4
}
else {
    [int] $columns = 5
}

$logPath = "${testDirectory}\root\${logFolder}"
$resultFile = Join-Path $logPath "sar.log"
$avgFile = Join-Path $logPath "sar-avg.log"
$ethName = "$testInterface"

If (Test-Path $resultFile)
{
    write-host "Result File Exists! It will be overwritten after 1 second." -foregroundcolor red
    Remove-Item $resultFile
}

If (Test-Path $avgFile)
{
    write-host "AVERAGE Result File Exists! It will be overwritten after 1 second." -foregroundcolor red
    Remove-Item $avgFile
}

write-host "Parse logs from $logPath ..."

$connections = $testConnections.Substring(1,$testConnections.Length-2)

$connections = $connections.Split(" ")

write-host " "
write-host "------------------------------------"
write-host "| Connections     Bandwidth (Gb/s) |"
write-host "------------------------------------"

foreach ($conn in $connections)
{
    #$gtotal is used to calculate average throughput
    $gtotal=0
    $gAvg=0

    $sarfile =  $logPath + "\" + $conn + "\" + "sar.log"
    #$sarfile =  $logPath + "\" + $conn + "-" + "sar.log"
    $lines = (Get-Content $sarfile)

    $count = [int] $testDuration
    $lastGoodOne = 0
    for ($i = 0; $i -lt $lines.Length - 1; $i++)
    {
        if ($count -eq 0)
        {
            break
        }
        $line = $lines[$i]

        IF([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line.Contains($ethName) -eq $false)
        {
            continue
        }
        else
        {
            $line = $line -Replace '\s+', ' '
            #write-host $line.Split(" ")
            $netThrEth0 = $line.Split(" ")[$columns]
            if (($netThrEth0 -as [double]) -gt 100000)
            {
                echo $netThrEth0 >> $resultFile
                $lastGoodOne = $netThrEth0
                $gtotal = $gtotal + [double]$netThrEth0
                $count = $count -1
            }
        }
    }

    if ($testDuration-$count -gt 0) {
       $gAvg = $gtotal * 8 / 1000 / 1000 / ($testDuration - $count)
    }

    if ($count -gt 0)
    {
        for ($x =$count; $x -ne 0; $x--)
        {
                echo $lastGoodOne >> $resultFile
        }
    }
    #echo $conn + " "+ $gAvg >> $avgFile
    $conn + " "+ $gAvg | out-file $avgFile -append
    write-host " $conn           $gAvg"
}

# Perform clean-up for future parsing of new logs
New-Item $testdirectory\parsed\ -ItemType Directory -Force | Out-Null
Get-ChildItem -Path $testdirectory\iperf-client*iperf3* | Move-Item -Destination $testdirectory\parsed\
Remove-Item -Recurse -Force $testdirectory\root\

write-host "Average bandwith speeds were parsed succesfully and can be found in $testDirectory"
return $true