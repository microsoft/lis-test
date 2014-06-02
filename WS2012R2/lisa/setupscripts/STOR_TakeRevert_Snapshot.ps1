
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

<#
.Synopsis
    Verify take snapshot and revert snapshot operations work.
    
.Description
    Tests to see that the virtual machine snapshot operation works as well as
    the revert snapshot operation.

    A typical test case definition for this test script would look
    similar to the following:
             <test>
            <testName>TakeRevert_SnapShot</testName>
            <testScript>setupScripts\STOR_TakeRevert_Snapshot.ps1</testScript>
            <timeout>1800</timeout>
            <testParams>
                <param>snapshotname=ICABase</param>
                <param>TC_COVERED=STOR-42,STOR-43</param>
        </testParams>
            <onError>Continue</onError>
            <noReboot>False</noReboot>
        </test>

.Parameter vmName
    Name of the VM to perform the test with.
    
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
    
.Parameter testParams
    A semicolon separated list of test parameters.
    
.Example
    setupScripts\STOR_TakeRevert_Snapshot.ps1 -vmName "myVm" -hvServer "localhost -TestParams "TC_COVERED=STOR-42,STOR-43;snapshotname=ICABase"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false
$TC_COVERED = $null
$rootDir = $null
$ipv4 = $null
$sshKey = $null
$snapshotname = $null
$random = Get-Random -minimum 1024 -maximum 4096

#
# Check input arguments
#
if (-not $vmName)
{
    "Error: VM name is null."
    return $retVal
}

if (-not $hvServer)
{
    "Error: hvServer is null."
    return $retVal
}

if (-not $testParams)
{
    "Error: No testParams provided!"
    "This script requires the test case ID and the logs folder as the test parameters."
    return $retVal
}

#
# Checking the mandatory testParams
#
$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    if ($fields[0].Trim() -eq "TC_COVERED")
    {
        $TC_COVERED = $fields[1].Trim()
    }
     if ($fields[0].Trim() -eq "rootDir")
    {
        $rootDir = $fields[1].Trim()
    }
     if ($fields[0].Trim() -eq "snapshotname")
    {
        $snapshotname = $fields[1].Trim()
    }
     if ($fields[0].Trim() -eq "ipv4")
    {
        $ipv4 = $fields[1].Trim()
    }
     if ($fields[0].Trim() -eq "sshKey")
    {
        $sshKey = $fields[1].Trim()
    }
}

if (-not $TC_COVERED)
{
    "Error: Missing testParam TC_COVERED value"
    return $retVal
}

if (-not $rootDir)
{
    "Error: Missing testParam rootDir value"
    return $retVal
}

if (-not $ipv4)
{
    "Error: Missing testParam ipv4 value"
    return $retVal
}

if (-not $sshKey)
{
    "Error: Missing testParam sshKey value"
    return $retVal
}

if (-not $snapshotname)
{
    "Error: Missing testParam snapshotname value"
    return $retVal
}

# Change the working directory for the log files
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $retVal
}
cd $rootDir

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#######################################################################
#
# Main script block
#
#######################################################################

# Source the TCUtils.ps1 file
. .\setupscripts\TCUtils.ps1

#
#Creating a file for snapshot
#
$sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "touch /root/PostSnapData.txt " | out-null
if (-not $?)
{
    Write-Output "Error: Unable to create file on VM" | Out-File -Append $summaryLog
    return $False
}

Write-Host "Waiting for VM $vmName to shut-down..."
if ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Off") {
    Stop-VM -ComputerName $hvServer -Name $vmName -Force -Confirm:$false
}

#
# Waiting until the VM is off
#
if (-not (WaitForVmToStop $vmName $hvServer 300))
{
    Write-Output "Error: Unable to stop VM"
    return $False
}

#
# Take a snapshot then restore the VM to the snapshot
#
"Info : Taking Snapshot operation on VM"

$Snapshot = "TestSnapshot_$random"
Checkpoint-VM -Name $vmName -SnapshotName $Snapshot -ComputerName $hvServer
if (-not $?)
{
    Write-Output "Error: Taking snapshot" | Out-File -Append $summaryLog
    return $False
}

"Info : Restoring Snapshot operation on VM"
Restore-VMSnapshot -VMName $vmName -Name $snapshotname -ComputerName $hvServer -Confirm:$false
if (-not $?)
{
    Write-Output "Error: Restoring snapshot" | Out-File -Append $summaryLog
    $error[0].Exception.Message
    return $False
}

#
# Starting the VM
#
Start-VM $vmName -ComputerName $hvServer

#
# Waiting for the VM to run again and respond to SSH - port 22
#
$timeout = 300
while ($timeout -gt 0) {
    if ( (TestPort $ipv4) ) {
        break
    }

    Start-Sleep -seconds 2
    $timeout -= 2
}

if ($timeout -eq 0) {
    Write-Output "Error: Test case timed out waiting for VM to boot" | Out-File -Append $summaryLog
    return $False
}

"Info : Checking if the test file is still present..."
$sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "stat /root/PostSnapData.txt 2>/dev/null" | out-null
if ( $?)
{
    Write-Output "Error: File still present in VM" | Out-File -Append $summaryLog
    return $False
}
$retVal = $True

 Write-Output "Snapshot/Restore : Success!" | Out-File -Append $summaryLog

#
# Delete the snapshot
#
"Info : Deleting Snapshot ${Snapshot} of VM ${vmName}"
Remove-VMSnapshot -VMName $vmName -Name $Snapshot -ComputerName $hvServer
if ( -not $?)
{
   Write-Output "Error: Deleting snapshot"  | Out-File -Append $summaryLog
}

return $retVal