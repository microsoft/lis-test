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
    Run the ttcp to collect throughput metrics.

.Description
    Run the ttcp utility to collect throughput metrics.
    The TARGET_IP is the address of the Linux system to
    run "ttcp -r" on.  This script assumes the TARGET_IP
    system is running since it could be a VM or bare metal.

    A sample XML definition for this test script would look similar
    to the following:

        <test>
            <testName>ttcp</testName>
            <testScript>setupscripts\Perf_ttcp.ps1</testScript>
            <!-- <files>tools\ttcp.c</files>  -->
            <timeout>600</timeout>
            <onError>Continue</onError>
            <noReboot>True</noReboot>
            <testparams>
                <param>TC_COVERED=PERF-TTCP-01</param>
                <param>BUFFER_COUNT=65536</param>
                <param>TTCP_FILE=ttcp.c</param>
                <param>TTCP_SOURCE_DIR=Tools</param>
                <param>TARGET_IP="10.200.51.224"</param>

                <param>rootDir=D:\lisa\trunk\lisablue</param>
            </testparams>
            <uploadFiles>
                <file>ttcp.log</file>
            </uploadFiles>
        </test>

.Parameter vmName
    Name of the VM to read intrinsic data from.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    .\Perf_ttcp.ps1 -vmName "myVm" -hvServer "localhost -TestParams "rootDir=c:\lisa\trunk\lisa;TC_COVERED=KVP-01;TARGET_IP=192.168.1.106;TTCP_FILE=ttcp.c;TTCP_SOURCE_DIR=D:\Tools\"

.Link
    None.
#>



param( [String] $vmName, [String] $hvServer, [String] $testParams )


#######################################################################
#
# Main script body
#
#######################################################################

#
# Make sure the required arguments were passed
#
if (-not $vmName)
{
    "Error: no VMName was specified"
    return $False
}

if (-not $hvServer)
{
    "Error: No hvServer was specified"
    return $False
}

if (-not $testParams)
{
    "Error: No test parameters specified"
    return $False
}

#
# Debug - display the test parameters so they are captured in the log file
#
"TestParams : '${testParams}'"

#
# Parse the test parameters
#
$ipv4      = $null
$rootDir   = $null
$targetIP  = $null
$sshKey    = $null
$bufLength = 8192
$bufCount  = 65536
$tcCovered = "Undefined"
$ttcpFile  = $null
$ttcpSourceDir = $null          # Where to find the $ttcpFile on the host
$testLogDir    = $null

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {      
    "TARGET_IP"       { $targetIP      = $fields[1].Trim() }
    "BUFFER_LENGTH"   { $bufLength     = $fields[1].Trim() }
    "BUFFER_COUNT"    { $bufCount      = $fields[1].Trim() }
    "rootDir"         { $rootDir       = $fields[1].Trim() }
    "TC_COVERED"      { $tcCovered     = $fields[1].Trim() }
    "SSHKEY"          { $sshKey        = $fields[1].Trim() }
    "IPv4"            { $ipv4          = $fields[1].Trim() }
    "TTCP_FILE"       { $ttcpFile      = $fields[1].Trim() }
    "TTCP_SOURCE_DIR" { $ttcpSourceDir = $fields[1].Trim() }
    "TestLogDir"      { $testLogDir    = $fields[1].Trim() }
    default           {}
    }
}

#
# Make sure required test parameters were provided
#
if (-not $ipv4)
{
    "Error: The IPv4 test parameter was not provided"
    return $False
}

if (-not $targetIP)
{
    "Error: The TARGET_IP test parameter was not provided"
    return $False
}

if (-not $sshKey)
{
    "Error: The SSHKEY test parameter was not provided"
    return $False
}

if (-not $ttcpFile)
{
    "Error: The TTCP_FILE test parameter was not provided"
    return $False
}

if (-not $ttcpSourceDir)
{
    "Error: The TTCP_SOURCE_DIR test parameter was not provided"
    return $False
}

if (-not $testLogDir)
{
    "Error: The TestLogDir test parameter was not provided"
    return $False
}

if (-not $rootDir)
{
    "Error: no rootdir was specified"
    return $False
}

if (-not (Test-Path $rootDir))
{
    "Error: rootDir '${rootDir}' does not exist"
    return $False
}

cd $rootDir

. .\setupscripts\TCUtils.ps1

$summaryLog  = "${vmName}_summary.log"
Del $summaryLog -ErrorAction SilentlyContinue
echo "Covers : ${tcCovered}" >> $summaryLog

#
# Push ttcp to the target IP machine
#
$localFile = $ttcpSourceDir
if ( -not ($localFile.EndsWith("\")) -and -not ($localFile.EndsWith("/")) )
{
    $localFile += "\"
}
$localFile += $ttcpFile

if (-not (SendFileToVM $ipv4 $sshKey "${localFile}" "${ttcpFile}" $True))
{
    "Error: Unable to copy ttcp.c to test VM"
    return $False
}

if (-not (SendFileToVM $targetIP $sshKey "${localFile}" "${ttcpFile}" $True))
{
    "Error: Unable to copy ttcp.c to TARGET VM"
    return $False
}

#
# Build ttcp on both the client and target IP machines
#
if (-not (SendCommandToVM $ipv4 $sshKey "gcc ./${ttcpFile} -o ./ttcp"))
{
    "Error: Unable to build ttcp.c on test VM"
    return $False
}

if (-not (SendCommandToVM $targetIP $sshKey "gcc ./${ttcpFile} -o ./ttcp"))
{
    "Error: Unable to build ttcp.c on test VM"
    return $False
}

#
# Start a job that will run "ttcp -r" on the target IP machine
#
"Starting the ttcp on the target machine in Receive mode ..."
# Print the command and return it to caller for debugging purpose
"./ttcp -r 2&> /dev/null"
$scriptBlock = {param([String] $rootDir, [String] $sshKey, [String] $targetIP) cd ${rootDir}; bin\plink.exe -i ssh\${sshKey} root@${targetIP} "./ttcp -r 2&> /dev/null"}

$job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $rootDir, $sshKey, $targetIP
if (-not $job)
{
    "Error: Unable to start ttcp -r job"
    return $False
}

#
# Allow some time for the job to start and the 'ttcp -r' to start on the VM
#
Start-Sleep -s 5

#
# Run ttcp on the client
#
"Starting the ttcp testing in Transmit mode ..."
# Print the command and return it to caller for debugging purpose
"./ttcp -s -t -l $bufLength -n $bufCount $targetIP > ./ttcp.log"
$sts = SendCommandToVM $ipv4 $sshKey "./ttcp -s -t -l $bufLength -n $bufCount $targetIP > ./ttcp.log"

#
# Collect the log file from the client
#
if (-not ($testLogDir.EndsWith("\")) )
{
    $testLogDir += "\"
}
$remoteFile = "./ttcp.log"
$localFile = "${testLogDir}${vmName}_ttcp.log"

if (-not (GetFileFromVM $ipv4 $sshKey "./ttcp.log" "${localFile}"))
{
    "Error: Unable to collect ttcp.log file from VM"
    return $False
}

#
# Receive the PowerShell job that ran on the Target IP machine
#
$jobStatus = Get-Job -id $job.ID
if ($jobStatus -eq $null)
{
    "Error: bad job id"
    return $False
}

"Info : Job state = $($jobStatus.state)"

if ($jobStatus.State -ne "Completed")
{
    "Error: ttcp -r job did not complete"
    return $False
}

$jobResults = @(Receive-Job -id $job.ID) | out-null


return $True
