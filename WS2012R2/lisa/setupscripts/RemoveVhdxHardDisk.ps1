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
    This cleanup script, which runs after the VM is shutdown, will remove VHDx Hard Driver from VM.

.Description
   
#   This is a cleanup script that will run after the VM shuts down.
#   This script will delete the hard drive, and if no other drives
#   are attached to the controller, delete the controller.
#
#   Note: The controller will not be removed if it is an IDE.
#         IDE Lun 0 will not be removed.
#
#
#   An actual testparams definition may look like the following
#
#     <testParams>
#         <param>SCSI=0,0,Fixed</param>
#         <param>IDE=0,1,Dynamic</param>
#     <testParams>
#
#   The above example will be parsed into the following string by the
#   ICA scripts and passed to the cleanup script:
#
#       "SCSI=0,0,Fixed;IDE=0,1,Dynamic"
#
#   Cleanup scripts need to parse the testParam string to find any
#   parameters it needs.
#
#   All setup and cleanup scripts must return a boolean ($true or $false)
#   to indicate if the script completed successfully or not.

   Where
      ControllerType   = The type of disk controller.  IDE or SCSI
      Controller Index = The index of the controller, 0 based.
                         Note: IDE can be 0 - 1, SCSI can be 0 - 3
      Lun or Port      = The IDE port number of SCSI Lun number
      Vhd Type         = Type of VHD to use.
                         Valid VHD types are:
                             Dynamic
                             Fixed
                             Diff (Differencing)
   The following are some examples

   SCSI=0,0,Dynamic,4096 : Add a hard drive on SCSI controller 0, Lun 0, vhd type of Dynamic disk with logical sector size of 4096
   IDE=1,1,Fixed,4096  : Add a hard drive on IDE controller 1, IDE port 1, vhd type of Fixed disk with logical sector size of 4096
   
   A typical XML definition for this test case would look similar
   to the following:
     <test>
          <testName>VHDx_4k_IDE1_Dynamic</testName>         
          <setupScript>setupscripts\AddVhdxHardDisk.ps1</setupScript>
          <cleanupScript>setupscripts\RemoveVhdxHardDisk.ps1</cleanupScript>
          <testScript>STOR_Lis_Disk.sh</testScript>
          <files>remote-scripts/ica/LIS_Storage_Disk.sh</files>
          <timeout>18000</timeout>
          <testparams>
              <param>IDE=1,1,Dynamic,4096</param>        
          </testparams>         
      </test>

.Parameter vmName
    Name of the VM to remove disk from .

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\RemoveVhdxHardDisk -vmName sles11sp3x64 -hvServer localhost -testParams "SCSI=0,0,Dynamic,4096;sshkey=rhel5_id_rsa.ppk;ipv4=10.200.50.192;RootDir=" 

.Link
    None.
#>
############################################################################
#
# RemoveVhdxHardDisk.ps1
#
#
############################################################################

param([string] $vmName, [string] $hvServer, [string] $testParams)


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

    write-output "DeleteHardDrive($vmName, $hvServer, $controllertype, $arguments)"

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
    if ($fields.Length -ne 4)
    {
        write-output "Error - Incorrect number of arguments: $arguments"
        write-output "        args = ControllerID,Lun,vhdtype"
        return $false
    }

    #
    # Set and validate the controller ID and disk LUN
    #
    $controllerID = $fields[0].Trim()
    $lun = $fields[1].Trim()

    if ($scsi)
    {
        # Hyper-V only allows 4 SCSI controllers
        if ($controllerID -lt 0 -or $controllerID -gt 3)
        {
            write-output "Error - bad SCSI controllerID: $controllerID"
            return $false
        }

        # We will limit SCSI LUNs to 4 (0-3)
        if ($lun -lt 0 -or $lun -gt 4)
        {
            write-output "Error - bad SCSI Lun: $Lun"
            return $false
        }
    }
    elseif ($ide)
    {
        # Hyper-V creates 2 IDE controllers and we cannot add any more
        if ($controllerID -lt 0 -or $controllerID -gt 1)
        {
            write-output "Error - bad IDE controller ID: $controllerID"
            return $false
        }

        if ($lun -lt 0 -or $lun -gt 1)
        {
            write-output "Error - bad IDE Lun: $Lun"
            return $false
        }

        # Make sure we are not deleting IDE 0 0, or IDE 1,0
        if ( $Lun -eq 0)
        {
            write-output "Error - Cannot delete IDE 0,0 or IDE 1,0"
            return $false
        }
    }
    else
    {
        write-output "Error - undefined controller type"
        return $retVal
    }

    #
    # Delete the drive if it exists
    #

    $controller = $null
    $drive = $null

    if($ide)
    {
        $controller = Get-VMIdeController -VMName $vmName -ComputerName $hvServer -ControllerNumber $controllerID
    }
    if($scsi)
    {
        write-host "INFO : Get-VMScsiController -VMName $vmName -ComputerName $hvServer -ControllerNumber $controllerID"
        $controller = Get-VMScsiController -VMName $vmName -ComputerName $hvServer -ControllerNumber $controllerID
    }
    
    if ($controller)
    {
        $drive = Get-VMHardDiskDrive $controller -ControllerLocation $lun
        if ($drive)
        {
            write-output "Info : Removing $controllerType $controllerID $lun"
            #$sts = Remove-VMHardDiskDrive $vmName $controllerID -ControllerLocation $lun -ComputerName $hvServer
            $sts = Remove-VMHardDiskDrive $drive
        }
        else
        {
            write-output "Warn : Drive $controllerType $controllerID,$Lun does not exist"
        }
    }
    else
    {
        write-output "Warn : the controller $controllerType $controllerID does not exist"
    }
    
    $retVal = $True
    return $retVal
}

############################################################################
#
# Main entry point for script
#
############################################################################

$retVal = $false

#
# Check input arguments
#
if ($vmName -eq $null -or $vmName.Length -eq 0)
{
    "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null -or $hvServer.Length -eq 0)
{
    "Error: hvServer is null"
    return $retVal
}

if ($testParams -eq $null -or $testParams.Length -lt 13)
{
    #
    # The minimum length testParams string is "IDE=1,1,Fixed"
    #
    "Error: No testParams provided"
    "       The script $MyInvocation.InvocationName requires test parameters"
    return $retVal
}

#
# Make sure we have access to the Microsoft Hyper-V snapin
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
    return $Falses
}

#
# Parse the testParams string
# We expect a parameter string similar to: "ide=1,1,dynamic;scsi=0,0,fixed"
#
# Create an array of string, each element is separated by the ;
#
$params = $testParams.Split(';')
foreach ($p in $params)
{
    if ($p.Trim().Length -eq 0)
    { continue }

    $fields = $p.Split('=')
    
    if ($fields.Length -ne 2)
    {
        "Error: bad test parameter: $p"
        $retVal = $false
        continue
    }
    
    $controllerType = $fields[0].Trim().ToLower()
    if ($controllertype -ne "scsi" -and $controllerType -ne "ide")
    {
        # Just ignore the parameter
        continue
    }
    
    "DeleteHardDrive $vmName $hvServer $controllerType $($fields[1])"
    $sts = DeleteHardDrive -vmName $vmName -hvServer $hvServer -controllerType $controllertype -arguments $fields[1]
    if ($sts[$sts.Length-1] -eq $false)
    {
        $retVal = $false
        # displayed captured output from function
        for ($i=0; $i -lt $sts.Length -1; $i++)
        {
            write-output "    " $sts[$i]
        }
    }
    else
    {
        $retVal = $true
    }
}

"RemoveHardDisk returning $retVal"

return $retVal
