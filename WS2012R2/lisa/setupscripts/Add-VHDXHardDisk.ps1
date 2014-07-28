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
     The script will create a minimum 3GB.vhdx file, and mount it to the
     specified hard drive.  If the hard drive does not exist, it
     will be created.


     The .xml entry to specify this startup script would be:


         <setupScript>SetupScripts\Add-VHDXHardDisk.ps1</setupScript>


   The  scripts will always pass the vmName, hvServer, and a
   string of testParams from the test definition separated by
   semicolons. The testParams for this script identify disk
   controllers, hard drives, .vhd type, and sector size.  The
   testParamss have the format of:


      ControllerType=Controller Index, Lun or Port, vhd type, sector size, disk size


   The following are some examples


   SCSI=0,0,Dynamic,4096,3GB : Add SCSI Controller 0, hard drive on Lun 0, .vhdx type Dynamic, sector size of 4096, 3GB disk size
   SCSI=1,0,Fixed,512,3GB    : Add SCSI Controller 1, hard drive on Lun 0, .vhdx type Fixed, sector size of 512 bytes, 3GB disk size
   IDE=0,1,Dynamic,512,3GB   : Add IDE hard drive on IDE 0, port 1, .vhdx type Fixed, sector size of 512 bytes, 3GB disk size
   IDE=1,1,Fixed,4096,3GB    : Add IDE hard drive on IDE 1, port 1, .vhdx type Fixed, sector size of 4096 bytes, 3GB disk size


   The following testParams


     <testParams>
         <param>SCSI=0,0,Dynamic,4096,3GB</param>
         <param>IDE=1,1,Fixed,512,3GB</param>
     <testParams>


   will be parsed into the following string by the ICA scripts and passed
   to the setup script:


       "SCSI=0,0,Dynamic,4096,3GB;IDE=1,1,Fixed,512,3GB"


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
      Disk zise        = Size of the VHDx files
                         Valid size sample:
                             3GB
                             1TB
                             100MB


   The following are some examples


   SCSI=0,0,Dynamic,4096,3GB : Add a hard drive on SCSI controller 0, Lun 0, vhd type of Dynamic disk with logical sector size of 4096, 3GB disk size
   IDE=1,1,Fixed,40963GB  : Add a hard drive on IDE controller 1, IDE port 1, vhd type of Fixed disk with logical sector size of 4096, 3GB disk size


.Parameter vmName
    Name of the VM to add disk from .


.Parameter hvServer
    Name of the Hyper-V server hosting the VM.


.Parameter testParams
    Test data for this test case


.Example
    setupScripts\Add-VHDXHardDisk -vmName VM_NAME -hvServer HYPERV_SERVER} -testParams "SCSI=0,0,Dynamic,4096,3GB;sshkey=YOUR_KEY.ppk;ipv4=255.255.255.255"
#>
############################################################################


param([string] $vmName, [string] $hvServer, [string] $testParams)


$global:MinDiskSize = 3GB
$global:DefaultDynamicSize = 127GB


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
    if ($ControllerID -lt 0 -or $controllerID -gt 15)
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
        "Info : SCI controller already exists"
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


############################################################################
#
# CreateHardDrive
#
# Description
#     If the -SCSI options is false, an IDE drive is created
#
############################################################################
function CreateHardDrive( [string] $vmName, [string] $server, [System.Boolean] $SCSI, [int] $ControllerID,
                          [int] $Lun, [string] $vhdType, [string] $sectorSizes, [String] $newSize)
{
    $retVal = $false
    $initialSize = $newSize
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
      
        $vmDrive = Get-VMHardDiskDrive -VMName $vmName -ComputerName $server
        $lastSlash = $vmDrive.Path.LastIndexOf("\")


        #
        # Create the .vhd file if it does not already exist, then create the drive and mount the .vhdx
        #
        # $hostInfo = Get-VMHost -ComputerName $server
        # if (-not $hostInfo)
        # {
            # "Error: Unable to collect Hyper-V settings for ${server}"
            # return $False
        # }


        # $defaultVhdPath = $hostInfo.VirtualHardDiskPath
        $defaultVhdPath = $vmDrive.Path.Substring(0,$lastSlash)
        if (-not $defaultVhdPath.EndsWith("\"))
        {
            $defaultVhdPath += "\"
        }
        $newVHDSize = ConvertStringToUInt64 $newSize
        $vhdName = $defaultVhdPath + $vmName + "-" + $controllerType + "-" + $controllerID + "-" + $lun + "-" + $vhdType + ".vhdx"


        $fileInfo = GetRemoteFileInfo -filename $vhdName -server $server
        if (-not $fileInfo)
        {
            $nv = New-Vhd -Path $vhdName -size $newVHDSize -Dynamic:($vhdType -eq "Dynamic") -LogicalSectorSize ([int] $sectorSize)  -ComputerName $server
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
    "Error: setupScript requires test params"
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


    if ($diskArgs.Length -lt 4 -or $diskArgs.Length -gt 5)
    {
        "Error: Incorrect number of arguments: $p"
        $retVal = $false
        continue
    }


    $controllerID = $diskArgs[0].Trim()
    $lun = $diskArgs[1].Trim()
    $vhdType = $diskArgs[2].Trim()


    $sectorSize = 512
    $VHDxSize = $global:MinDiskSize
    if ($diskArgs.Length -eq 5)
    {
        $sectorSize = $diskArgs[3].Trim()
        if ($sectorSize -ne "4096" -and $sectorSize -ne "512")
        {
            "Error: bad sector size: ${sectorSize}"
            return $False
        }
        $VHDxSize = $diskArgs[4].Trim()
    }
    


    if (@("Fixed", "Dynamic", "PassThrough") -notcontains $vhdType)
    {
        "Error: Unknown disk type: $p"
        $retVal = $false
        continue
    }


    "CreateHardDrive $vmName $hvServer $scsi $controllerID $Lun $vhdType $sectorSize"
    $sts = CreateHardDrive -vmName $vmName -server $hvServer -SCSI:$SCSI -ControllerID $controllerID -Lun $Lun -vhdType $vhdType -sectorSize $sectorSize -newSize $VHDxSize
    if (-not $sts[$sts.Length-1])
    {
        write-output "Failed to create hard drive"
        $sts
        $retVal = $false
        continue
    }
}


return $retVal
