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
    Mount a .iso in the default DVD drive.

.Description
    Mount a .iso in the default DVD drive.

.Parameter vmName
    Name of the VM with the DVD drive to mount.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParam
    Semicolon separated list of test parameters.

.Example
    .\InsertIsoInDvd.ps1 "testVM" "localhost" "isoFilename=test.iso"
#>



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


#######################################################################
#
# Main script body
#
#######################################################################
"insertIsoInDvd.ps1"
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

if (-not $testParams)
{
    "Error: Missing testParams argument"
    return $False
}

#
# Extract the testParams we are concerned with
#
$params = $testParams.Split(';')
foreach ($p in $params)
{
    if ($p.Trim().Length -eq 0)
    {
        continue
    }

    $tokens = $p.Trim().Split('=')
    
    if ($tokens.Length -ne 2)
    {
	    # Just ignore it
        continue
    }
    
    $lValue = $tokens[0].Trim()
    $rValue = $tokens[1].Trim()
    
    if ($lValue -eq "IsoFilename")
    {
        $isoFilename = $rValue
    }
}

#
# Make sure we found the parameters we need to do our job
#
if (-not $isoFilename)
{
    "Error: Test parameters is missing the IsoFilename parameter"
    return $False
}

$error.Clear()

#
# Make sure the DVD drive exists on the VM
#
$dvd = Get-VMDvdDrive $vmName -ComputerName $hvServer -ControllerLocation 0 -ControllerNumber 1
if ($dvd)
{
    Remove-VMDvdDrive $dvd -Confirm:$False
    if($? -ne "True")
    {
        "Error: Cannot remove DVD drive from ${vmName}"
        $error[0].Exception
        return $False
    }
}

#
# Make sure the .iso file exists on the HyperV server
#
if (-not ([System.IO.Path]::IsPathRooted($isoFilename)))
{
    $obj = Get-WmiObject -ComputerName $hvServer -Namespace "root\virtualization\v2" -Class "MsVM_VirtualSystemManagementServiceSettingData"
        
    $defaultVhdPath = $obj.DefaultVirtualHardDiskPath
	
    if (-not $defaultVhdPath)
    {
        "Error: Unable to determine VhdDefaultPath on HyperV server ${hvServer}"
        $error[0].Exception
        return $False
    }
   
    if (-not $defaultVhdPath.EndsWith("\"))
    {
        $defaultVhdPath += "\"
    }
  
    $isoFilename = $defaultVhdPath + $isoFilename
   
}   

$isoFileInfo = GetRemoteFileInfo $isoFilename $hvServer
if (-not $isoFileInfo)
{
    "Error: The .iso file $isoFilename does not exist on HyperV server ${hvServer}"
    return $False
}

#
# Insert the .iso file into the VMs DVD drive
#
Add-VMDvdDrive -VMName $vmName -Path $isoFilename -ControllerNumber 1 -ControllerLocation 0 -ComputerName $hvServer -Confirm:$False
if ($? -ne "True")
{
    "Error: Unable to mount"
    $error[0].Exception
    return $False
}
else
{
    $retVal = $True
}

return $retVal
