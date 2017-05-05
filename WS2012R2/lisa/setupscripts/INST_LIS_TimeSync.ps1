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
    Verify the time on the VM.

.Description
    Verify the time on the VM synched with the Hyper-V host.
    This is not a long term time sync test.
        <test>
            <testName>Time_Sync_With_Host</testName>
            <testScript>setupScripts\INST_LIS_TimeSync.ps1</testScript>
            <timeout>600</timeout>
            <onError>Continue</onError>
            <noReboot>True</noReboot>
            <testParams>
                <param>testDelay=60</param>
                <param>MaxTimeDiff=0.9</param>
                <param>TC_COVERED=CORE-02</param>
                <param>rootDir=D:\Lisa\trunk\lisablue</param>
            </testParams>
        </test>

    Test parameters
        TestDelay
            Default is 0.  This parameter is optional.
            Specifies a time in seconds, to sleep before
            asking the test VM for its time.

        MaxTimeDiff
            Default is 5 second.  This parameter is optional.
            Specifies the maximum time difference to allow.
            Since the time is collected from the VM via SSH
            network delays will increase the actual difference.

        TC_COVERED
            Required.
            Identifies the test case this test covers.

        RootDir
            Required.
            PowerShell test scripts are run as a PowerShell job.
            When a PowerShell job runs, the current directory
            will not be correct.  This specifies the directory
            that should be the current directory for the test.

.Parameter vmName
    Name of the VM to test.

.Parameter  hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter  testParams
    A string with test parameters.

.Example
    .\INST_LIS_TimeSync.ps1 -vmName "myVM" -hvServer "myServer" -testParams "sshKey=lisa_id_rsa.ppk;rootDir=D:\lisa\trunk\lisablue"
#>



param ([String] $vmName, [String] $hvServer, [String] $testParams)

$retVal = $False

#
# Make sure all command line arguments were provided
#
if (-not $vmName)
{
    "Error: vmName argument is null"
    return $False
}

if (-not $hvServer)
{
    "Error: hvServer argument is null"
    return $False
}

if (-not $testParams)
{
    "Error: testParams argument is null"
    return $False
}

"timesync.ps1"
"  vmName    = ${vmName}"
"  hvServer  = ${hvServer}"
"  testParams= ${testParams}"

#
# Parse the testParams string
#
"Parsing test parameters"
$sshKey = $null
$ipv4 = $null
$maxTimeDiff = "5"
$rootDir = $null
$tcCovered = "unknown"
$testDelay = "0"

$params = $testParams.Split(";")
foreach($p in $params)
{
    $tokens = $p.Trim().Split("=")
    if ($tokens.Length -ne 2)
    {
        continue   # Just ignore the parameter
    }
    
    $val = $tokens[1].Trim()
    
    switch($tokens[0].Trim().ToLower())
    {
    "ipv4"        { $ipv4        = $val }
    "sshkey"      { $sshKey      = $val }
    "rootdir"     { $rootDir     = $val }
    "MaxTimeDiff" { $maxTimeDiff = $val }
    "TC_COVERED"  { $tcCovered   = $val }
    "TestDelay"   { $testDelay   = $val }
    default       { continue }
    }
}

#
# Make sure the required testParams were found
#
"Verify required test parameters were provided"
if (-not $sshKey)
{
    "Error: testParams is missing the sshKey parameter"
    return $False
}

#
# Change the working directory to where we should be
#
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

"Changing directory to ${rootDir}"
cd $rootDir

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
"Covers ${tcCovered}" >> $summaryLog

#
# Source the utility functions so we have access to them
#
. .\setupscripts\TCUtils.ps1

#
# Source the timesync utility functions
#
. .\setupscripts\TimeSync_Utils.ps1

#
# Determine the IPv4 address of the test VM
#
"Determine IPv4 address for VM '${vmName}'"
if (-not $ipv4)
{
    $ipv4 = GetIPv4 $vmName $hvServer
    if (-not $ipv4)
    {
        "Error: Unable to determin the IPv4 address for VM ${vmName}"
        return $False
    }
}

"Test data"
"  ipv4        = ${ipv4}"
"  sshKey      = ${sshKey}"
"  maxTimeDiff = ${maxTimeDiff}"
"  testDelay   = ${testDelay}"
"  rootDir     = ${rootDir}"


#
# If the test delay was specified, sleep for a bit
#
if ($testDelay -ne "0")
{
    "Sleeping for ${testDelay} seconds"
    Start-Sleep -S $testDelay
}

#
# Get a time string from the VM, then convert the Unix time string into a .NET DateTime object
#
"Get time from Unix VM"
$unixTimeStr = GetUnixVMTime -sshKey "ssh\${sshKey}" -ipv4 $ipv4
if (-not $unixTimeStr)
{
    "Error: Unable to get date/time string from VM"
    return $False
}

$diffInSeconds = GetTimeSync -sshKey $sshKey -ipv4 $ipv4

if ($diffInSeconds -and $diffInSeconds -lt 5)
{
    Write-Output "Info: Time is properly synced" | Out-File $summaryLog
    return $True
}
else
{
    Write-Output "Error: Time is out of sync!" | Out-File $summaryLog
    return $False
}
