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
    Verify that VM sees the WWN node and port values for a HBA.

.Description
    This script compares the host provided information with the ones
	detected on a Linux guest VM.
    Pushes a script to identify the information inside the VM
    and compares the results.
    A typical test case definition for this test script would look
    similar to the following:
		<test>
			<testName>FC_WWN_basic</testName>
			<testScript>setupScripts\FC_WWN.ps1</testScript>
			<files>remote-scripts\ica\FC_WWN.sh,remote-scripts/ica/utils.sh</files>
			<setupScript>setupscripts\FC_AddFibreChannelHba.ps1</setupScript>
			<cleanupScript>setupScripts\FC_RemoveFibreChannelHba.ps1</cleanupScript>
			<timeout>800</timeout>
			<testParams>
				<param>TC_COVERED=FC-09</param>
				<param>vSANName=FC_NAME</param>
			</testParams>
		</test>

.Parameter vmName
    Name of the VM to perform the test on.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams

.Example
    setupScripts\FC_WWN.ps1 -vmName "myVm" -hvServer "localhost" -TestParams "TC_COVERED=FC-09;TestLogDir=log_folder;ipv4=VM_IP;sshkey=pki_id_rsa.ppk"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$remoteScript = "fc_wwn.sh"
$summaryLog  = "${vmName}_summary.log"
$retVal = $False

######################################################################
#
#   Helper function to execute command on remote machine.
#
#######################################################################
function execute([string] $command) {
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

#
# Extracting the node and port name values for the VM attached HBA
#
$WorldWideNodeNameSet = Get-VMFibreChannelHba -VMName $vmName -ComputerName $hvServer | Select -ExpandProperty WorldWideNodeNameSetA
$WorldWidePortNameSet = Get-VMFibreChannelHba -VMName $vmName -ComputerName $hvServer | Select -ExpandProperty WorldWidePortNameSetA

$WorldWideNodeNameSet=[system.string]::Join(",",$WorldWideNodeNameSet)
$WorldWidePortNameSet=[system.string]::Join(",",$WorldWidePortNameSet)
#
# Send the WWNN and WWNP values from the host to the guest VM
#
$cmd_wwnn="echo `"expectedWWNN=$($WorldWideNodeNameSet.ToLower())`" >> ~/constants.sh";
$result = Execute($cmd_wwnn)
if (-not $result) {
    Write-Error -Message "Error: Unable to submit command ${cmd} to VM!" -ErrorAction SilentlyContinue
    return $False
}

$cmd_wwnp="echo `"expectedWWNP=$($WorldWidePortNameSet.ToLower())`" >> ~/constants.sh";
$result = Execute($cmd_wwnp)
if (-not $result) {
    Write-Error -Message "Error: Unable to submit command ${cmd} to VM!" -ErrorAction SilentlyContinue
    return $False
}

$sts = RunRemoteScript $remoteScript

if ($sts -Match "TestSkipped") {
	$logfilename = "${TestLogDir}\$remoteScript.log"
	Get-Content $logfilename | Write-output  >> $summaryLog
    return $Skipped
}
elseif (-not $sts[-1]) {
    Write-Output "Error: Running $remoteScript script failed on VM!" >> $summaryLog
	$logfilename = "${TestLogDir}\$remoteScript.log"
	Get-Content $logfilename | Write-output  >> $summaryLog
    return $False
}
else {
	Write-Output "Matching values for WWNN ${WorldWideNodeNameSet} and WWNP ${WorldWidePortNameSet} have been found! " | Tee-Object -Append -file $summaryLog
}

return $retVal
