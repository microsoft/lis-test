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
    This script tests vDSO.
    The "vDSO" (virtual dynamic shared object) is a small shared library
       that the kernel automatically maps into the address space of all
       user-space applications.
    Luckily, current new kernel support vDSO.

.Description

    This test covers current clocksource support vDSO.

    A typical XML definition for this test case would look similar
    to the following:
    <test>
        <testName>Core_Time_VDSO</testName>
        <testScript>SetupScripts\Core_Time_VDSO.ps1</testScript>
        <files>tools/time/gettime.c</files>
        <testParams>
            <param>TC_COVERED=CORE-38</param>
        </testParams>
        <timeout>600</timeout>
        <RevertDefaultSnapshot>True</RevertDefaultSnapshot>
        <onError>Continue</onError>
        <noReboot>false</noReboot>
    </test>

.Parameter vmName
    Name of the VM to test.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case.
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

# compile gettime.c, get time of running the compiled script
function gettime()
{
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "gcc gettime.c -o gettime"
    if ($? -ne "True") {
        Write-Output "Error: Unable to compile gettime.c" | Tee-Object -Append -file $summaryLog
        return $Aborted
    }

    # get time of running gettime
    $result = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "time -p  (./gettime) 2>&1 1>/dev/null"
    $result = $result.Trim()
    write-output "$result" | Tee-Object -Append -file $summaryLog
    #real 3.14 user 3.14 sys 0.00
    $real = $result.split("")[1]  # get real time: 3.14
    $sys = $result.split("")[5]   # get sys time: 0.00

    write-output "real time: $real, sys time: $sys" | Tee-Object -Append -file $summaryLog
    # support VDSO, sys time should be shorter than 1.0 second
    if (([float]$real -gt 10.0) -or ([float]$sys -gt 1.0))
    {
        Write-Output "Error: Check real time is $real(>10.0s), sys time is $sys(>1.0s)" | Tee-Object -Append -file $summaryLog
        return $Failed
    }
    else
    {
        Write-Output "Check real time is $real(<10.0s), sys time is $sys(<1.0s)" | Tee-Object -Append -file $summaryLog
        return $True
    }
}

# Checking the input arguments
if (-not $vmName) {
    "Error: VM name is null!"
    return $Failed
}

if (-not $hvServer) {
    "Error: hvServer is null!"
    return $Failed
}

if (-not $testParams) {
    "Error: No testParams provided!"
    "This script requires the test case ID and VM details as the test parameters."
    return $Failed
}

#
# Checking the mandatory testParams. New parameters must be validated here.
#
$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")

    if ($fields[0].Trim() -eq "TC_COVERED") {
        $TC_COVERED = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "TEST_TYPE") {
        $TEST_TYPE = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "rootDir") {
        $rootDir = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "ipv4") {
        $ipv4 = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "sshkey") {
        $sshkey = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "TestLogDir") {
        $TestLogDir = $fields[1].Trim()
    }
}

#
# Change the working directory for the log files
# Delete any previous summary.log file, then create a new one
#
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist"
    return $Failed
}
cd $rootDir

# Source TCUtils.ps1 for test related functions
if (Test-Path ".\setupscripts\TCUtils.ps1")
{
    . .\setupScripts\TCUtils.ps1
}
else
{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $Failed
}
$retVal = $False
# Delete any previous summary.log file, then create a new one
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Check if VM kernel version supports vDSO
# Kernel version for RHEL 7.5
$supportkernel = "3.10.0-862"
$kernelSupport = GetVMFeatureSupportStatus $ipv4 $sshkey $supportkernel
if ($kernelSupport -ne "True") {
    Write-Output "Info: Current VM Linux kernel version does not support vDSO feature." | Tee-Object -Append -file $summaryLog
    return $Skipped
}

################################################
#   Main Test
################################################
gettime
