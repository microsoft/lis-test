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

$summaryLog = ("{0}_summary.log" -f @($vmName))
Remove-Item -Force $summaryLog -ErrorAction SilentlyContinue

Write-Output "TEST PARAMS: ${testParams}" `
        | Tee-Object -Append -file $summaryLog

if (-not $vmName) {
    "Error: VM name is null!"
    return $retVal
}

if (-not $hvServer) {
    "Error: hvServer is null!"
    return $retVal
}

if (-not $testParams) {
    "Error: No testParams provided!"
    "This script requires the test case ID and VM details as the test parameters."
    return $retVal
}

$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")

    switch ($fields[0].Trim()) {
        "rootDir" { $rootDir = $fields[1].Trim() }
        "sshKey" { $sshKey  = $fields[1].Trim() }
        "ipv4" { $ipv4 = $fields[1].Trim() }
        "LOGS" { $logs = $fields[1].Trim() }
        "TestLogDir" { $logDir = $fields[1].Trim() }
        default  {}
    }
}

if ($null -eq $sshKey) {
    "Error: Test parameter sshKey was not specified"
    return $False
} else {
    $sshKey = Resolve-Path "ssh\${sshKey}"
}
if ($null -eq $ipv4) {
    "Error: Test parameter ipv4 was not specified"
    return $False
}
if (-not $rootDir) {
    "Warn : rootdir was not specified"
} else {
    Set-Location $rootDir
}
if (($logDir) -and (Test-Path $logDir)) {
    $logDir = Resolve-Path $logDir
} else {
    "Error: TestLogDir was not specified of cannot be found"
    return $false
}
if ($logs) {
    $logs = $logs.Split(",")
} else {
    "Warn: no logs spefified for download"
    return $true
}

foreach ($file in $logs) {
    .\bin\plink -i ${sshKey} root@${ipv4} "[[ -d ${file} ]]"
    if ($?) {
        Write-Output "Found directory ${file}" | Out-File -Append $summaryLog
        $fileName = $file.Trim("/").Split("/")[-1]
        .\bin\plink -i ${sshKey} root@${ipv4} "tar -cvf ${fileName}.tar -C `$(dirname ${file}) ${fileName}"
        if ($?) {
            Write-Output "Tar exited successfully. Downloading" | Out-File -Append $summaryLog
            .\bin\pscp -i ${sshKey}  root@${ipv4}:/root/${fileName}.tar "${logDir}\${fileName}.tar"
        }
        continue
    }
    .\bin\plink -i ${sshKey} root@${ipv4} "[[ -f ${file} ]]"
    if ($?) {
        Write-Output "Found file ${file}. Downloading" | Out-File -Append $summaryLog
        $fileName = $file.Trim("/").Split("/")[-1]
        .\bin\pscp -i ${sshKey}  root@${ipv4}:${file} "${logDir}\${fileName}"
        continue
    }
    Write-Output "Warn: Cannot find file ${file}" | Out-File -Append $summaryLog
}

return $true
