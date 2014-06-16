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
    This setup script, that will run before the VM is booted, will Add VHDx Hard Driver to VM.


.Description
   This is a cleanup script that will run after the VM shuts down.
   This script delete the hard drives identified in any ide= or
   scsi= test parameters.


   Note: The controller will not be removed if it is an IDE.
         IDE Lun 0 will not be removed.


   Cleanup scripts are run in a separate PowerShell environment,
   so they do not have access to the environment running the ICA
   scripts.


   The .xml entry for this script could look like either of the
   following:


   <cleanupScript>SetupScripts\RemoveVhdxHardDisk.ps1</cleanupScript>


   The ICA scripts will always pass the vmName, hvServer, and a
   string of testParams from the test definition, separated by
   semicolons. The testParams for this script identify disk
   controllers, hard drives, .vhd types, and optional sector size.
   The testParams have the format of:


      ControllerType=Controller Index, Lun or Port, vhdType [, sector size]


   An actual testparams definition may look like the following


     <testParams>
         <param>SCSI=0,0,Fixed,4096,3GB</param>
         <param>IDE=0,1,Dynamic,512,3GB</param>
     <testParams>


   The above example will be parsed into the following string by the
   ICA scripts and passed to the cleanup script:


       "SCSI=0,0,Fixed,4096;IDE=0,1,Dynamic,512,3GB"


   Cleanup scripts need to parse the testParam string to find any
   parameters it needs.


   All setup and cleanup scripts must return a boolean ($true or $false)
  to indicate if the script completed successfully or not.
#>
############################################################################


param([string] $vmName, [string] $hvServer, [string] $testParams)


function ConvertStringToUInt64([string] $str)
{
    $uint64Size = $null


    #
    # Make sure we received a string to convert
    #
    if (-not $str)
    {
        Write-Error -Message "ConvertStringToUInt64() - input string is null" -Category InvalidArgument -ErrorAction SilentlyContinue
        return $null
    }


    if ($newSize.EndsWith("MB"))
    {
        $num = $newSize.Replace("MB","")
        $uint64Size = ([Convert]::ToUInt64($num)) * 1MB
    }
    elseif ($newSize.EndsWith("GB"))
    {
        $num = $newSize.Replace("GB","")
        $uint64Size = ([Convert]::ToUInt64($num)) * 1GB
    }
    elseif ($newSize.EndsWith("TB"))
    {
        $num = $newSize.Replace("TB","")
        $uint64Size = ([Convert]::ToUInt64($num)) * 1TB
    }
    else
    {
        Write-Error -Message "Invalid newSize parameter: ${str}" -Category InvalidArgument -ErrorAction SilentlyContinue
        return $null
    }


    return $uint64Size
}


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
# DeleteHardDrive
#
# Description
#   Delete the specified hard drive.  If there are no other hard drives
#   attached to the controller, remove the controller if it is a SCSI.
#
#   Never remove the IDE controllers, or the IDE port 0 devices.
#   By default IDE 0, port 0 is the system drive
#              IDE 1, port 0 is the DVD
#
############################################################################
function DeleteHardDrive([string] $vmName, [string] $hvServer, [string]$controllerType, [string] $arguments)
{
    $retVal = $false


    "DeleteHardDrive( $vmName, $hvServer, $controllertype, $arguments)"


    $scsi = $false
    $ide = $true


    if ($controllerType -eq "scsi")
    {
        $scsi = $true
        $ide = $false
    }
    
    #
    # Extract the parameters in the arguments variable
    #
    $controllerID = -1
    $lun = -1
    
    $fields = $arguments.Trim().Split(',')
    if ($fields.Length -lt 4 -or $fields.Length -gt 5)
    {
        "Error - Incorrect number of arguments: $arguments"
        "        args = ControllerID,Lun,vhdtype[,sectorSize]"
        return $false
    }


    #
    # Set and validate the controller ID and disk LUN
    #
    $controllerID = $fields[0].Trim()
    $lun = $fields[1].Trim()


    if ($scsi)
    {
        # Win 8 supports 16 SCSI controllers
        if ($controllerID -lt 0 -or $controllerID -gt 15)
        {
            "Error - Invalid SCSI controllerID: $controllerID"
            return $false
        }
        
        # Win 8 supports 64
        if ($lun -lt 0 -or $lun -gt 63)
        {
            "Error - Invalid SCSI Lun: $Lun"
            return $false
        }
    }
    elseif ($ide)
    {
        # Hyper-V creates 2 IDE controllers and we cannot add any more
        if ($controllerID -lt 0 -or $controllerID -gt 1)
        {
            "Error - Invalid IDE controller ID: $controllerID"
            return $false
        }
        
        if ($lun -lt 0 -or $lun -gt 1)
        {
            "Error - Invalid IDE Lun: $Lun"
            return $false
        }
        
        # Make sure we are not deleting IDE 0 0, or IDE 1,0
        if ( $Lun -eq 0)
        {
            "Error - Cannot delete IDE 0,0 or IDE 1,0"
            return $false
        }
    }
    else
    {
        "Error - undefined controller type"
        return $retVal
    }
    
    #
    # Delete the drive and vhdx file
    #
    try
    {
        $drive = Get-VMHardDiskDrive -VMName $vmName -ControllerType $controllerType -ControllerNumber $controllerID -ControllerLocation $Lun -ComputerName $hvServer
        if ($drive)
        {
            #
            # Collect file info on the .vhdx file, but remove the drive first
            #
            $fileInfo = GetRemoteFileInfo $drive.Path $hvServer


            "Info : Removing drive $controllerType $controllerID $lun"
            Remove-VMHardDiskDrive -vmName $vmName -ControllerType $controllerType -ControllerNumber $controllerID -ControllerLocation $Lun -ComputerName $hvServer


            if ($fileInfo)
            {
                "Info : Deleting file $($fileInfo.Name)"
                $sts = $fileInfo.Delete()
            }
        }
        else
        {
            "Warn : Drive $controllerType $controllerID,$Lun does not exist"
        }
    }
    catch
    {
        "Error: unable to remove the drive"
        "       $($_.Exception)"
    }


    #
    # The cleanup script does not fail
    #
    $retVal = $True
    return $retVal
}




