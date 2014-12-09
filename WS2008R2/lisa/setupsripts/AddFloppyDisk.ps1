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

param([string] $vmName, [string] $hvServer, [string] $testParams)


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



############################################################################
#
# Main entry point for script
#
############################################################################

"AddFloppyDisk.ps1"
"  vmName     = ${vmName}"
"  hvServer   = ${hvServer}"

#
# Check input arguments
#
if ($vmName -eq $null -or $vmName.Length -eq 0)
{
    "Error: VM name is null"
    return $False
}

if ($hvServer -eq $null -or $hvServer.Length -eq 0)
{
    "Error: hvServer is null"
    return $False
}

#
# AddFloppyDisk.ps1 does not use any testParams, so they are not checked
#

#
# Load the PowerShell HyperV library
#
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    $HYPERV_LIBRARY = ".\HyperVLibV2SP1\Hyperv.psd1"
    if ( (Test-Path $HYPERV_LIBRARY) )
    {
        Import-module .\HyperVLibV2SP1\Hyperv.psd1
    }
    else
    {
        "Error: The PowerShell HyperV library does not exist"
        return $False
    }
}

#
# If a .vfd file does not exist, create one
#
$defaultVhdPath = Get-VhdDefaultPath -server $hvServer
if (-not $defaultVhdPath.EndsWith("\"))
{
    $defaultVhdPath += "\"
}

$vfdName = "${defaultVhdPath}${vmName}.vfd"

$fileInfo = GetRemoteFileInfo $vfdName $hvServer
if (-not $fileInfo)
{
    #
    # The .vfd file does not exist, so create one
    #
    $newVfd = New-VFD -VFDPath $vfdName -Server $hvServer -Wait
    if (-not $newVfd)
    {
        "Error: Unable to create VFD file ${vfdName}"
        return $False
    }
}
else
{
    "Info : The file ${vfdName} already exists"
}

#
# Only attach the floppy if one is not already attached
#
$oldFloppy = Get-VMFloppyDisk -VM $vmName -Server $hvServer
if (-not $oldFloppy)
{
    $newFloppy = Add-VMFloppyDisk -VM $vmName -Path $vfdName -Server $hvServer -Force
    if (-not $newFloppy)
    {
        "Error: Unable to attach floppy to VM"
        return $False
    }
}
else
{
    "Info : A .vfd file is already attached"
}

return $True
