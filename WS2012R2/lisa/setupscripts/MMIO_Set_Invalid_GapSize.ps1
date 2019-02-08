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
	Attempts to send a NMI as an unprivileged user.

.Description
	The script verifies that the PCI hole for a Linux VM cannot be configured
	outside the valid size range of 128MB - 3.5GB.
	Any size value outside this range is an invalid gap size. If user tries to
	set an invalid gap size then the system returns 4096 error code; for all
	valid gap sizes system returns 0.

    The test case definition for this test case would look similar to:
        <test>
            <testName>MMIO_Set_Invalid_GapSize</testName>
            <testScript>setupscripts\MMIO_Set_Invalid_GapSize.ps1</testScript>
            <timeout>600</timeout>
            <onError>Continue</onError>
			<testParams>
                <param>TC_COVERED=MMIO-02</param>
            </testParams>
            <noReboot>True</noReboot>
        </test>

.Parameter vmName
    Name of the VM to perform the test with.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.

.Example
    .\MMIO_Set_Invalid_GapSize.ps1 -vmName "MyVM" -hvServer "localhost" -testParams "TC_COVERED=MMIO-02"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false
$newGapSize = @(64,126,3586,4096)
$TC_COVERED = $null
$rootDir = $null
$failCount = 0

#######################################################################
#
# function GetVmSettingData ()
# This function will filter all the settings for given VM
#
#######################################################################
function GetVmSettingData([String] $name, [String] $server)
{
    if (-not $name) {
        return $null
    }

    $vssd = gwmi -n root\virtualization\v2 -class Msvm_VirtualSystemSettingData -ComputerName $server
    if (-not $vssd) {
		return $null
    }

    foreach ($vm in $vssd) {
        if ($vm.ElementName -ne $name) {
            continue
        }
		return $vm
    }
    return $null
}

#######################################################################
#
# function TestMMIOgap ()
# This function will set the MMIO gap size
#
#######################################################################
function TestMMIOGap([INT] $newGapSize)
{
	#
	# Getting the VM settings
	#
    $vssd = GetVmSettingData $vmName $hvServer
    if (-not $vssd) {
        Write-Output "Error: Unable to find settings data for VM '${vmName}'!" | Tee-Object -Append -file $summaryLog
        return $false
    }

	#
	# Create a WMI management object
	#
    $mgmt = gwmi -n root\virtualization\v2 -class Msvm_VirtualSystemManagementService -ComputerName $hvServer
    if(!$?) {
        Write-Output "Error: Unable to create WMI Management Object!" | Tee-Object -Append -file $summaryLog
        return $false
    }

    $vssd.LowMmioGapSize = $newGapSize
    $sts = $mgmt.ModifySystemSettings($vssd.gettext(1))

    if ($sts.ReturnValue -eq 0) {
            Write-Output "Test failed! Incorrect MMIO gap size of $newGapSize was set to VM $VmName" | Tee-Object -Append -file $summaryLog
			return $false
        }
	elseif ($sts.ReturnValue -ne 0) {
            Write-Output "Test passed! MMIO gap size of $newGapSize cannot be set." | Tee-Object -Append -file $summaryLog
            return $true
        }
     else {
        Write-Output "Test failed to validate or configure the MMIO gap size!" | Tee-Object -Append -file $summaryLog
        return $false
    }
    Write-Output "Test Failed! New gap size = $($vssd.LowMmioGapSize) MB has been set" | Tee-Object -Append -file $summaryLog
}

#
# Checking the mandatory testParams
#
$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")

    if ($fields[0].Trim() -eq "TC_COVERED") {
        $TC_COVERED = $fields[1].Trim()
    }
     if ($fields[0].Trim() -eq "rootDir") {
        $rootDir = $fields[1].Trim()
    }
}

if (-not $TC_COVERED) {
    "Error: Missing testParam TC_COVERED value!"
}

if (-not $rootDir) {
    "Error: Missing testParam rootDir value!"
    return $retVal
}

#
# Change the working directory for the log files
# Delete any previous summary.log file, then create a new one
#
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist"
    return $retVal
}
cd $rootDir

$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#######################################################################
#
# Main script body
#
#######################################################################
#
# Check input arguments
#
if (-not $vmName) {
    Write-Output "Error: VM name is null!"
    return $retVal
}

if (-not $hvServer) {
    Write-Output "Error: hvServer is null!"
    return $retVal
}

#
# Stopping the VM prior to setting the gap size
#
if ((Get-VM -Name $vmName -ComputerName $hvServer).state -ne "Off" -and $vm.Heartbeat -ne "") {
    Stop-VM -Name $vmName -ComputerName $hvServer -Force
    if(!$?) {
        Write-Output "Error: VM could not be stopped!" | Tee-Object -Append -file $summaryLog
        return $false
    }
}

#
# Attempting to set the incorrect MMIO gap sizes
#
for ($i=0; $i -le $NewGapSize.Length -1; $i++) {
	$pass = TestMMIOGap $newGapSize[$i]
	if ($pass[1] -eq $False) {
		$failCount++
	}
}
$retval = $true

if ($failCount) {
	Write-Output "Test Failed! At least one invalid MMIO gap size has been set." | Tee-Object -Append -file $summaryLog
	$retVal = $false
}

# Starting the VM for LISA clean-up
Start-Sleep -S 2

if ((Get-VM -ComputerName $hvServer -Name $vmName).State -eq "Off") {
	Start-VM -Name $vmName -ComputerName $hvServer
    if (-not $?){
        "Error: Unable to start VM ${vmName}"
        return $false
    }
}
$timeout = 150
if (-not (WaitForVMToStartKVP $vmName $hvServer $timeout )) {
    Write-Output "Error: ${vmName} failed to start KVP" | Tee-Object -Append -file $summaryLog
    return $false
}

return $retval
