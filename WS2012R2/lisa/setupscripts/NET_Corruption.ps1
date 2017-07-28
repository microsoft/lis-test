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
Run NET Corruption test

.Description
This test script will configure the VM and run the TCP_Corruption

The logic of the script is:
Process the test parameters.
Run NET_Corruption in the guest VM in order to install netcat
and set the desired corruption.
Start netcat listen process on the VM and the receive process on
windows host.
Check for call traces.
Compare file hashes.

A sample LISA test case definition would look similar to the following:
<test>
    <testName>TCP_Corruption</testName>
    <onError>Continue</onError>
    <setupScript>
        <file>setupscripts\RevertSnapshot.ps1</file>
    </setupScript>
    <testParams>
        <param>TC_COVERED=NET-24</param>
        <param>CORRUPTION=1%</param>
        <param>FILE_SIZE=256M</param>
    </testParams>
    <testScript>setupscripts\NET_Corruption.ps1</testScript>
    <files>remote-scripts/ica/NET_Corruption.sh,remote-scripts/ica/utils.sh</files>
    <timeout>800</timeout>
</test>
#>
param( [String] $vmName, [String] $hvServer, [String] $testParams )
Set-PSDebug -Strict

########################################################################
#
# Main script body
#
########################################################################

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

"Info : Parsing test parameters"
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
        "ipv4"          { $ipv4        = $val }
        "sshkey"        { $sshKey      = $val }
        "rootdir"       { $rootDir     = $val }
        "TC_COVERED"    { $tcCovered   = $val }
        "TestLogDir"    { $testLogDir  = $val }
        default         { continue }
    }
}

#
# Change the working directory to where we should be
#
if (-not $rootDir)
{
    "Error: The roodDir parameter was not provided by LISA"
    return $False
}

if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

"Info : Changing directory to '${rootDir}'"
cd $rootDir

if (Test-Path ".\setupScripts\TCUtils.ps1")
{
    . .\setupScripts\TCUtils.ps1
}
else
{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $False
}
#
# Make sure the required testParams were found
#
"Info : Verify required test parameters were provided"
if (-not $sshKey)
{
    "Error: testParams is missing the sshKey parameter"
    return $False
}

if (-not (Test-Path ssh\${sshKey}))
{
    "Error: The SSH key 'ssh\${sshKey}' does not exist"
    return $False
}

if (-not $ipv4)
{
    "Error: The ipv4 parameter was not provided by LISA"
    return $False
}

$port = 1234
$sourceFilePath = "/tmp/testfile"
$destionationFilePath = ".\testfile"
$netcatScriptPath = "listen.sh"
$netcatBinPath = ".\bin\nc.exe"
$summaryLog = "${vmName}_summary.log"

del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers: ${tcCovered}" | Tee-Object -Append -file $summaryLog

if (-not (Test-Path $netcatBinPath)) {
    $msg = "Unable to find netcat binary"
    "${msg}"
    Write-Output $msg | Tee-Object -Append -file $summaryLog
    return $False
}

"Info: Configuring VM"
$cmd = "./NET_Corruption.sh ${sourceFilePath} ${port} ${netcatScriptPath} 2>/dev/null"
$sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix NET_Corruption.sh 2>/dev/null"
$sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod 755 NET_Corruption.sh 2>/dev/null"
$sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} $cmd

if (-not $?)
{
    $msg = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "tail -n 1 summary.log"
    $vm_log = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "tail -n+2 summary.log" | %{$_.Split("`n")}
    $vm_log = $vm_log -join "`n"
    "${vm_log}"
    Write-Output $msg | Tee-Object -Append -file $summaryLog
    return $False
}

"Info: Checking system logs path"
bin\plink.exe -i ssh\${sshKey} root@${ipv4} "[[ -f /var/log/syslog ]]"
if (-not $?)
{
    $logPath = '/var/log/messages'
}
else
{
    $logPath = '/var/log/syslog'
}

"Info: Starting netcat server on VM Job"
$cmd = "`"" + "setsid ./${netcatScriptPath} >/dev/null 2>&1 < /dev/null &" + "`""
"Info: Running command ${cmd}"
bin\plink.exe -i ssh\${sshKey} root@${ipv4}  $cmd

$jobName = "ReceiveJob"
$ipAddr = (Get-VMNetworkAdapter -VMName ${vmName} -ComputerName $hvServer)[1].IPAddresses[0]
$cmd = "cmd.exe /C " + "'" + "${netcatBinPath} -v -w 2 ${ipAddr} ${port} > ${destionationFilePath}" + "'"
"Info: Running command ${cmd}"
$cmd | Out-File ./nccmd.ps1
$sts = ./nccmd.ps1
Start-Job -Name ${jobName} -ScriptBlock {./nccmd.ps1}


"Info: Checking for call traces in ${logPath}"
$grepCmd = "grep -i 'Call Trace' ${logPath}"
while ((Get-Job -Name ${jobName}).State -eq "Running")
{
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} $grepCmd
    if ($?)
    {
        $msg = "Error: Call traces found in ${logPath}"
        Write-Output $msg | Tee-Object -Append -file $summaryLog
        return $False
    }
}

Get-Job -Name ${jobName} | Remove-Job

"Info: Comparing hashes"
$localHash = (Get-FileHash -Algorithm MD5 $destionationFilePath).Hash
$hashCmd = "md5sum ${sourceFilePath}"
$remoteHash = (bin\plink.exe -i ssh\${sshKey} root@${ipv4} $hashCmd).Split(" ")[0]

if (-not $?)
{
    $msg = "Error: Unable to get file hash from VM"
    Write-Output $msg | Tee-Object -Append -file $summaryLog
    return $False
}

"Info : File hashes: ${remoteHash} - ${localHash}"
if ($remoteHash.ToUpper() -ne $localHash) {
    $msg = "Error: File hashes do not match."
    Write-Output $msg | Tee-Object -Append -file $summaryLog
    return $False
}

#
# If we made it here, everything worked
#
"Info : Test completed successfully"
Write-Output "Test completed successfully" | Tee-Object -Append -file $summaryLog
return $True
