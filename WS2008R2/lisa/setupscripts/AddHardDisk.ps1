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
    This setup script, which runs before the VM is booted, will
    add additional hard drives to the specified VM.

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

      SCSI=0,0,Dynamic : Add a hard drive on SCSI controller 0, Lun 0, vhd type of Dynamic
      SCSI=1,0,Fixed   : Add a hard drive on SCSI controller 1, Lun 0, vhd type of Fixed
      IDE=0,1,Dynamic  : Add a hard drive on IDE controller 0, IDE port 1, vhd type of Fixed
      IDE=1,1,Diff     : Add a hard drive on IDE controller 1, IDE port 1, vhd type of Diff

  A sample testParams section from a .xml file might look like:

    <testParams>
        <param>SCSI=0,0,Dynamic</param>
        <param>IDE=1,1,Fixed</param>
    <testParams>

  The above example will be parsed into the following string by the ICA scripts and passed
  to the setup script:

      "SCSI=0,0,Dynamic;IDE=1,1,Fixed"

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

$global:MinDiskSize = "1GB"

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
# GetPhysicalDiskForPassThru
#
# Description
#     
#
############################################################################
function GetPhysicalDiskForPassThru([string] $server, [string] $passDriveNumber)
{
    #
    # Find all the Physical drives that are in use
    #
    $PhysDisksInUse = @()


    $physDrive = $null

    $drives = GWMI Msvm_DiskDrive -namespace root\virtualization -computerName $server
    foreach ($drive in $drives)
    {
        if ($($drive.DriveNumber))
        {
            if ([Convert]::ToUint64($passDriveNumber) -eq $($drive.DriveNumber))
            {
                $physDrive = $drive
                break
            }
        }
    }

    return $physDrive
}

function ConvertStringToUInt64([string] $newSize)
{
    $uint64Size = $null

    #
    # Make sure we received a string to convert
    #
    if (-not $newSize)
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
        Write-Error -Message "Invalid newSize parameter: ${newSize}" -Category InvalidArgument -ErrorAction SilentlyContinue
        return $null
    }


    return $uint64Size
}

