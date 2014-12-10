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
    This setup script is for testing the load on SCSI contoller. it runs before the VM is booted, it will
    add 64 SCSI disk to each of the 4 SCSI controllers. 

    Setup and cleanup scripts run in a separate PowerShell environment,
    and do not have access to the environment running the ICA scripts.
    Since this script uses the PowerShell Hyper-V library, these modules
    must be loaded.

    The .xml entry for a startup script would look like:

        <setupScript>SetupScripts\AddHardDisk.ps1</setupScript>

  The ICA always pass the vmName, hvServer, and a string of testParams
  to statup (and cleanup) scripts.  The testParams for this script have
  the format of:

     ControllerType=Controller Index, Lun or Port, vhd type

  Where
     Lun or Port      = The IDE port number of SCSI Lun number
     Vhd Type         = Type of VHD to use.
                        Valid VHD types are:
                            Dynamic
                            Fixed
                            Diff (Differencing)
    VHD Format - is VHD/VHDX format

  #   A sample testParams section from a .xml file might look like:
     
    <testParams>
        <param>VHD_FORMAT=VHD,512</param>
        <param>VHD_TYPE=Dynamic</param>
    <testParams>

  The above example will be parsed into the following string by the ICA scripts and passed
  to the setup script:

      
  The setup (and cleanup) scripts parse the testParam string to find any parameters
  it needs to perform its task.

  All setup and cleanup scripts must return a boolean ($true or $false)
  to indicate if the script completed successfully or not.

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$global:MinDiskSize = 1GB


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
# CreateController
#
# Description
#     Create a SCSI controller if one with the ControllerID does not
#     already exist.
#
############################################################################
function CreateController([string] $vmName, [string] $server, [string] $controllerID)
{
    #
    # Hyper-V only allows 4 SCSI controllers - make sure the Controller ID is valid
    #
    if ($ControllerID -lt 0 -or $controllerID -gt 3)
    {
        write-output "    Error: Invalid SCSI controller ID: $controllerID"
        return $false
    }

    #
    # Check if the controller already exists
    # Note: If you specify a specific ControllerID, Get-VMDiskController always returns
    #       the last SCSI controller if there is one or more SCSI controllers on the VM.
    #       To determine if the controller needs to be created, count the number of 
    #       SCSI controllers.
    #
    $maxControllerID = 0
    $createController = $true
    $controllers = Get-VMDiskController -vm $vmName -ControllerID "*" -server $server -SCSI
    if ($controllers -ne $null)
    {
        if ($controllers -is [array])
        {
            $maxControllerID = $controllers.Length
        }
        else
        {
            $maxControllerID = 1
        }
        
        if ($controllerID -lt $maxControllerID)
        {
            "    Info : Controller exists - controller not created"
            $createController = $false
        }
    }
    
    #
    # If needed, create the controller
    #
    if ($createController)
    {
        $ctrl = Add-VMSCSIController -vm $vmName -name "SCSI Controller $ControllerID" -server $server -force
        if ($ctrl -eq $null -or $ctrl.__CLASS -ne 'Msvm_ResourceAllocationSettingData')
        {
            "    Error: Add-VMSCSIController failed to add 'SCSI Controller $ControllerID'"
            return $retVal
        }
        "    Controller successfully added"
    }
}

