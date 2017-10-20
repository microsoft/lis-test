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


param([string] $vmName, [string] $hvServer, [string] $testParams)

$summaryLog  = "${vmName}_summary.log"

#######################################################################
#
# Main script body
#
#######################################################################

#
# Check input arguments
#
if ($vmName -eq $null) {
    "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null) {
    "Error: hvServer is null"
    return $retVal
}

$params = $testParams.Split(";")

foreach ($p in $params) {
	$fields = $p.Split("=")
    
	switch ($fields[0].Trim()) {
		"sshKey" { $sshKey  = $fields[1].Trim() }
		"ipv4"   { $ipv4    = $fields[1].Trim() }
		"hvServer"   { $hvServer    = $fields[1].Trim() }
		"rootdir" { $rootDir = $fields[1].Trim() }
        "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
		default  {}
    }
}

if ($null -eq $sshKey) {
    "Error: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4) {
    "Error: Test parameter ipv4 was not specified"
    return $False
}

#
# Change the working directory to where we need to be
#
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist!"
    return $False
}

Write-output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

cd $rootDir

#
# Source the TCUtils.ps1 file
#
. .\setupscripts\TCUtils.ps1

.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} 'dos2unix ./install_lis_next.sh'
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} 'chmod +x ./install_lis_next.sh'
$sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} './install_lis_next.sh'
if (-not $sts) {
    "Error: Failed to install lis next"
    return $False
}

.\bin\plink.exe -i ssh\${sshKey} root@${ipv4}  'reboot'

$timeout = 300
if (-not (WaitForVMToStartKVP $vmName $hvServer $timeout ))
{
    "Error: ${vmName} failed to start"
    return $False
}

"Info : Patch test completed"
return $True