############################################################################
#
# CreatePassThruDrive
#
# Description
#     If the -SCSI options is false, an IDE drive is created
#
############################################################################
function CreatePassThruDrive([string] $vmName, [string] $server, [switch] $scsi,
                             [string] $controllerID, [string] $Lun, [string] $passDriveNumber)
{
    $retVal = $false
    
    $ide = $true
    if ($scsi)
    {
        $ide = $false
    }
    
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

    $drives = Get-VMDiskController -vm $vmName -ControllerID $ControllerID -server $server -SCSI:$SCSI -IDE:(-not $SCSI) | Get-VMDriveByController -Lun $Lun
    
    if ($drives)
    {
        "Error: drive $controllerType $controllerID $Lun already exists"
        return $false
    }
    
    #
    # Make sure the drive number exists
    #
    $physDisk = GetPhysicalDiskForPassThru $server $passDriveNumber
    if ($physDisk -ne $null)
    {
        $pt = Add-VMPassThrough -vm $vmName -controllerID $controllerID -Lun $Lun -PhysicalDisk $physDisk `
                                -server $server -SCSI:$scsi -force
        if ($pt)
        {
            $retVal = $true
        }
    }
    else
    {
        "Error: no free physical drives found"
    }
    
    return $retVal
}

############################################################################
#
# CreateHardDrive
#
# Description
#     If the -SCSI options is false, an IDE drive is created
#
############################################################################
function CreateHardDrive( [string] $vmName, [string] $server, [System.Boolean] $SCSI, [int] $ControllerID,
                          [int] $Lun, [string] $vhdType, [String] $newSize)
{
    $retVal = $false

    "Enter CreateHardDrive $vmName $server $scsi $controllerID $lun $vhdType"
    
    $controllerType = "IDE"
    
    #
    # Make sure it's a valid IDE ControllerID.  For IDE, it must 0 or 1.
    # For SCSI it must be 0, 1, 2, or 3
    #
    if ($SCSI)
    {
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

        $controllerType = "SCSI"
    }
    else # Make sure the controller ID is valid for IDE
    {
        if ($ControllerID -lt 0 -or $ControllerID -gt 1)
        {
            "Error: CreateHardDrive was passed an invalid IDE Controller ID: $ControllerID"
            return $false
        }
    }
    
    #
    # If the hard drive exists, complain. Otherwise, add it
    #
    $drives = Get-VMDiskController -vm $vmName -ControllerID $ControllerID -server $server -SCSI:$SCSI -IDE:(-not $SCSI) | Get-VMDriveByController -Lun $Lun
    if ($drives)
    {
        write-output "Error: drive $controllerType $controllerID $Lun already exists"
        return $retVal
    }
    else
    {
        $newDrive = Add-VMDrive -vm $vmName -ControllerID $controllerID -Lun $Lun -scsi:$SCSI -server $server
        if ($newDrive -eq $null -or $newDrive.__CLASS -ne 'Msvm_ResourceAllocationSettingData')
        {
            write-output "Error: Add-VMDrive failed to add $controllerType drive on $controllerID $Lun"
            return $retVal
        }
    }
    
    #
    # Create the .vhd file if it does not already exist
    #
    $defaultVhdPath = Get-VhdDefaultPath -server $server
    if (-not $defaultVhdPath.EndsWith("\"))
    {
        $defaultVhdPath += "\"
    }
    
    $newVHDSize = ConvertStringToUInt64 $newSize
    
     $vhdName = $defaultVhdPath + $vmName + "-" + $controllerType + "-" + $controllerID + "-" + $Lun + "-" + $vhdType + ".vhd"

    if(Test-Path $vhdName)
    {
        Remove-Item $vhdName
    }
    
    $fileInfo = GetRemoteFileInfo -filename $vhdName -server $hvServer
    if (-not $fileInfo)
    {
        $newVhd = $null
        switch ($vhdType)
        {
            "Dynamic"
                {
                    $newVhd = New-Vhd -vhdPaths $vhdName -size $newVHDSize  -server $server -force -wait
                }
            "Fixed"
                {
                    $newVhd = New-Vhd -vhdPaths $vhdName -size $newVHDSize  -server $server -fixed -force -wait
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
        #$nv = New-Vhd -vhdPaths $vhdName -size $$newVHDSize -server $server -fixed:($vhdType -eq "Fixed") -force -wait
        if ($newVhd -eq $null)
        {
            write-output "Error: New-VHD failed to create the new .vhd file: $($vhdName)"
            return $retVal
        }
    }
    
    #
    # Attach the .vhd file to the new drive
    #
    $disk = Add-VMDisk -vm $vmName -ControllerID $controllerID -Lun $Lun -Path $vhdName -SCSI:$SCSI -server $server
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
    
    return $retVal
}

############################################################################
#
# Main entry point for script
#
############################################################################

$retVal = $true

"AddHardDisk.ps1 -vmName $vmName -hvServer $hvServer -testParams $testParams"

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
    {
        continue
    }

    $temp = $p.Trim().Split('=')
    if ( $temp[0] -eq "passDriveNumbers" )
    {
        $passDrives = $temp[1].Trim().Split(',')
        $diskDriveIndex = 0
    }
}

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
    
    $controllerType = $temp[0]
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
   
    if ($diskArgs.Length -ne 4 -and $diskArgs.Length -ne 3)
    {
        "Error: Incorrect number of arguments: $p"
        $retVal = $false
        continue
    }
    
    $controllerID = $diskArgs[0].Trim()
    $lun = $diskArgs[1].Trim()
    $vhdType = $diskArgs[2].Trim()
    $VHDSize = $global:MinDiskSize
   
    if ($diskArgs.Length -eq 4)
    {
        $VHDSize = $diskArgs[3].Trim()
    }
   
    
    if (@("Fixed", "Dynamic", "PassThrough", "Diff") -notcontains $vhdType)
    {
        "Error: Unknown disk type: $p"
        $retVal = $false
        continue
    }
    
    if ($vhdType -eq "PassThrough")
    {
        "CreatePassThruDrive $vmName $hvServer $scsi $controllerID $Lun"
        $sts = CreatePassThruDrive $vmName $hvServer -SCSI:$scsi $controllerID $Lun $passDrives[$diskDriveIndex]
        $results = [array]$sts
        if (! $results[$results.Length-1])
        {
            "Failed to create PassThrough drive"
            $sts
            $retVal = $false
            continue
        }
        $diskDriveIndex += 1
    }
    else # Must be Fixed, Dynamic, or Diff
    {
        "CreateHardDrive $vmName $hvServer $scsi $controllerID $Lun $vhdType $VHDSize"
        $sts = CreateHardDrive -vmName $vmName -server $hvServer -SCSI:$SCSI -ControllerID $controllerID -Lun $Lun -vhdType $vhdType -newSize $VHDSize
        if (! $sts[$sts.Length-1])
        {
            write-output "Failed to create hard drive"
            $sts
            $retVal = $false
            continue
        }
    }
}

return $retVal
