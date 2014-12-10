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
# RemoveMultiple4kVHDX_IDE0.ps1
#
# Description:
#   This is a cleanup script that will run after the VM shuts down.
#   This script will delete the 4k Sector VHDX drives connected to IDE0 controller 
#   and it will move the boot disk from IDE1,0 to IDE0,0 location
#
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
#   #
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

    $ide = $true

    #
    # Extract the parameters in the arguments variable
    #
    $controllerID = -1
    $lun = -1

    $fields = $arguments.Trim().Split(',')
    if ($fields.Length -ne 4)
    {
        write-output "Error - Incorrect number of arguments: $arguments"
        write-output "args = ControllerID,Lun,vhdtype"
        return $false
    }

    #
    # Set and validate the controller ID and disk LUN
    #
    $controllerID = $fields[0].Trim()
    $lun = $fields[1].Trim()

    # Hyper-V creates 2 IDE controllers and we cannot add any more
    if ($controllertype -eq "IDE")
    {
        if ($controllerID -lt 0 -or $controllerID -gt 1)
        {
            write-output "Error - Invalid IDE controller ID: $controllerID"
            return $false
        }

        if ($lun -lt 0 -or $lun -gt 1)
        {
            write-output "Error - Invalid IDE Lun: $Lun"
            return $false
        }

        # Make sure we are not deleting boot disk present at location IDE 1,0
        if ( $controllerID -eq 1 -and $Lun -eq 0)
        {
            write-output "Error - Cannot delete IDE 1,0 - boot disk"
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

    $controller = Get-VMDiskController $vmName -server $hvServer -IDE:$ide -controllerID $controllerID
    if ($controller.__CLASS -eq 'Msvm_ResourceAllocationSettingData')
    {
        $drive = Get-VMDriveByController $controller -Lun $lun
        if ($drive.__CLASS -eq 'Msvm_ResourceAllocationSettingData')
        {
            write-output "Info : Removing $controllerType $controllerID $lun"
            $sts = Remove-VMDrive $vmName $controllerID $lun -SCSI:$false -server $hvServer
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
    "The script $MyInvocation.InvocationName requires test parameters"
    return $retVal
}

#
# Load the HyperVLib version 2 modules
#
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2Sp1\Hyperv.psd1
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
    {   
        continue
    }

    $fields = $p.Split('=')
    
    if ($fields.Length -ne 2)
    {
        "Error: Invalid test parameter: $p"
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
#
# At the end transfer the boot disk from location IDE1,0 back to IDE0,0 
#
$a = Get-VMHardDiskDrive -VMName $vmName -ComputerName $hvServer -ControllerType IDE -ControllerNumber 1   -ControllerLocation 0 

$b = $a.Path

Remove-VMHardDiskDrive -VMName $vmName -ComputerName $hvServer -ControllerType IDE -ControllerNumber 1 -ControllerLocation 0  -WarningAction Ignore
if ( $? -eq $False)
{
    Write-Output "Error while removing the boot disk from IDE0,0"
    return $retVal           
}

Add-VMHardDiskDrive  -VMName $vmName -ComputerName $hvServer -ControllerType IDE -ControllerNumber 0 -ControllerLocation 0 -Path $b -WarningAction Ignore 
if ($? -eq $False)
{
    Write-Output "Error while attaching the boot disk to IDE 1,0"
    return $retVal           
}


"RemoveHardDisk returning $retVal"

return $retVal
