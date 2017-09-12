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
    Verify Production Checkpoint feature.

.Description
    This script will stop networking and attach a CD ISO to the vm. 
    After that it will proceed with making a Production Checkpoint on test VM
    and check if the ISO is still mounted

    A typical test case definition for this test script would look
    similar to the following:
        <test>
            <testName>ProductionCheckpoint_ISO_NoNetwork</testName>
            <setupScript>setupscripts\RevertSnapshot.ps1</setupScript>
            <testScript>setupscripts\Production_checkpoint_ISO_NoNetwork.ps1</testScript> 
            <testParams>
                <param>TC_COVERED=PC-08</param>
                <param>snapshotName=ICABase</param>
            </testParams>
            <timeout>2400</timeout>
            <OnError>Continue</OnError>
        </test>


.Parameter vmName
    Name of the VM to perform the test with.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.

.Example
    setupScripts\STOR_TakeRevert_Snapshot.ps1 -vmName "myVm" -hvServer "localhost"
     -TestParams "TC_COVERED=PC-08;snapshotname=ICABase"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

# Define the guest side script
$remoteScript = "STOR_VSS_StopNetwork.sh"

$retVal = $false

######################################################################
# Runs a remote script on the VM without checking the log 
#######################################################################
function RunRemoteScriptNoState($remoteScript)
{

    "./${remoteScript} > ${remoteScript}.log" | out-file -encoding ASCII -filepath runtest.sh 

    .\bin\pscp -i ssh\${sshKey} .\runtest.sh root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy runtest.sh to the VM"
       return $False
    }      

    .\bin\pscp -i ssh\${sshKey} .\remote-scripts\ica\${remoteScript} root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy ${remoteScript} to the VM"
       return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix ${remoteScript} 2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to run dos2unix on ${remoteScript}"
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to run dos2unix on runtest.sh" 
        return $False
    }
    
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x ${remoteScript}   2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to chmod +x ${remoteScript}" 
        return $False
    }
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to chmod +x runtest.sh " -
        return $False
    }

    # Run the script on the vm
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "at -f runtest.sh now" 
    if (-not $?)
    {
        Write-Output "Error: Unable to submit runtest.sh to the vm"
        return $False
    }

    del runtest.sh
    return $True
}

#######################################################################
#
# Main script body
#
#######################################################################

# Define and cleanup the summaryLog
$summaryLog  = "${vmName}_summary.log"
echo "Covers Production Checkpoint Testing" > $summaryLog

# Check input arguments
if ($vmName -eq $null)
{
    "ERROR: VM name is null"
    return $retVal
}

# Check input params
$params = $testParams.Split(";")

foreach ($p in $params)
{
  $fields = $p.Split("=")

  switch ($fields[0].Trim())
    {
    "TC_COVERED"  { $TC_COVERED = $fields[1].Trim() }
    "sshKey"      { $sshKey = $fields[1].Trim() }
    "ipv4"        { $ipv4 = $fields[1].Trim() }
    "rootdir"     { $rootDir = $fields[1].Trim() }
     default  {}
    }
}

if ($null -eq $sshKey)
{
    "ERROR: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4)
{
    "ERROR: Test parameter ipv4 was not specified"
    return $False
}

if ($null -eq $rootdir)
{
    "ERROR: Test parameter rootdir was not specified"
    return $False
}

# Change the working directory to where we need to be
cd $rootDir

Write-output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Source the TCUtils.ps1 file
. .\setupscripts\TCUtils.ps1

# if host build number lower than 10500, skip test
$BuildNumber = GetHostBuildNumber $hvServer
if ($BuildNumber -eq 0) {
    return $False
}
elseif ($BuildNumber -lt 10500) {
	"Info: Feature supported only on WS2016 and newer"
    return $Skipped
}

# Check if the Vm VHD in not on the same drive as the backup destination
$vm = Get-VM -Name $vmName -ComputerName $hvServer
if (-not $vm)
{
    "Error: VM '${vmName}' does not exist"
    return $False
}

# Check to see Linux VM is running VSS backup daemon
$sts = RunRemoteScript "STOR_VSS_Check_VSS_Daemon.sh"
if (-not $sts[-1])
{
    Write-Output "ERROR executing $remoteScript on VM. Exiting test case!" >> $summaryLog
    Write-Output "ERROR: Running $remoteScript script failed on VM!"
    return $False
}

Write-Output "VSS Daemon is running " >> $summaryLog

# Insert CD/DVD .
$CdPath = ".\bin\CDTEST.iso"
Set-VMDvdDrive -VMName $vmName -ComputerName $hvServer -Path $CdPath
if (-not $?)
    {
        "Error: Unable to Add ISO $CdPath" 
        return $False
    }

Write-Output "Attached DVD: Success" >> $summaryLog

# Bring down the network. 
RunRemoteScriptNoState $remoteScript

Start-Sleep -Seconds 3

# Make sure network is down.
$sts = ping $ipv4
$pingresult = $False
foreach ($line in $sts)
{
   if (( $line -Like "*unreachable*" ) -or ($line -Like "*timed*")) 
   {
       $pingresult = $True
   }
}

if ($pingresult) {
    Write-Output "Network Down: Success"
    Write-Output "Network Down: Success" >> $summaryLog
} else {
    Write-Output "Network Down: Failed" >> $summaryLog
    Write-Output "ERROR: Running $remoteScript script failed on VM!"
    return $False
}

#Check if we can set the Production Checkpoint as default
if ($vm.CheckpointType -ne "ProductionOnly"){
    Set-VM -Name $vmName -CheckpointType ProductionOnly -ComputerName $hvServer
    if (-not $?)
    {
       Write-Output "Error: Could not set Production as Checkpoint type"  | Out-File -Append $summaryLog
       return $false
    }
}

$random = Get-Random -minimum 1024 -maximum 4096
$snapshot = "TestSnapshot_$random"
Checkpoint-VM -Name $vmName -SnapshotName $snapshot -ComputerName $hvServer
if (-not $?)
{
    Write-Output "Error: Could not create checkpoint" | Out-File -Append $summaryLog
    $error[0].Exception.Message
    return $False
}

Restore-VMSnapshot -VMName $vmName -Name $snapshot -ComputerName $hvServer -Confirm:$false
if (-not $?)
{
    Write-Output "Error: Could not restore checkpoint" | Out-File -Append $summaryLog
    $error[0].Exception.Message
    return $False
}

# Starting the VM
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

# Check if ISO file is still present
$isoInfo = Get-VMDvdDrive -VMName $vmName -ComputerName $hvServer
if ($isoInfo.Path -like "*CDTEST*" -eq $False){
    Write-Output "Error: The ISO is missing from the VM" | Out-File -Append $summaryLog
    return $False 
}
Write-Output "The ISO file is present. Test succeeded" >> $summaryLog

#
# Delete the snapshot
#
"Info : Deleting Snapshot ${Snapshot} of VM ${vmName}"
Remove-VMSnapshot -VMName $vmName -Name $snapshot -ComputerName $hvServer
if ( -not $?)
{
   Write-Output "Error: Could not delete snapshot"  | Out-File -Append $summaryLog
}

return $true