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
    Performs basic Live/Quick Migration operations
.Description
    This is a Powershell test case script that implements Live/Quick Migration
    of a VM.
    Keeps pinging the VM while migration is in progress, ensures that migration
    of VM is successful and the that the ping should not loose

    A typical test case definition for this test script would look similar to
    the following:

.Parameter vmName
    Name of the VM to migrate.
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
.Parameter testParams
    Test data for this test case
.Example
    .\NET-LIVEMIG.ps1 -vmName VM_Name -hvServer HYPERV_SERVER -TestParams "ipv4=255.255.255.255;MigrationType=Live;sshKey=YOUR_KEY.ppk"
#>

param( [String] $vmName,
       [String] $hvServer,
       [String] $testParams
)

$migrationType  = $null
$ipv4           = $null
$sshKey         = $null
$rootDir        = $null
$copyFile       = $False
$stopClusterNode= $False
$TC_COVERED     = $null
$pingCount      = 0
$goodPings      = 0
$badPings       = 0
$firstPing      = $False
$lastPing       = $False

########################################################################
#
# Create-TempFile()
#
########################################################################
function Create-TempFile
{
    param(
		[Parameter(mandatory=$True)]
		[String]$FilePath,
		[Parameter(mandatory=$True)]
		[double]$Size
		)

    $file = [System.IO.File]::Create($FilePath)
    $file.SetLength($Size)
    $file.Close()

    return $true
}

########################################################################
#
# Copy-TempFile -Path $rootDir\temp.txt -sshKey $sshKey -Ip $ipv4
#
########################################################################
function Copy-TempFile
{
    param(
		[Parameter(mandatory=$True)]
		[String]$FilePath,
		[Parameter(mandatory=$True)]
		[String]$sshKey,
		[Parameter(mandatory=$True)]
		[String]$Ip,
		[Parameter(mandatory=$True)]
		[String]$ScpDir
		)

    & "$ScpDir\pscp.exe" -i $sshKey $FilePath root@${Ip}:
    if(-not $?)
    {
        "Error: Error copying ${Path} to VM Ip - ${Ip}"
        return $False
    }

    return $true
}

########################################################################
#
# Main entry point for script
#
########################################################################

if (-not $vmName -or $vmName.Length -eq 0)
{
    "Error: No vmName was specified"
    Return $False   
}

if (-not $hvServer)
{
    "Error: No hvServer was specified"
    Return $False
}

if (-not $testParams)
{
    "Error: No test parameters specified"
    Return $False
}

$params = $testParams.TrimEnd(";").Split(";")
foreach ($param in $params)
{
    $fields = $param.Split("=")

    switch ($fields[0].Trim())
    {
        "MigrationType" { $migrationType    = $fields[1].Trim() }
        "ipv4"          { $ipv4             = $fields[1].Trim() }
        "sshKey"        { $sshKey           = $fields[1].Trim() }
        "rootDir"       { $rootDir          = $fields[1].Trim() }
        "copyFile"      { $copyFile         = $fields[1].Trim() }
        "stopClusterNode"{ $stopClusterNode = $True }
        "TC_COVERED"    { $TC_COVERED       = $fields[1].Trim() }
        default         {} #unknown param - just ignore it
    }
}

$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Create a ping object
#
$ping = New-Object System.Net.NetworkInformation.Ping
if (-not $ping)
{
    "Error: Unable to create a ping object"
}

"Info: Trying to ping the VM before starting migration"
$pingCount += 1
$pingReply = $ping.Send($ipv4)
if ($pingReply.Status -ne "Success")
{
    "Error: Cannot ping VM prior to migration. Status = $($pingReply.Status)"
    return $False
}
$firstPing = $true
$goodPings += 1


#
# Start the VM migration, and make sure it is running
#
"Info: Starting migration job"
$job = Start-Job -FilePath $rootDir\setupScripts\Migrate-VM.ps1 -ArgumentList $vmName, $hvServer, $migrationType, $stopClusterNode

if (-not $job)
{
    "Error: Migration job not started"
    return $False
}

"Info: Checking if the migration job is actually running"
$jobInfo = Get-Job -Id $job.Id
if($jobInfo.State -ne "Running")
{
    "Error: Migration job did not start or terminated immediately"
    return $False
}

"Info: Pinging VM during the migration"
$migrateJobRunning = $true
while ($migrateJobRunning)
{
    $pingReply = $ping.Send($ipv4)
    if ($pingReply.Status -eq "Success")
    {
        $goodPings += 1
        $lastPing = $true
    }
    else
    {
        $badPings += 1
        $lastPing = $False
    }
    $pingCount += 1

    #
    # Copying file during migration
    #
    if($copyFile)
    {
        "Info: Creating a 256MB temp file"
        $sts = Create-TempFile -FilePath "$rootDir\temp.txt" -Size 256MB 
        if (-not $?)
        {
            "Error: Unable to create the temp file"
            return $False
        }

        "Info: Copying temp file to VM"
        $sts = Copy-TempFile -FilePath "$rootDir\temp.txt" -sshKey "$rootDir\ssh\$sshKey" -Ip $ipv4 -ScpDir "$rootDir\bin"
        if (-not $?)
        {
            "Error: Unable to copy file"
            return $False
        }

        $copyFile = $False
    }

    $jobInfo = Get-Job -Id $job.Id
    if($jobInfo.State -eq "Completed")
    {
        $migrateJobRunning = $False
        continue
    }
}

"Info: Pinging VM after migration"
$pingReply = $ping.Send($ipv4)
if ($pingReply.Status -eq "Success")
{
    $goodPings += 1
    $lastPing = $true
}
else
{
    $badPings += 1
    $lastPing = $False
}
$pingCount += 1

#
# Receiving the migration job's output
#
$jobInfo = Receive-Job -Id $job.Id
Remove-Job -Id $job.Id

#
# Display migrate job output
#
"Info: $vmName - Migrate job output"
foreach ($data in $jobInfo)
{
    "    $data"
}

"Total pings : $pingCount"
"Good pings  : $goodPings"

"Total pings : $pingCount"
"Bad pings  : $badPings"

#
# Adding ping stats to summary
#
Write-Output "Good pings = $goodPings" | Tee-Object -Append -file $summaryLog
Write-Output "Bad pings  = $badPings"  | Tee-Object -Append -file $summaryLog

#
# Checking if migration reports success and the last ping is successful
#
$retVal = ($jobInfo[$jobInfo.Length-1] -eq $True) -and ($lastPing)

return $retVal

