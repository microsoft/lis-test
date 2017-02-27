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
     This is a setup script that will run before the VM is booted.
     The script will create a .vhdx file, and mount it to the
     specified hard drive.  If the hard drive does not exist, it
     will be created.

     The .xml entry to specify this startup script would be:

         <setupScript>SetupScripts\AddHardDisk.ps1</setupScript>

   The  scripts will always pass the vmName, hvServer, and a
   string of testParams from the test definition separated by
   semicolons. The testParams for this script identify disk
   controllers, hard drives, .vhd type, and sector size.  The
   testParamss have the format of:

      ControllerType=Controller Index, Lun or Port, vhd type, sector size

   The following are some examples:
   SCSI=0,0,Dynamic,4096 : Add SCSI Controller 0, hard drive on Lun 0, .vhd type Dynamic, sector size of 4096
   SCSI=1,0,Fixed,512    : Add SCSI Controller 1, hard drive on Lun 0, .vhd type Fixed, sector size of 512 bytes
   IDE=0,1,Dynamic,512   : Add IDE hard drive on IDE 0, port 1, .vhd type Fixed, sector size of 512 bytes
   IDE=1,1,Fixed,4096    : Add IDE hard drive on IDE 1, port 1, .vhd type Fixed, sector size of 4096 bytes

   The following testParams

     <testParams>
         <param>SCSI=0,0,Dynamic,4096</param>
         <param>IDE=1,1,Fixed,512</param>
     <testParams>

   will be parsed into the following string by the ICA scripts and passed
   to the setup script:

       "SCSI=0,0,Dynamic,4096;IDE=1,1,Fixed,512"

   All setup and cleanup scripts must return a boolean ($true or $false)
   to indicate if the script completed successfully.

   Where
      ControllerType   = The type of disk controller.  IDE or SCSI
      Controller Index = The index of the controller, 0 based.
                         Note: IDE can be 0 - 1, SCSI can be 0 - 3
      Lun or Port      = The IDE port number of SCSI Lun number
      Vhd Type         = Type of VHD to use.
                         Valid VHD types are:
                             Dynamic
                             Fixed

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
    Name of the VM to remove disk from.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\AddVhdxHardDisk -vmName myVM -hvServer localhost -testParams "SCSI=0,0,Dynamic,4096;sshkey=linux_id_rsa.ppk;ipv4=IPaddress;RootDir="

#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$global:MinDiskSize = 1GB
$global:DefaultDynamicSize = 127GB

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
    # Initially, we will limit this to 4 SCSI controllers...
    #
    if ($ControllerID -lt 0 -or $controllerID -gt 3)
    {
        write-output "    Error: bad SCSI controller ID: $controllerID"
        return $False
    }

    #
    # Check if the controller already exists.
    #
    $scsiCtrl = Get-VMScsiController -VMName $vmName -ComputerName $server
    if ($scsiCtrl.Length -1 -ge $controllerID)
    {
        "Info : SCI ontroller already exists"
    }
    else
    {
        $error.Clear()
        Add-VMScsiController -VMName $vmName -ComputerName $server
        if ($error.Count -gt 0)
        {
            "    Error: Add-VMScsiController failed to add 'SCSI Controller $ControllerID'"
            $error[0].Exception
            return $False
        }
        "Info : Controller successfully added"
    }
    return $True
}

