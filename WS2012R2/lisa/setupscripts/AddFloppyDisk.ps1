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
    Mount a floppy vfd file in the VMs floppy drive.

.Description
    Mount a floppy in the VMs floppy drive
    The .vfd file that will be mounted in the floppy drive
    is named <vmName>.vfd.  If the virtual floppy does not
    exist, it will be created.

.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

.Example
    <test>
		<testName>FloppyDisk</testName>
		<testScript>STOR_Floppy_Disk.sh</testScript>    
		<files>remote-scripts\ica\STOR_Floppy_Disk.sh</files> 
		<setupScript>setupscripts\AddFloppyDisk.ps1</setupScript> 
		<cleanupScript>setupScripts\RemoveFloppyDisk.ps1</cleanupScript>
		<noReboot>False</noReboot>
		<testParams>               
			<param>TC_COVERED=STOR-01</param>
		</testParams>
		<timeout>600</timeout>			
  </test>

#>

param ([String] $vmName, [String] $hvServer, [String] $testParams)

$vfdPath = $null

#############################################################
#
# Main script body
#
#############################################################
$retVal = $False

#
# Check the required input args are present
#
if (-not $vmName)
{
    "Error: null vmName argument"
    return $False
}

if (-not $hvServer)
{
    "Error: null hvServer argument"
    return $False
}

# Source TCUtils.ps1 for common functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
	. .\setupScripts\TCUtils.ps1
	"Info: Sourced TCUtils.ps1"
}
else {
	"Error: Could not find setupScripts\TCUtils.ps1"
	return $false
}

# If a .vfd file does not exist, create one
#
#
$hostInfo = Get-VMHost -ComputerName $hvServer
if (-not $hostInfo)
{
	"Error: Unable to collect Hyper-V settings for ${hvServer}"
	return $False
}

$defaultVhdPath=$hostInfo.VirtualHardDiskPath
        if (-not $defaultVhdPath.EndsWith("\"))
        {
            $defaultVhdPath += "\"
        }

$vfdPath = "${defaultVhdPath}${vmName}.vfd"

$fileInfo = GetRemoteFileInfo $vfdPath $hvServer
if (-not $fileInfo)
{
    #
    # The .vfd file does not exist, so create one
    #
    $newVfd = New-VFD -Path $vfdPath -ComputerName $hvServer 
    if (-not $newVfd)
    {
        "Error: Unable to create VFD file ${vfdPath}"
        return $False
    }
}
else {
    "Info: The file ${vfdPath} already exists"
}

#
# Add the vfd
#
Set-VMFloppyDiskDrive -Path $vfdPath -VMName $vmName -ComputerName $hvServer
if ($? -eq "True")
{
    $retVal = $True
}
else {
    "Error: Unable to mount the floppy file!"
}

return $retVal
