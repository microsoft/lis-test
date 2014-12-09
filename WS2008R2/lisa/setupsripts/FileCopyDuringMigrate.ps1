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
    This test case will check that file copy operation completes successfuly during the Live migration of the VM.


.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

#####################################################################
#
# SendCommandToVM()
#
#####################################################################
function SendCommandToVM([String] $sshKey, [String] $ipv4, [string] $command)
{
    $retVal = $null

    $sshKeyPath = Resolve-Path $sshKey
    
    $dt = .\bin\plink -i ${sshKeyPath} root@${ipv4} $command 2>&1

    if ($?)
    {
        $retVal = $dt
    }
    else
    {
        Write-Output "Error: $vmName unable to send command to VM. Command = '$command'"
    }

    return $retVal
}


#####################################################################
#
# Main script body
#
#####################################################################

#
# Check input arguments
#
if (-not $vmName -or $vmName.Length -eq 0)
{
    "Error: vmName is null"
    return $False
}

if (-not $hvServer -or $hvServer.Length -eq 0)
{
    "Error: hvServer is null"
    return $False
}

if (-not $testParams -or $testParams.Length -lt 3)
{
    "Error: testParams is null or invalid"
    return $False
}

$ipv4 = $null
$rootdir = $null
$tc = $null


#
# Parse the testParams string
#
$params = $testParams.Split(';')
foreach ($p in $params)
{
    if ($p.Trim().Length -eq 0)
    {
        continue
    }

    $fields = $p.Trim().Split('=')
    
    if ($fields.Length -ne 2)
    {
	    #"Warn : test parameter '$p' is being ignored because it appears to be malformed"
        continue
    }
    
    if ($fields[0].Trim() -eq "IPV4")
    {
        $ipv4 = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "RootDir")
    {
        $rootdir = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "TC_COVERED")
    {
        $tc = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "sshKey")
    {
        $sshKey = $fields[1].Trim()
    }
   
}

if (-not $rootdir)
{
    "Error: root dir is null or invalid"
    return $False
}



$sts = get-module | select-string -pattern FailoverClusters -quiet
if (! $sts)
{
    Import-module FailoverClusters
}

#
# change the working directory to root dir
#

cd $rootdir


#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers ${tc}" | Out-File -Append $summaryLog




# Start the copy job in the background
$job = SendCommandToVM ".\ssh\${sshKey}" $ipv4 "bash /root/FileCopyMigration.sh >summary.log &"

if( $job -match "Error")
{
    Write-Output "Failed to start the copy job - $job" | Out-File -Append $summaryLog
    return $False
}        

# wait till the file copy starts 

Start-Sleep -s 10

#
# During file copy migrate the VM.
# 

$migStatus = setupScripts\MigrateVM.ps1 $vmName $hvServer $testParams

if ( $migStatus -ne $True)
{
    Write-Output "Error: Live migration failed" | Out-File -Append $summaryLog
    return $False
}


# Check whether copy job completed successfully & md5 checksum passsed

$result = "TestRunning"

while ($result -eq "TestRunning")
{

    $result = SendCommandToVM ".\ssh\${sshKey}" $ipv4 "cat state.txt"

    if( $result -eq "TestCompleted")
    {
         break
    }

    if( $result -eq "TestAborted" -or $result -eq "TestFailed" -or $result -match "Error")
    {
         Write-Output "Error: File copy job not completed properly" | Out-File -Append $summaryLog

         SendCommandToVM ".\ssh\${sshKey}" $ipv4 "cat summary.log" # On fail read the log before exit 

         return $False
    }
    Start-Sleep -Seconds 05
}

# Read the copy job output

SendCommandToVM ".\ssh\${sshKey}" $ipv4 "cat summary.log"


#
# If you are here, file copy during migration completed successfully.
#

Write-Output "File copy during migration completed successfully" | Out-File -Append $summaryLog

return $True
