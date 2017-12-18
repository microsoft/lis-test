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
    Generates html reports based on previous GCOV data.

.Description
    Runs the remote script that is collecting the html reports.

.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script uses any setup scripts.

.Example
    
    <postTest>SetupScripts\CreateGcovReport.ps1</postTest>

#>

param([String] $vmName, [String] $hvServer, [String] $testParams)

if (-not $testParams)
{
    "Error: No test parameters specified"
    return $False
}

Write-Output "TestParams : '${testParams}'"

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {
    "rootdir"      { $rootDir   = $fields[1].Trim() }
    "ipv4"         { $ipv4      = $fields[1].Trim() }
    "SshKey"       { $sshKey    = $fields[1].Trim() }
    "testArea"   { $testArea = $fields[1].Trim() }
    "kernelSource"   { $kernelSource = $fields[1].Trim() }
    "reportsFolder"   { $reportsFolder = $fields[1].Trim() }
    default  {}
    }
}

if (-not $rootDir)
{
    "Warn : no rootdir was specified"
}
else
{
    cd $rootDir
}

if (Test-Path ".\setupScripts\TCUtils.ps1")
{
  . .\setupScripts\TCUtils.ps1
}
else
{
  "Error: Could not find setupScripts\TCUtils.ps1"
  return $false
}


$sts = Test-Path ".\${reportsFolder}\${testArea}\*"
if (-not $sts) {
    "Info: Unable to find ${testArea} folder"
    return $Skipped
}

if (Test-Path ".\${testArea}.zip") {
    Remove-Item ".\${testArea}.zip"
}
Compress-Archive -Path ".\${reportsFolder}\${testArea}\*" -DestinationPath .\$testArea
if (-not $?) {
    "Error: Unable to compress gcov files"
    return $false
}


.\bin\pscp -i ssh\${sshKey} ".\${testArea}.zip" root@${ipv4}:/root/
if (-not $?) {
    "Error: Unable to send zip to vm"
    exit 1
}
$reportCmd = @"
easy_install pip
pip install gcovr
unzip `$1 -d `$2
mkdir `$1
cd `$2
gcovr -g -k -r . --html --html-details -o /root/`$1/"`${1}.html"
cd ~
zip coverage_report `$1/* 
"@

$filename = "create_report.sh"

if (Test-Path ".\${filename}")
{
    Remove-Item ".\${filename}"
}

Add-Content $filename "$reportCmd"
$retVal = SendFileToVM $ipv4 $sshKey $filename "/root/${filename}"

if (-not $retVal[-1])
{
    return $false
}

$retVal = SendCommandToVM $ipv4 $sshKey "cd /root && chmod u+x ${filename} && dos2unix ${filename} && ./${filename} ${testArea} ${kernelSource}"
if (-not $retVal) {
    "Error: Unable to create report"
    return $false
} else {

} 

.\bin\pscp -i ssh\${sshKey}  root@${ipv4}:/root/coverage_report.zip ".\reports\${testArea}.zip"
$sts = $?
if (-not $sts)
{
    "Error: Unable to copy report"
    return $false
    
}

"INFO: Created report"
return $true