function CreateHardDrive( [string] $vmName, [string] $server, [System.Boolean] $SCSI, [int] $ControllerID,
                          [int] $Lun, [string] $vhdType, [string] $sectorSizes, [string] $diskType)
{
    $retVal = $false

    "CreateHardDrive $vmName $server $scsi $controllerID $lun $vhdType"

    #
    # Make sure it's a valid IDE ControllerID.  For IDE, it must 0 or 1.
    # For SCSI it must be 0, 1, 2, or 3
    #
    $controllerType = "IDE"
    if ($SCSI)
    {
        $controllerType = "SCSI"

        if ($ControllerID -lt 0 -or $ControllerID -gt 3)
        {
            "Error: CreateHardDrive was passed an bad SCSI Controller ID: $ControllerID"
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
    }
    else # Make sure the controller ID is valid for IDE
    {
        if ($ControllerID -lt 0 -or $ControllerID -gt 1)
        {
            "Error: CreateHardDrive was passed an invalid IDE Controller ID: $ControllerID"
            return $False
        }
    }

    #
    # If the hard drive already exists, return an error
    #

    $drive = Get-VMHardDiskDrive -VMName $vmName -ControllerNumber $controllerID -ControllerLocation $Lun -ControllerType $controllerType -ComputerName $server
    if ($drive)
    {
        if ( $controllerID -eq 0 -and $Lun -eq 0 )
        {
            write-output "Error: drive $controllerType $controllerID $Lun already exists"
            return $false
        }
        else
        {
            Remove-VMHardDiskDrive $drive
        }
    }

    $dvd = Get-VMDvdDrive -VMName $vmName -ComputerName $hvServer
    if ($dvd)
    {
        Remove-VMDvdDrive $dvd
    }

    #
    # Create the .vhd file if it does not already exist, then create the drive and mount the .vhdx
    #
    $hostInfo = Get-VMHost -ComputerName $server
    if (-not $hostInfo)
    {
        "Error: Unable to collect Hyper-V settings for ${server}"
        return $False
    }

    $defaultVhdPath = $hostInfo.VirtualHardDiskPath
    if (-not $defaultVhdPath.EndsWith("\"))
    {
        $defaultVhdPath += "\"
    }

   $vhdName = $defaultVhdPath + $vmName + "-" + $controllerType + "-" + $controllerID + "-" + $lun + "-" + $vhdType + "." + $diskType.ToLower()

    if(Test-Path $vhdName)
    {
        Remove-Item $vhdName
    }

    $fileInfo = GetRemoteFileInfo -filename $vhdName -server $server
    if (-not $fileInfo)
    {
        $nv = New-Vhd -Path $vhdName -size $global:MinDiskSize -Dynamic:($vhdType -eq "Dynamic") -LogicalSectorSize ([int] $sectorSize)  -ComputerName $server
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

    return $retVal
}


############################################################################
#
# Main entry point for script
#
############################################################################
$retVal = $true

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
    "       AddHardDisk.ps1 requires test params"
    return $False
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

    if ($temp[0].Trim() -eq "diskType")
    {
        $diskType = $temp[1].Trim()
    }

    if (@("IDE", "SCSI") -notcontains $controllerType)
    {
        # Not a test parameter we are concerned with
        continue
    }

    $SCSI = $false
    if ($controllerType -eq "SCSI")
    {
        $SCSI = $true
    }

    $diskArgs = $temp[1].Trim().Split(',')

    if ($diskArgs.Length -lt 3 -or $diskArgs.Length -gt 4)
    {
        "Error: Incorrect number of arguments: $p"
        $retVal = $false
        continue
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
	
    $controllerID = $diskArgs[0].Trim()
    $lun = $diskArgs[1].Trim()
    $vhdType = $diskArgs[2].Trim()

    $sectorSize = 512
    if ($diskArgs.Length -eq 4)
    {
        $sectorSize = $diskArgs[3].Trim()
        if ($sectorSize -ne "4096" -and $sectorSize -ne "512")
        {
            "Error: bad sector size: ${sectorSize}"
            return $False
        }
    }

    if (@("Fixed", "Dynamic") -notcontains $vhdType)
    {
        "Error: Unknown disk type: $p"
        $retVal = $false
        continue
    }

    "CreateHardDrive $vmName $hvServer $scsi $controllerID $Lun $vhdType $sectorSize"
    $sts = CreateHardDrive -vmName $vmName -server $hvServer -SCSI:$SCSI -ControllerID $controllerID -Lun $Lun -vhdType $vhdType -sectorSize $sectorSize -diskType $diskType

    if (-not $sts[$sts.Length-1])
    {
        write-output "Error: Failed to create hard drive!"
        $sts
        $retVal = $false
        continue
    }
}

return $retVal