############################################################################
#
# Main entry point for script
#
############################################################################


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


if ($testParams -eq $null -or $testParams.Length -lt 13)
{
    #
    # The minimum length testParams string is "IDE=1,1,Fixed"
    #
    "Error: No testParams provided"
    "       The script $MyInvocation.InvocationName requires test parameters"
    return $False
}


#
# Make sure we have access to the Microsoft PowerShell Hyper-V snapin
#
$hvModule = Get-Module Hyper-V
if ($hvModule -eq $NULL)
{
    import-module Hyper-V
    $hvModule = Get-Module Hyper-V
}


if ($hvModule.companyName -ne "Microsoft Corporation")
{
    "Error: The Microsoft Hyper-V PowerShell module is not available"
    return $False
}


#
# Parse the testParams string
# We expect a parameter string similar to: "ide=1,1,dynamic;scsi=0,0,fixed"
#
# Create an array of string, each element is separated by the ;
#
$retVal = $True


$params = $testParams.Split(';')
foreach ($p in $params)
{
    if ($p.Trim().Length -eq 0)
    { continue }


    $fields = $p.Split('=')
    
    if ($fields.Length -ne 2)
    {
        "Error: Invalid test parameter: $p"
        $retVal = $False
        continue
    }
    
    $controllerType = $fields[0].Trim().ToLower()
    if ($controllertype -ne "scsi" -and $controllerType -ne "ide")
    {
        # It's a testParam we don't care about - just ignore the parameter
        continue
    }
    
    "DeleteHardDrive $vmName $hvServer $controllerType $($fields[1])"
    $sts = DeleteHardDrive -vmName $vmName -hvServer $hvServer -controllerType $controllertype -arguments $fields[1]
    if ($sts[$sts.Length-1] -eq $False)
    {
        $retVal = $False
    }


    #
    # displayed captured output from DeleteHardDrive() function
    #
    for ($i=0; $i -lt $sts.Length -1; $i++)
    {
        "    $($sts[$i])"
    }
}


"RemoveVhdxHardDisk returning $retVal"


return $retVal
