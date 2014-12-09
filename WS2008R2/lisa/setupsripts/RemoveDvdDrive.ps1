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
    

.Description
    

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>
#######################################################################
#
# RemoveIsoFromDvd.ps1
#
# Description:
#    This script will "unmount" a .iso file in the DVD drive (IDE 1 0)
#
#######################################################################

param ([String] $vmName, [String] $hvServer, [String] $testParams)


#######################################################################
#
# GetRemoteFileInfo()
#
# Description:
#     Use WMI to retrieve file information for a file residing on the
#     Hyper-V server.
#
# Return:
#     A FileInfo structure if the file exists, null otherwise.
#
#######################################################################
function GetRemoteFileInfo([String] $filename, [String] $server )
{
    $fileInfo = $null
    
    if (-not $filename)
    {
        return $null
    }
    
    if (-not $server)
    {
        return $null
    }
    
    $remoteFilename = $filename.Replace("\", "\\")
    $fileInfo = Get-WmiObject -query "SELECT * FROM CIM_DataFile WHERE Name='${remoteFilename}'" -computer $server
    
    return $fileInfo
}


"removeIsoFromDvd.ps1"
"  vmName = ${vmName}"
"  hvServer = ${hvServer}"
"  testParams = ${testParams}"

$retVal = $False

$isoFilename = $null

#
# Check arguments
#
if (-not $vmName)
{
    "Error: Missing vmName argument"
    return $False
}

if (-not $hvServer)
{
    "Error: Missing hvServer argument"
    return $False
}

#
# This script does not use any testParams
#

$error.Clear()

#
# Load the HyperVLib version 2 modules
#
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2SP1\Hyperv.psd1
    if ($error.count -gt 0)
    {
        "Error: Unable to load the Hyperv Library"
        $error[0].Exception
        return $False
    }
}

#
# Make sure the DVD drive exists on the VM
#
$ide1 = Get-VMDiskController $vmName -server $hvServer -IDE 1
if (-not $ide1)
{
    "Error: Cannot find IDE controller 1 on VM ${vmName}"
    $error[0].Exception
    return $False
}

$dvd = Get-VMDriveByController -Controller $ide1 -lun 0
if (-not $dvd)
{
    "Error: Cannot find DVD drive (IDE 1 0) on VM ${vmName}"
    $error[0].Exception
    return $False
}

#
# Check if a .iso is mounted in the drive
#
$disk = Get-VMDiskByDrive -drive $dvd
if (-not $disk)
{
    "Info : no .iso file mounted in DVD drive IDE 1 0"
    return $True
}

#
# Remove the .iso file from the VMs DVD drive
#
$newDisk = Remove-VMDrive -vm $vmName -ControllerID 1 -Lun 0 -server $hvServer -Force
if (-not $newDisk)
{
    "Error: Unable to remove drive"
    $error[0].Exception
    return $False
}
else
{
    $retVal = $True
}

return $retVal
