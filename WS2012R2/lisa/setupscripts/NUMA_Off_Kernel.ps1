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
    Verify that VM turns off NUMA when "numa=off" param is added to
    kernel boot param.
.Description
    This script compares the host provided information with the ones
    detected on a Linux guest VM.
    Verify the memory size of each NUMA node is assigned correctly.
    Verify the NUMA is turned off when "numa=off" param is added to
    kernel boot param even though host has NUMA setting.
.Parameter vmName
    Name of the VM to perform the test on.
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
.Parameter  testParams
    A string with test parameters.
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$remoteScriptCheck = "NUMA_check.sh"
$remoteScriptConfig = "NUMA_off_kernel.sh"
$summaryLog  = "${vmName}_summary.log"
$retVal = $False

######################################################################
#
#   Helper function to execute command on remote machine.
#
#######################################################################
function Execute([string] $command) {
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} $command
    return $?
}

#######################################################################
#
# Main script body
#
#######################################################################

# Checking the input arguments
if (-not $vmName) {
    LogMsg 0 "Error: VM name is null!"
    return $retVal
}

if (-not $hvServer) {
    LogMsg 0 "Error: hvServer is null!"
    return $retVal
}

if (-not $testParams) {
    LogMsg 0 "Error: No testParams provided!"
    LogMsg 0 "This script requires the test case ID and VM details as the test parameters."
    return $retVal
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

    if ($fields[0].Trim() -eq "ipv4") {
        $IPv4 = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "rootDir") {
        $rootDir = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "sshkey") {
        $sshkey = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "TestLogDir") {
        $TestLogDir = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "VCPU")
    {
        $numCPUs = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "MemSize")
    {
        $MaxMemSizeEachNode = [Int64] 0
        $tmpMemSize = $fields[1].Trim()
        if ($tmpMemSize.EndsWith("MB"))
        {
            $num = $tmpMemSize.Replace("MB","")
            $MaxMemSizeEachNode = [Convert]::ToInt64($num)
        }
        if ($tmpMemSize.EndsWith("GB"))
        {
            $num = $tmpMemSize.Replace("GB","")
            $MaxMemSizeEachNode = ([Convert]::ToInt64($num)) * 1MB
        }
    }
}

# Change the working directory to where we need to be
if (-not (Test-Path $rootDir)) {
    LogMsg 0 "Error: The directory `"${rootDir}`" does not exist!"
    return $False
}
cd $rootDir

# Delete any previous summary.log file
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

$retVal = $True

# Source TCUtils.ps1 for test related functions
if (Test-Path ".\setupScripts\TCUtils.ps1")
{
. .\setupScripts\TCUtils.ps1
}
else
{
LogMsg 0 "Error: Could not find setupScripts\TCUtils.ps1"
return $false
}

$kernel = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "uname -a"
if( $? -eq $false){
	write-output "WARNING: Could not get kernel version of $vmName" | Tee-Object -Append -file $summaryLog
}
if( $kernel.Contains("2.6") -or $kernel.Contains("i686 i386")){
	write-output "Info: NUMA not suported for kernel:`n      $kernel"  | Tee-Object -Append -file $summaryLog
	return $Skipped
}

#
# Collecting the VM generation info
#
$vmGeneration = Get-VM $vmName -ComputerName $hvServer | select -ExpandProperty Generation -ErrorAction SilentlyContinue
if ($? -eq $False) {
	$vmGeneration = 1
}

#
# Extracting the node and port name values for the VM attached HBA
#
$NumaNodes = Get-VM $vmName -ComputerName $hvServer | select -ExpandProperty NumaNodesCount

#
# Send the Numa Nodes value to the guest if it matches with the number of CPUs
#
if ( $NumaNodes -eq $numCPUs ) {
	LogMsg 9 "Info: NumaNodes and the number of CPU are matched."
}
else {
	LogMsg 0 "Error: NumaNodes and the number of CPU does not match."
	return $False
}

$cmd_numanodes="(echo expected_number=$NumaNodes; echo MaxMemSizeEachNode=$MaxMemSizeEachNode; echo VmGeneration=$VmGeneration) >> ~/constants.sh";
$result = Execute($cmd_numanodes)
if (-not $result) {
    LogMsg 0 "Error: Unable to submit command ${cmd} to VM!"
    return $False
}

$sts = RunRemoteScript $remoteScriptCheck
LogMsg 9 "Info: $sts"

if (-not $sts[-1]) {
    Write-Output "Error: Running $remoteScriptCheck script failed on VM!" >> $summaryLog
    $logfilename = "${TestLogDir}\$remoteScriptCheck.log"
    Get-Content $logfilename | Write-output  >> $summaryLog
    return $False
}
else {
    LogMsg 9 "Info: Matching values for NumaNodes: $NumaNodes has been found on the vm!"
    Write-Output "Matching values for NumaNodes: $NumaNodes has been found on the vm!" | Tee-Object -Append -file $summaryLog
}

#
# Configure kernel parameter to turn NUMA off
#
$sts = RunRemoteScript $remoteScriptConfig
LogMsg 9 "Info: $sts"

if (-not $sts[-1]) {
    Write-Output "Error: Running $remoteScriptConfig script failed on VM!" >> $summaryLog
    $logfilename = "${TestLogDir}\$remoteScriptConfig.log"
    Get-Content $logfilename | Write-output  >> $summaryLog
    return $False
}
else {
    LogMsg 9 "Info: NUMA off kernel param has been added!"
    Write-Output "NUMA off kernel param has been added!" | Tee-Object -Append -file $summaryLog
}

#
# Reboot VM (stop and start)
# Have to stop and start. Restart-VM will loss unsaved data.
#
Stop-VM -Name $vmName -ComputerName $hvServer

Write-Output "VM $vmName is shutting down." | Tee-Object -Append -file $summaryLog
if (-not $?)
{
    "Error: Unable to Shut Down VM!"
    return $False
}

$sts = WaitForVMToStop $vmName $hvServer $timeout
if (-not $sts)
{
    "Error: Unable to Shut Down VM!"
    return $False
}

Start-VM -Name $vmName -ComputerName $hvServer
Write-Output "VM $vmName is starting to make NUMA-off work." | Tee-Object -Append -file $summaryLog
$timeout = 120
while ($timeout -gt 0)
{
    if ( (TestPort $ipv4) )
    {
        break
    }

    Start-Sleep -seconds 2
    $timeout -= 2
}

if ($timeout -eq 0)
{
    LogMsg 0 "Error: Test case timed out for VM to be running again!"
    return $False
}

#
# Check the kernel parameter working or not
#
$NumaNodesHost = Get-VM $vmName -ComputerName $hvServer | select -ExpandProperty NumaNodesCount
Write-Output "Info: VM $vmName is configured with $NumaNodesHost nodes." | Tee-Object -Append -file $summaryLog

$NumaNodesGuest = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "numactl -H | grep cpu | wc -l"
LogMsg 9 "Debug: Only $NumaNodesGuest node is available for VM when NUMA-Off kernel param enabled."
Write-Output "Only $NumaNodesGuest node is available for VM when NUMA-Off kernel param enabled." | Tee-Object -Append -file $summaryLog

if ($NumaNodesGuest -eq 1) {
    LogMsg 9 "Info: Kernel parameter 'numa=off' works."
    Write-Output "Test successful: Kernel parameter 'numa=off' works" | Tee-Object -Append -file $summaryLog
}
else {
    LogMsg 0 "Error: Kernel parameter numa=off does not work."
    Write-Output "Failed: Kernel parameter numa=off does not work." | Tee-Object -Append -file $summaryLog
    return $False
}

return $retVal
