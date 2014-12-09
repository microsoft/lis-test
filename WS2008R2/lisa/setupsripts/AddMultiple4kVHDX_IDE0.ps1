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
############################################################################
#
# AddMultiple4kVHDX_IDE0.ps1
#
# This script assumes it is running on a Windows 8 machine
# with access to the Windows 8 Hyper-V snap-in.
#
# Description:
#     This is a setup script that will run before the VM is booted.
#     The script will first move the boot disk from IDE 0,0 location to IDE1,0 location. Then it will create
#     two 4k disks and will attach to IDE0,0 and IDE0.1 location.   
#
#     Setup scripts (and cleanup scripts) are run in a separate
#     PowerShell environment, and do not have access to the
#     environment running the ICA scripts
#
#     The .xml entry to specify this startup script would be:
#
#         <setupScript>SetupScripts\AddHardDisk.ps1</setupScript>
#
#   The ICA scripts will always pass the vmName, hvServer, and a
#   string of testParams from the test definition separated by
#   semicolons. The testParams for this script identify disk
#   controllers, hard drives, .vhd type, and sector size.  The
#   testParamss have the format of:
#
#      ControllerType=Controller Index, Lun or Port, vhd type, sector size
#
#   The following are some examples
#
#   IDE=0,1,Dynamic,512   : Add IDE hard drive on IDE 0, port 1, .vhd type Fixed, sector size of 512 bytes
#   IDE=1,1,Fixed,4096    : Add IDE hard drive on IDE 1, port 1, .vhd type Fixed, sector size of 4096 bytes
#
#   The following testParams
#
#     <testParams>
#          <param>IDE=1,1,Fixed,512</param>
#     <testParams>
#
#   will be parsed into the following string by the ICA scripts and passed
#   to the setup script:
#
#       "IDE=0,0,Dynamic,4096;IDE=1,1,Fixed,512"
#
#   All setup and cleanup scripts must return a boolean ($true or $false)
#   to indicate if the script completed successfully.
#
############################################################################
param([string] $vmName, [string] $hvServer, [string] $testParams)