############################################################################
#
# CreateHardDrive
#
# Description
#     If the -SCSI options is false, an IDE drive is created
#
############################################################################
function CreateHardDrive( [string] $vmName, [string] $server, [int] $ControllerID, [int] $Lun, [string] $vhdType, [string] $vhdFormat, [string] $sectorSize)
{
    $retVal = $false
        
    "Enter CreateHardDrive $vmName $server $controllerID $lun $vhdType $vhdFormat $sectorSize"
    
    if ($ControllerID -lt 0 -or $ControllerID -gt 3)
    {
        "Error: CreateHardDrive was passed an invalid SCSI Controller ID: $ControllerID"
         return $false
    }
        
    #
    # Create the SCSI controller if needed
    #
    $sts = CreateController $vmName $server $controllerID
    if (-not $sts[$sts.Length-1])
    {
        "Error: Unable to create SCSI controller $controllerID"
         return $false
    }

       
    #
    # If the hard drive exists, complain. Otherwise, add it
    #
    $drives = Get-VMDiskController -vm $vmName -ControllerID $ControllerID -server $server -SCSI:$true -IDE:$false | Get-VMDriveByController -Lun $Lun
    if ($drives)
    {
        write-output "Error: drive $controllerType $controllerID $Lun already exists"
        return $false
    }
    else <#Create the disks #>
    {
       #
       # Check the VHD storage path.
       #
       $defaultVhdPath = Get-VhdDefaultPath -server $server
       if (-not $defaultVhdPath.EndsWith("\"))
       {
         $defaultVhdPath += "\"
       }
       $vhdPath = $defaultVhdPath + "${vmName}_temp\"

       if ($vhdFormat -eq "vhd") <#code to create & attach VHDs to SCSI controller#> 
       {
         $newDrive = Add-VMDrive -vm $vmName -ControllerID $controllerID -Lun $Lun -scsi:$true -server $server
         if ($newDrive -eq $null -or $newDrive.__CLASS -ne 'Msvm_ResourceAllocationSettingData')
         {
           write-output "Error: Add-VMDrive failed to add $controllerType drive on $controllerID $Lun"
           return $retVal
         }
        
         #
         # Create the .vhd file if it does not already exist
         #
         $vhdName = $VhdPath + $vmName + "-" + $controllerType + "-" + $controllerID + "-" + $Lun + "-" + $vhdType + ".vhd"
         
         $fileInfo = GetRemoteFileInfo -filename $vhdName -server $hvServer
         write-host "File exist return code: ${fileInfo}"
         if (-not $fileInfo)
         {
           $newVhd = $null
           switch ($vhdType)
           {
            "Dynamic"
                {
                   $newVhd = New-Vhd -vhdPaths $vhdName -server $server -force -wait
                }
            "Fixed"
                {
                    $newVhd = New-Vhd -vhdPaths $vhdName -size $global:MinDiskSize -server $server -fixed -force -wait
                }
            "Diff"
                {
                    $parentVhdName = $defaultVhdPath + "icaDiffParent.vhd"
                    $parentInfo = GetRemoteFileInfo -filename $parentVhdName -server $hvServer
                    if (-not $parentInfo)
                    {
                       Write-Output "Error: parent VHD does not exist: ${parentVhdName}"
                       return $retVal
                    }
                    $newVhd = New-Vhd -vhdPaths $vhdName -parentVHD $parentVhdName -server $server -Force -Wait
                }
            default
                {
                    Write-Output "Error: unknow vhd type of ${vhdType}"
                    return $retVal
                }
           }
           if ($newVhd -eq $null)
           {
              write-output "Error: New-VHD failed to create the new .vhd file: $($vhdName)"
              return $retVal
           }
         }
    
         #
         # Attach the .vhd file to the new drive
         #
         $disk = Add-VMDisk -vm $vmName -ControllerID $controllerID -Lun $Lun -Path $vhdName -SCSI:$true -server $server
         if ($disk -eq $null -or $disk.__CLASS -ne 'Msvm_ResourceAllocationSettingData')
         {
           write-output "Error: AddVMDisk failed to add $($vhdName) to $controllerType $controllerID $Lun $vhdType"
           return $retVal
         }
         else
         {
            write-output "Success"
            $retVal = $true
         }
    
      }
       else <#code to create & attach VHDX files to SCSI controller #>
       {
              
         #
         # Create the .vhdx file if it does not already exist
         #
         $vhdName = $VhdPath + $vmName + "-" + $controllerType + "-" + $controllerID + "-" + $Lun + "-" + $vhdType + "-" + $sectorSize + ".vhdx"
         
         $fileInfo = GetRemoteFileInfo -filename $vhdName -server $hvServer
         write-host "File exist return code: ${fileInfo}"
         if (-not $fileInfo)
         {
           $newVhd = $null
           switch ($vhdType)
           {
            "Dynamic"
                {
                   $newVhd = hyper-v\New-Vhd -Path $vhdName -size $global:MinDiskSize -Dynamic:($vhdType -eq "Dynamic") -LogicalSectorSize ([int] $sectorSize)  -ComputerName $server
                   
                }
            "Fixed"
                {
                   $newVhd = hyper-v\New-Vhd -Path $vhdName -size $global:MinDiskSize -ComputerName $server -LogicalSectorSizeBytes ([int] $sectorSize) -Fixed:($vhdType -eq "Fixed") 
                }
            "Diff"
                {
                  if ([int] $sectorSize = 512)
                  {
                    $parentVhdName = $defaultVhdPath + "icadiffvhdx512.vhdx"
                  }
                  else
                  {
                    $parentVhdName = $defaultVhdPath + "icaDiffvhdx4k.vhdx"
                  } 
                  $parentInfo = GetRemoteFileInfo -filename $parentVhdName -server $hvServer
                  if (-not $parentInfo)
                  {
                     Write-Output "Error: parent VHD does not exist: ${parentVhdName}"
                     return $retVal
                  }
                  $newVhd = hyper-v\New-Vhd -Path $vhdName -ParentPath $parentVhdName -ComputerName $server -Differencing 
                }
            default
                {
                    Write-Output "Error: unknow vhd type of ${vhdType}"
                    return $retVal
                }
           }
           if ($newVhd -eq $null)
           {
              write-output "Error: New-VHD failed to create the new .vhd file: $($vhdName)"
              return $retVal
           }
         }
    
         #
         # Attach the .vhd file to the new drive
         #
         $error.Clear()
         hyper-v\Add-VMHardDiskDrive -VMName $vmName -Path $vhdName -ControllerType SCSI -ControllerLocation $Lun -ControllerNumber $controllerID  -ComputerName $server
         if ($error.Count -gt 0)
         {
           "Error: Add-VMHardDiskDrive failed to add drive on ${controllerType} ${controllerID} ${Lun}"
            $error[0].Exception
            return $retVal
         }
         else
         {
          write-output "Success"
          $retVal = $true
         }
    
   }
       return $retVal
    }
}



############################################################################
#
# Main entry point for script
#
############################################################################

$retVal = $false

"Load256SCSIDisks.ps1 -vmName $vmName -hvServer $hvServer -testParams $testParams"

#
# Check input arguments
#
if ($vmName -eq $null -or $vmName.Length -eq 0)
{
    "Error: VM name is null"
    return $false
}

if ($hvServer -eq $null -or $hvServer.Length -eq 0)
{
    "Error: hvServer is null"
    return $false
}

if ($testParams -eq $null -or $testParams.Length -lt 3)
{
    "Error: No testParams provided"
    "       AddHardDisk.ps1 requires test params"
    return $false
}

#
# Load the HyperVLib version 2 modules

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
    {
        continue
    }

    $temp = $p.Trim().Split('=')
    
    if ($temp.Length -ne 2)
    {
	"Warn : test parameter '$p' is being ignored because it appears to be malformed"
     continue
    }
    if ($temp[0].Trim() -eq "VHD_FORMAT")
    {
        #$switchName = $tokens[1].Trim().ToLower()
        $diskArgs = $temp[1].Trim().Split(',')
        if ($diskArgs.Length -lt 2 -or $diskArgs.Length -gt 2)
        {
          "Error: Incorrect number of arguments: $diskArgs"
          continue
        }
        $vhdFormat = $diskArgs[0].Trim().ToLower()
        $sectorSize = $diskArgs[1].Trim()

    }
     if ($temp[0].Trim() -eq "VHD_TYPE")
    {
        #$switchName = $tokens[1].Trim().ToLower()
        $vhdType = $temp[1].Trim().ToLower()
    
    }
     if ($temp[0].Trim() -eq "MAX_CONTROLLERS")
    {
        #$switchName = $tokens[1].Trim().ToLower()
        $MaxControllers = $temp[1].Trim().ToLower()
    
    }
     if ($temp[0].Trim() -eq "DISKS_PER_CONTROLLER")
    {
        #$switchName = $tokens[1].Trim().ToLower()
        $DisksperController = $temp[1].Trim().ToLower()
    
    }
}

#  
# Verify that the correct parameters are passed  
#
     
if (@("Fixed", "Dynamic", "Diff") -notcontains $vhdType)
{
    "Error: Unknown disk type: $p"
    return $retVal
}
if (@("VHD", "VHDX") -notcontains $vhdFormat)
{
    "Error: Unknown disk format: $p"
    return $retVal
}
if (@("512", "4096") -notcontains $sectorSize)
{
    "Error: Unsupported logical sector size: $p"
    return $retVal
}

if ($MaxControllers -gt 4)
{
    "Error: Max number of controllers supported is only 4"
    return $retVal
}
if ($DisksperController -gt 64)
{
    "Error: Max number of disks that can be attached to one controller is: 64"
    return $retVal
}

#  
# Create SCSI controllers and attach disks to each of them.  
# 
    
$controllerID = 0
while($controllerID -lt $MaxControllers)
{
  $lun = 0
  while($lun -lt $DisksperController)
  {
      "CreateHardDrive $vmName $hvServer $scsi $controllerID $Lun $vhdType"
      $sts = CreateHardDrive -vmName $vmName -server $hvServer -ControllerID $controllerID -Lun $Lun -vhdType $vhdType -vhdFormat $vhdFormat -sectorSize $sectorSize
      if (! $sts[$sts.Length-1])
      {
         write-output "Failed to create hard drive"
         $sts
         return $false
        
      }
      $lun++

  }
  $controllerID++
}
"Completed adding disks to SCSI Controllers"
$retVal = $true
return $retVal
