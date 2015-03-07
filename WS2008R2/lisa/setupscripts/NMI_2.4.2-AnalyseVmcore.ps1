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
    

.Description
    

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>
############################################################################
# NMI_2.4.2-TriggerKernelPanic.ps1
#
# This script automates TC 2.4.2. It sends the NMI trigger to the linux VM
# which leads to the kernel panic on the VM, then verifies if the vmcore files
# are created post kernel panic and if the vmcore files are readable using crash utility.
# 
# This scripts works in 3 parts - configuring kdump on VM, Generating kernel
# panic and then analysing the core dump file. This script reboots the VM
# twice, this script has a longer execution time. Also, while configuring the
# kdump, it downloads/install various packages, which may take a longer time.
#
# NOTE: This script has been tested only for SLES distribution.
############################################################################

param([string] $vmName, [string] $hvServer, [string] $testparams)

############################################################################
#
# TestPort()
#
# Description:This function will wait till the VM on the given hyperv 
# server starts gracefully and verified if the port 22 is open on the VM.
#
############################################################################
function TestPort ([String] $serverName, [Int] $port=22, [Int] $to=3)
{
    $retVal = $False
    $timeout = $to * 1000

    #
    # Try an async connect to the specified machine/port
    #
    $tcpclient = new-Object system.Net.Sockets.TcpClient
    $iar = $tcpclient.BeginConnect($serverName,$port,$null,$null)

    #
    # Wait for the connect to complete. Also set a timeout
    # so we don't wait all day
    #
    $connected = $iar.AsyncWaitHandle.WaitOne($timeout,$false)

    #
    # Check to see if the connection is done
    #
    if($connected)
    {
    
    #
    # Close our connection
    #
        try
        {
            $sts = $tcpclient.EndConnect($iar) | out-Null
            $retVal = $true
        }
        catch
        {
            # Nothing we need to do...
        }

    }
    $tcpclient.Close()

    return $retVal
}
#######################################################################
#
# Main script body
#
#######################################################################
$retVal = $false

#
# Check input arguments
#
if (-not $vmName)
{
    "Error: VM name is null. "
    return $retVal
}

if (-not $hvServer)
{
    "Error: hvServer is null"
    return $retVal
}

if (-not $testparams)
{
    "Error: testparams are null"
    return $retVal
}

$params = $testparams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    if ($fields.Length -ne 2)
    {
        continue  # Just ignore a malformed testparam
    } 
    
    switch ($fields[0].Trim())
    {
    "SshKey"  { $sshKey  = $fields[1].Trim() }
    "ipv4"    { $ipv4    = $fields[1].Trim() }
    "email"    { $email    = $fields[1].Trim() }
	"rootdir" { $rootDir = $fields[1].Trim() }
    default   {}  # unknown param - just ignore it
    }
}

#
# Updating the summary log with Testcase ID details
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers NMI TC-2.4.2" | Out-File $summaryLog

#
# Process the rootDir variable.  This is required for LiSA.
#
if ($rootDir)
{
    if (-not (Test-Path $rootDir))
    {
        "Error: rootDir contains an invalid path"
        return $False
    }

    cd $rootDir
    "Info : current directory is ${PWD}"
} 

#
# Saving the email address to a file for suse registration
#
echo email=$email | out-file -encoding ASCII -filePath ${vmName}_testdata.sh

#
# Verifying if the created testdata file exists
#
if (Test-Path ${vmName}_testdata.sh)
{
    "Info : testdata file Found"

    #
    # Copying files to VM with appropriate format and permissions
    #
    .\bin\pscp.exe -i ssh\${sshkey} "${vmName}_testdata.sh" root@${ipv4}:/root/testdata.sh 
    if(!$?)
    {
        "Error: Failed to copy ${vmName}_testdata.sh file."
        return $retVal
    }
    .\bin\plink -i ssh\${sshkey} root@${ipv4} "dos2unix /root/testdata.sh"
    del ${vmName}_testdata.sh

    #$retval = $True
} 
else
{
    "Error: testdata file Not Found!"
    return $retval
}

#
# Copying required kdump configuration scripts to VM
#
.\bin\pscp.exe -i ssh\${sshkey} ".\remote-scripts\ica\NMI_ConfigKdump.sh" root@${ipv4}: 
if(!$?)
{
    "Error: Failed to copy NMI_ConfigKdump.sh file"
    return $retVal
}
.\bin\plink -i ssh\${sshkey} root@${ipv4} "chmod +x /root/NMI_ConfigKdump.sh"
.\bin\plink -i ssh\${sshkey} root@${ipv4} "dos2unix /root/NMI_ConfigKdump.sh"
.\bin\plink -i ssh\${sshkey} root@${ipv4} "sh /root/NMI_ConfigKdump.sh"

#
# Waiting for VM to come up after the crash
#
start-sleep 5
$testCaseTimeout = 600
while ($testCaseTimeout -gt 0)
{
    if ( (TestPort $ipv4) )
    {
        break
    }

    Start-Sleep -seconds 2
    $testCaseTimeout -= 2

    if ($testCaseTimeout -eq 0)
    {
        "Error: Test case timed out for VM to go to Running"
        return $False
    }
}

"Info: Generating System Crash, Please wait, it may take longer than 5 mins to complete the process.."

#
# Sending NMI interrupt to the linux VM
#
Debug-VM -Name $vmName -InjectNonMaskableInterrupt -ComputerName $hvServer
if(!$?)
    {
        "Error: Failed to send NMI to VM."
        return $retVal
    }
sleep 10

#
# Waiting for VM to come up after the crash
#
start-sleep 5
$testCaseTimeout = 600
while ($testCaseTimeout -gt 0)
{
    if ( (TestPort $ipv4) )
    {
        break
    }

    Start-Sleep -seconds 2
    $testCaseTimeout -= 2

    if ($testCaseTimeout -eq 0)
    {
        "Error: Test case timed out for VM to go to Running"
        return $False
    }
}

Start-Sleep 10

#
# Verifying if the kernel panic process creates readable vmcore file
#
.\bin\pscp.exe -i ssh\${sshkey} ".\remote-scripts\ica\NMI_Verify_Vmcore.sh" root@${ipv4}: 
if(!$?)
{
    "Error: Failed to copy NMI_Verify_Vmcore.sh file"
    return $retVal
}
else
{
    .\bin\pscp.exe -i ssh\${sshkey} ".\remote-scripts\bin\crashcommand" root@${ipv4}:
    if(!$?)
    {
        "Error: Failed to copy crashcommand file"
        return $retVal
    }
    .\bin\plink -i ssh\${sshkey} root@${ipv4} "chmod +x /root/crashcommand"
    .\bin\plink -i ssh\${sshkey} root@${ipv4} "dos2unix /root/crashcommand"

    .\bin\plink -i ssh\${sshkey} root@${ipv4} "chmod +x /root/NMI_Verify_Vmcore.sh"
    .\bin\plink -i ssh\${sshkey} root@${ipv4} "dos2unix /root/NMI_Verify_Vmcore.sh"
    .\bin\plink -i ssh\${sshkey} root@${ipv4} "sh /root/NMI_Verify_Vmcore.sh"
    if($?)
    {
        $retVal = $true
    }
}

return $retval