$global:MinDiskSize = 1GB
$global:DefaultDynamicSize = 127GB


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
# CreateHardDrive
#
# Description
#     If the -SCSI options is false, an IDE drive is created
#
############################################################################
function CreateHardDrive( [string] $vmName, [string] $server, [int] $ControllerID,
                          [int] $Lun, [string] $vhdType, [string] $sectorSize)
{
    $retVal = $false

    "CreateHardDrive $vmName $server $controllerID $lun $vhdType $sectorSize"
    
    #
    # Make sure it's a valid IDE ControllerID.  For IDE, it must 0 or 1.
    #
    #
    $controllerType = "IDE"
    
    if ($ControllerID -lt 0 -or $ControllerID -gt 1)
    {
        "Error: CreateHardDrive was passed an invalid IDE Controller ID: $ControllerID"
        return $False
    }
        
    #
    # If the hard drive exists, complain...
    #
    $drive = Get-VMHardDiskDrive -VMName $vmName -ControllerNumber $controllerID -ControllerLocation $Lun -ControllerType $controllerType -ComputerName $server
    if ($drive)
    {
        "Error: drive $controllerType $controllerID $Lun already exists"
        return $False
    }
    else
    {
        #
        # Create the .vhd file if it does not already exist, then create the drive and mount the .vhdx
        #
        #$hostInfo = Get-VMHost -ComputerName $server
        <#if (-not $hostInfo)
        {
            "Error: Unable to collect Hyper-V settings for ${server}"
            return $False
        }#>

        $defaultVhdPath = Get-VhdDefaultPath -server $server

       # $defaultVhdPath = $hostInfo.VirtualHardDiskPath
        if(-not $defaultVhdPath.EndsWith("\"))
        {
            $defaultVhdPath += "\"
        }

	    $vhdName = $defaultVhdPath + $vmName + "-" + $controllerType + "-" + $controllerID + "-" + $lun + "-" + $vhdType + "4k" + ".vhdx" 


        $fileInfo = GetRemoteFileInfo -filename $vhdName -server $server
        if (-not $fileInfo)
        {
            $nv = hyper-v\New-Vhd -Path $vhdName -size $global:MinDiskSize -Dynamic:($vhdType -eq "Dynamic") -LogicalSectorSize ([int] $sectorSize)  -ComputerName $server
            if ($nv -eq $null)
            {
                "Error: New-VHD failed to create the new .vhd file: $($vhdName)"
                return $False
            }
        }

        $error.Clear()
        Add-VMHardDiskDrive -VMName $vmName -Path $vhdName -ControllerNumber $controllerID -ControllerLocation $Lun -ControllerType $controllerType -ComputerName $server
        if ($error.Count -gt 0)
        {
            "Error: Add-VMHardDiskDrive failed to add drive on ${controllerType} ${controllerID} ${Lun}s"
            $error[0].Exception
            return $retVal
        }

        "Success"
        $retVal = $True
    }
    
    return $retVal
}



############################################################################
#
# Main entry point for script
#
############################################################################

$retVal = $true

"AddMultiple4kVHDX_IDE0.ps1"
"  vmName     : $vmName"
"  hvServer   : $hvServer"
"  testParams : $testParams"

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

if ($testParams -eq $null -or $testParams.Length -lt 3)
{
    "Error: No testParams provided"
    "AddHardDisk.ps1 requires test params"
    return $False
}

#
# Make sure we have access to the Microsoft HyperV snapin
#

$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2Sp1\Hyperv.psd1 
}

#
# Transfer the boot disk from IDE0,0 location to IDE1,0 location.
#

$a = Get-VMHardDiskDrive -VMName $vmName -ComputerName $hvServer -ControllerType IDE -ControllerNumber 0   -ControllerLocation 0 

$b = $a.Path

Remove-VMHardDiskDrive -VMName $vmName -ComputerName $hvServer -ControllerType IDE -ControllerNumber 0 -ControllerLocation 0  -WarningAction Ignore
if ( $? -eq $False)
{
    Write-Output "Error while removing the boot disk from IDE0,0"
    return $retVal           
}

Add-VMHardDiskDrive  -VMName $vmName -ComputerName $hvServer -ControllerType IDE -ControllerNumber 1 -ControllerLocation 0 -Path $b -WarningAction Ignore 
if ($? -eq $False)
{
    Write-Output "Error while attaching the boot disk to IDE 1,0"
    return $retVal           
}


#
# Parse the testParams string
#
$params = $testParams.Split(';')
foreach ($p in $params)
{
    if ($p.Trim().Length -eq 0)
    {
        continue
    }

    $temp = $p.Trim().Split('=')
    
    if ($temp.Length -ne 2)
    {
	    "Warn : test parameter '$p' is being ignored because it appears to be malformed"
        continue
    }
    
    $controllerType = $temp[0].Trim()
    if (@("IDE") -notcontains $controllerType)
    {
        # Not a test parameter we are concerned with
        continue
    }
    
    $diskArgs = $temp[1].Trim().Split(',')
    
    if ($diskArgs.Length -lt 3 -or $diskArgs.Length -gt 4)
    {
        "Error: Incorrect number of arguments: $p"
        $retVal = $false
        continue
    }
    
    $controllerID = $diskArgs[0].Trim()
    $lun = $diskArgs[1].Trim()
    $vhdType = $diskArgs[2].Trim()
    $sectorSize = $diskArgs[3].Trim()
    if ($sectorSize -ne "4096" -and $sectorSize -ne "512")
    {
        "Error: Invalid sector size: ${sectorSize}"
        return $False
    }
    
    if (@("Fixed", "Dynamic", "PassThrough") -notcontains $vhdType)
    {
        "Error: Unknown disk type: $p"
        $retVal = $false
        continue
    }
    
    if ($vhdType -eq "PassThrough")
    {
        "Pass through disk not supported"
        $retVal = $false
        continue
    }
    else # Must be Fixed or Dynamic
    {
        "CreateHardDrive $vmName $hvServer $controllerID $Lun $vhdType $sectorSize"
        $sts = CreateHardDrive -vmName $vmName -server $hvServer -ControllerID $controllerID -Lun $Lun -vhdType $vhdType -sectorSize $sectorSize
        if (-not $sts[$sts.Length-1])
        {
            write-output "Failed to create hard drive"
            $sts
            $retVal = $false
            continue
        }
    }
}

return $true
