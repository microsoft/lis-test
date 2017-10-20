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
    Collects coverage data from vm and uploads it in TestLogDir.

.Description
    Runs the remote script that is collecting the coverage data ,
    then uploads the archive and renames is after the test name.

.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script uses any setup scripts.

.Example
    
    <postTest>SetupScripts\GcovDataCollect.ps1</postTest>

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
    "SourcePath"   { $sourcePath   = $fields[1].Trim() }
    "rootdir"      { $rootDir   = $fields[1].Trim() }
    "ipv4"         { $ipv4      = $fields[1].Trim() }
    "SshKey"       { $sshKey    = $fields[1].Trim() }
    "TestLogDir" { $TestLogDir = $fields[1].Trim() }
    "TestName"   { $TestName = $fields[1].Trim() }
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

$scriptParam = "$sourcePath"

RunRemoteScript("collect_gcov_data.sh")

$remoteFile = "gcov_data.zip"
$localFile = "${TestLogDir}\${vmName}_${TestName}_gcov_data.zip"
.\bin\pscp -i ssh\${sshKey} root@${ipv4}:${remoteFile} .
$sts = $?
if ($sts)
{
    "Info: Collect gcov_data.zip from ${remoteFile} to ${localFile}"
    if (test-path $remoteFile)
    {
        $contents = Get-Content -Path $remoteFile
        if ($null -ne $contents)
        {
                if ($null -ne ${TestLogDir})
                {
                    move "${remoteFile}" "${localFile}"
}}}}

if (test-path "${TestLogDir}\collect_gcov_data.sh.log")
{
    rm -Force "${TestLogDir}\collect_gcov_data.sh.log"
}

return $True