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
    Verify that VM sees the correct number of Numa Nodes compared to the number of CPUs.
.Description
    This script compares the host provided information with the ones
    detected on a Linux guest VM.
    Pushes a script to identify the information inside the VM
    and compares the results.
    To work accordingly we have to disable dynamic memory first.
.Parameter vmName
    Name of the VM to perform the test on.
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$remoteScript = "NUMA_check.sh"
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
# GetNumaSupportStatus()
#
##########################################################
#############
function GetNumaSupportStatus([string] $kernel)
{
    <#
    .Synopsis
        Try to determine whether guest support numa
    .Description
        Get whether numa is supported or not based on kernel verison. Generally, from RHEL 6.6 with kernel version 2.6.32-504, NUMA is supported well.
    .Parameter kernel
        $kernel version gets from "uname -r"
    .Example
        GetNumaSupportStatus 2.6.32-696.el6.x86_64
    #>

    if( $kernel.Contains("i686") `
        -or $kernel.Contains("i386")){
            return $false
    }
    $numaSupport = "2.6.32.504"
    $kernelSupport = $numaSupport.split(".")
    $kernelCurrent = $kernel.replace("-",".").split(".")

    for ($i=0; $i -le 3; $i++){
        if ($kernelCurrent[$i] -lt $kernelSupport[$i] ){
            return $false
        }
    }
    return $true
}
#######################################################################
#
# Main script body
#
#######################################################################

# Checking the input arguments
if (-not $vmName) {
    "Error: VM name is null!"
    return $retVal
}

if (-not $hvServer) {
    "Error: hvServer is null!"
    return $retVal
}

if (-not $testParams) {
    "Error: No testParams provided!"
    "This script requires the test case ID and VM details as the test parameters."
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
    if ($fields[0].Trim() -eq "NumaNodes")
    {
        $vcpuOnNode = $fields[1].Trim()
    }
}

# Change the working directory to where we need to be
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist!"
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
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
  }

$kernel = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "uname -r"
if( $? -eq $false){
    write-output "WARNING: Could not get kernel version of $vmName" | Tee-Object -Append -file $summaryLog
}

$numaVal = GetNumaSupportStatus $kernel

if( -not $numaVal ){
	write-output "Info: NUMA not suported for kernel:`n      $kernel"  | Tee-Object -Append -file $summaryLog
	return $Skipped
}

#
# Extracting the node and port name values for the VM attached HBA
#
$GetNumaNodes=Get-VM -Name $vmName -ComputerName $hvServer | select -ExpandProperty NumaNodesCount

#
# Send the Numa Nodes value to the guest if it matches with the number of CPUs
#
if ( $GetNumaNodes -eq $numCPUs/$vcpuOnNode ) {
    Write-Output "Info: NumaNodes and the number of CPU are matched."
}
else {
    Write-Output "Error: NumaNodes and the number of CPU does not match."
    return $False
}

$cmd_numanodes="echo `"expected_number=$($numCPUs/$vcpuOnNode)`" >> ~/constants.sh";
$result = Execute($cmd_numanodes)
if (-not $result) {
    Write-Error -Message "Error: Unable to submit command ${cmd} to VM!" -ErrorAction SilentlyContinue
    return $False
}

$sts = RunRemoteScript $remoteScript

if (-not $sts[-1]) {
    Write-Output "Error: Running $remoteScript script failed on VM!" >> $summaryLog
    $logfilename = "${TestLogDir}\$remoteScript.log"
    Get-Content $logfilename | Write-output  >> $summaryLog
    return $False
}
else {
    Write-Output "Matching values for NumaNodes: $vcpuOnNode has been found on the VM! " | Tee-Object -Append -file $summaryLog
}

return $retVal
