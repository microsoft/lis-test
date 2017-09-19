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
    Creates coverage htmls from gcov data uploaded from VM.

.Description
    The script will unzip coverage files from TestLogDir,
    then builds readable grouped readable htmls using gcovr
    and gcovr-group.

.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

.Example
    <test>
        <testName>GCOVR</testName>
        <testScript>setupscripts\GCOV_Data_Group.ps1</testScript>>
        <timeout>3600</timeout>
        <testparams>
            <param>GcovGroupFile=gcov_group</param>
            <param>Python2=C:\Python27</param>
        </testparams>
    </test

#>

param([String] $vmName, [String] $hvServer, [String] $testParams)

Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not $testParams)
{
    "Error: No test parameters specified"
    return $False
}

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {
    "GcovGroupFile" { $GcovGroupFile = $fields[1].Trim() }
    "TestLogDir" { $TestLogDir = $fields[1].Trim() }
    "rootDir"      { $rootDir   = $fields[1].Trim() }
    "Python2"      { $pythonPath   = $fields[1].Trim() }
    default  {}       
    }
}

if (-not $pythonPath )
{
    if (Test-Path "C:\Python27\")
    {
        $pythonPath = "C:\Python27"
    } else {
        "Error : Python 2.7 is not installed on your system"
        return $False
    }
}

if (-not $(Test-Path "$pythonPath\Scripts\gcovr")){
    "Error : Gcovr is not installed on your system"
    return $False
}

$TestLogDir = $rootDir + '\' + $TestLogDir

pushd "$TestLogDir"
$zipFiles = ls *.zip | Select-Object Name

$testPassed = $True

foreach ($zipFile in $zipFiles){
    $zipFile = $zipFile.Name
    [System.IO.Compression.ZipFile]::ExtractToDirectory("$TestLogDir\$zipfile", "$TestLogDir\temp_gcov")
	$pyPath="$rootDir\tools\gcov"
    pushd .\temp_gcov
    & "$pythonPath\python.exe" "$pythonPath\Scripts\gcovr" -g --html-details --html -o temp.html 
    & "$pythonPath\python.exe" "$pyPath\gcovr-group.py" -h temp.html -O "$rootDir\tools\gcov\$GcovGroupFile" -o .\out.html
    popd
    mv .\temp_gcov\out.html ".\$($zipFile.Split('.')[0]).html"
    rm -Recurse -Force .\temp_gcov
	
	if ( ! $(Test-Path ".\$($zipFile.Split('.')[0]).html")){
		$testPassed = $False
	}
}
popd
return $testPassed