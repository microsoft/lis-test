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
    Disable then enable the Time Sync service and verify Time Sync still works.

.Description
    Disable, then re-enable the LIS Time Sync service.  Then verify that
    a Time Sync request still works.  The XML test case definition for
    this test would look similar to:
    <test>
        <testName>VerifyItegratedTimeSyncService</testName>
        <testScript>setupscripts\INST_LIS_TimeSyncServiceDisableEnable.ps1</testScript>
        <timeout>600</timeout>
        <testParams>
            <param>TC_COVERED=CORE-29</param>
            <param>MaxTimeDiff=5</param>
        </testParams>
    </test>

.Parameter vmName
    Name of the VM to perform the test with.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.

.Example
    .\INST_LIS_Time SyncServiceDisableEnable.ps1 "myVM" "localhost" "rootDir=D:\lisa\trunk\lisablue;TC_COVERED=10"
#>



param([String] $vmName, [String] $hvServer, [String] $testParams)


#####################################################################
#
#   GetUnixVMTime()
#
#####################################################################
function GetUnixVMTime([String] $sshKey, [String] $ipv4)
{
    if (-not $sshKey)
    {
        return $null
    }

    if (-not $ipv4)
    {
        return $null
    }

    $unixTimeStr = $null
    $command =  "date '+%m/%d/%Y%t%T%p ' -u"

    $sshKeyPath = Resolve-Path $sshKey
    $unixTimeStr = .\bin\plink.exe -i ${sshKeyPath} root@${ipv4} $command

    if (-not $unixTimeStr -and $unixTimeStr.Length -lt 20)
    {
        return $null
    }

    return $unixTimeStr
}
#######################################################################
#
# Main script body
#
#######################################################################

$retVal = $False
#
# Check input arguments
#
if ($vmName -eq $null)
{
    "Error: VM name is null"
    return $False
}

if ($hvServer -eq $null)
{
    "Error: hvServer is null"
    return $False
}

if ($testParams -eq $null)
{
    "Error: testParams is null"
    return $False
}

#
# Parse the testParams string
#
$sshKey = $null
$rootDir = $null
$tcCovered = "Undefined"
$ipv4 = $null

"Parsing testParams"
$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {
    "ipv4"       { $ipv4      = $fields[1].Trim() }
    "sshKey"     { $sshKey      = $fields[1].Trim() }
    "rootdir"    { $rootDir   = $fields[1].Trim() }
    "TC_COVERED" { $tcCovered = $fields[1].Trim() }
    "MaxTimeDiff" { $maxTimeDiff = $fields[1].Trim() }
    default  {}
    }
}

if (-not $ipv4)
{
    "Error: This test requires an ipv4 test parameter"
    return $False
}

if (-not $rootDir)
{
    "Error: The RootDir test parameter is not defined."
    return $False
}

if (-not (Test-Path $rootDir) )
{
    "Error: The test root directory '${rootDir}' does not exist"
    return $False
}

#
# Display the test parameters so they are captured in the log
#
"IPv4      = ${ipv4}"
"rootDir   = ${rootDir}"
"tcCovered = ${tcCovered}"

#
# PowerShell test case scripts are run as a PowerShell job.  The
# default directory for a PowerShell job is not the LISA directory.
# Change the current directory to where we need to be.
#
cd $rootDir

. .\setupscripts\TCUtils.ps1

#
# Updating the summary log with Testcase ID details
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers ${tcCovered}" | Out-File $summaryLog

#
# Get the VMs Integrated Services and verify Time Sync is enabled and status is OK
#
$service = "Time Synchronization"
"Info : Verify the Integrated Services Time Sync Service is enabled"
$status = Get-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name $service
if ($status.Enabled -ne $True)
{
    "Error: The Itegrated Time Sync Service is already disabled"
    return $False
}

if ($status.PrimaryOperationalStatus -ne "Ok")
{
    "Error: Incorrect Operational Status for Time Sync Service: $($status.PrimaryOperationalStatus)"
    return $False
}

#
# Disable the Time Sync service.
#
"Info : Disabling the Integrated Services Time Sync Service"

Disable-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name $service
$status = Get-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name $service
if ($status.Enabled -ne $False)
{
    "Error: The Time Sync Service could not be disabled"
    return $False
}

if ($status.PrimaryOperationalStatus -ne "Ok")
{
    "Error: Incorrect Operational Status for Time Sync Service: $($status.PrimaryOperationalStatus)"
    return $False
}
"Info : Integrated Time Sync Service successfully disabled"

#
# Enable the Time Sync service
#
"Info : Enabling the Integrated Services Time Sync Service"

Enable-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name $service
$status = Get-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name $service
if ($status.Enabled -ne $True)
{
    "Error: Integrated Time Sync Service could not be enabled"
    return $False
}

if ($status.PrimaryOperationalStatus -ne "Ok")
{
    "Error: Incorrect Operational Status for Time Sync Service: $($status.PrimaryOperationalStatus)"
    return $False
}
"Info : Integrated Time Sync Service successfully Enabled"

#
# Now do a Time Sync to ensure the Time Sync Service is still functioning
#
"Info : Saving the VM"

Save-VM -Name $vmName -ComputerName $hvServer -Confirm:$False
if ($? -ne "True")
{
    "Error: Unable to save the VM"
    return $False
}

Start-Sleep -seconds 60

#
# Now start the VM so the automation scripts can do what they need to do
#
"Info : Starting the VM"

Start-VM -Name $vmName -ComputerName $hvServer -Confirm:$false
if ($? -ne "True")
{
    "Error: Unable to start the VM"
    return $False
}
$startTimeout = 100
if (-not (WaitForVMToStartSSH $ipv4 $StartTimeout))
{
    "Error: VM did not start within timeout period"
    return $False
}

"Info : VM successfully started"
# Check time sync
# Get a time string from the VM, then convert the Unix time string into a .NET DateTime object
#
"Info : Get time from Unix VM"
$unixTimeStr = GetUnixVMTime -sshKey "ssh\${sshKey}" -ipv4 $ipv4
if (-not $unixTimeStr)
{
    "Error: Unable to get date/time string from VM"
    return $False
}

#
# Get our time
#
$windowsTime = [DateTime]::Now.ToUniversalTime()

#
# Convert the Unix tiime string into a DateTime object
#
$unixTime = [DateTime]::Parse($unixTimeStr)

#
# Compute the timespan, then convert it to the absolute value of the total difference in seconds
#
"Compute time difference between localhost and Linux VM"
$diffInSeconds = $null
$timeSpan = $windowsTime - $unixTime

if (-not $timeSpan)
{
    "Error: Unable to compute timespan"
    return $False
}

$diffInSeconds = [Math]::Abs($timeSpan.TotalSeconds)

#
# Display the data
#
"Windows time: $($windowsTime.ToString())"
"Unix time: $($unixTime.ToString())"
"Difference: ${diffInSeconds}"

$msg = "Test case FAILED.  Time difference greater than ${maxTimeDiff} seconds"
if ($diffInSeconds -and $diffInSeconds -lt $maxTimeDiff)
{
    $msg = "Test case passed"
    $retVal = $true
}

$msg

#
# If we reached here, everything worked fine
#
return $retVal
