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
# UnloadSCSIDisks.ps1
#
# Description:
#   This is a cleanup script that will run after the VM shuts down.
#   This script will delete the hard drive, and if no other drives
#   are attached to the controller, delete the controller.
#
#   Note: The controller will not be removed if it is an IDE.
#         IDE Lun 0 will not be removed.
#
#   Cleanup scripts) are run in a separate PowerShell environment,
#   so they do not have access to the environment running the ICA
#   scripts.  Since this script uses the PowerShell Hyper-V library,
#   these modules must be loaded by this startup script.
#
#   The .xml entry for this script could look like either of the
#   following:
#
#   <cleanupScript>SetupScripts\delHardDisk.ps1</cleanupScript>
#
#   The ICA scripts will always pass the vmName, hvServer, and a
#   string of testParams from the test definition, separated by
#   semicolons. The testParams for this script identify disk
#   controllers, hard drives, and .vhd types.  The testParams
#   have the format of:
#
#      ControllerType=Controller Index, Lun or Port, vhdType
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
#
#   Modified for removing disk from IDE 1,0 drive(Default DVD drive)
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
function DeleteHardDrive([string] $vmName, [string] $hvServer, [int]$controllerID, [int] $lun)
{
    $retVal = $false
    
    write-output "DeleteHardDrive( $vmName, $hvServer, $controllerID, $lun)"
    
    # Hyper-V only allows 4 SCSI controllers
    if ($controllerID -lt 0 -or $controllerID -gt 3)
    {
       write-output "Error - Invalid SCSI controllerID: $controllerID"
       return $retVal
    }
        
    # Max limit for SCSI LUNs is 64 (0-63)
    if ($lun -lt 0 -or $lun -gt 63)
    {
       write-output "Error - Invalid SCSI Lun: $Lun"
       return $retVal
    }
   
    
    #
    # Delete the drive if it exists
    #
    
    $controller = $null
    $drive = $null
    
    $controller = Get-VMDiskController $vmName -server $hvServer -SCSI -controllerID $controllerID
    if ($controller.__CLASS -eq 'Msvm_ResourceAllocationSettingData')
    {
        $drive = Get-VMDriveByController $controller -Lun $lun
        if ($drive.__CLASS -eq 'Msvm_ResourceAllocationSettingData')
        {
           write-output "Info : Removing SCSI drive $controllerID $lun"
           $sts = Remove-VMDrive -VM $vmName -Server $hvServer -SCSI -ControllerID $controllerID -LUN $lun
           if ($sts -eq $null)
           {
              write-output "Error: deleting the SCSI drive: ${controllerID} ${lun}"
              return $retVal
           } 
        }
        else
        {
            write-output "Warn : SCSI Drive $controllerID,$Lun does not exist"
        }
    }
    else
    {
        write-output "Warn : the SCSI controller $controllerID does not exist"
    }

    #
    # Delete the SCSI controller if no other drives are attached
    #
    if ($controller)
    {
        #
        # Update the controller object since we may have removed a drive
        #
        $controller = Get-VMDiskController $vmName -server $hvServer -SCSI -controllerID $controllerID
        
        $drives = Get-VMDriveByController $controller
        if ($drives)
        {
            write-output "Additional drives are still attached"
        }
        else
        {
            write-output "Info : Removing SCSI controller $controllerID"
            $sts = Remove-VMSCSIController -vm $vmName -server $hvServer -controllerID $controllerID -force
            if ($sts -eq $null)
            {
              write-output "Error: deleting the SCSI Controller: ${controllerID}"
              return $retVal
            } 
        }
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
# Load the HyperVLib version 2 modules
#
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2SP1\Hyperv.psd1
}

#
# Parse the testParams string
#

$params = $testParams.Split(';')
foreach ($p in $params)
{
    if ($p.Trim().Length -eq 0)
    { continue }

    $fields = $p.Split('=')
    
    if ($fields.Length -ne 2)
    {
        "Error: Invalid test parameter: $p"
        $retVal = $false
        continue
    }
     if ($fields[0].Trim() -eq "MAX_CONTROLLERS")
    {
        #$switchName = $tokens[1].Trim().ToLower()
        $MaxControllers = $fields[1].Trim().ToLower()
    
    }
     if ($fields[0].Trim() -eq "DISKS_PER_CONTROLLER")
    {
        #$switchName = $tokens[1].Trim().ToLower()
        $DisksperController = $fields[1].Trim().ToLower()
    
    }
}    

#
# Delete the SCSI Vm drivers and SCSI controllers attached.
#

$controllerID = 0
while($controllerID -lt $MaxControllers)
{
   $lun = 0
   while($lun -lt $DisksperController)
   {
     
      "DeleteSCSIDrive ControllerID: ${controllerID}, LUN: ${lun} "
      $sts = DeleteHardDrive -vmName $vmName -hvServer $hvServer -controllerID $controllerID -lun $lun
      if (! $sts[$sts.Length-1])
      {
          write-output "Failed to delete SCSI drive"
          $sts
          return $false
         
      }
      $lun++
   }
   $controllerID++
}
#
# Delete the temp directory and Virtual disk files created.
#
$defaultVhdPath = Get-VhdDefaultPath -server $hvServer
if (-not $defaultVhdPath.EndsWith("\"))
{
    $defaultVhdPath += "\"
}
$vhdPath = $defaultVhdPath + "${vmName}_temp\"

del -Recurse -Path $vhdPath
if($? -eq $false)
{
  Write-Output "Error while deleting the VHD files and the storage directory"
  return $retVal
}

$retVal = $true
"UnloadSCSIDisks returning $retVal"
return $retVal
