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
    This setup script, which runs before the VM is booted, will add an additional differencing hard drive to the specified VM.

.Description
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

   SCSI=0,0,Diff : Add a hard drive on SCSI controller 0, Lun 0, vhd type of Dynamic
   IDE=1,1,Diff  : Add a hard drive on IDE controller 1, IDE port 1, vhd type of Diff
   
   Note: This setup script only adds differencing disks.

    A typical XML definition for this test case would look similar
    to the following:
        <test>
        <testName>VHDx_AddDifferencing_Disk_IDE</testName>
        <testScript>setupscripts\DiffDiskGrowthTestCase.ps1</testScript>
        <setupScript>setupscripts\DiffDiskGrowthSetup.ps1</setupScript>
        <cleanupScript>setupscripts\DiffDiskGrowthCleanup.ps1</cleanupScript>
        <timeout>18000</timeout>
        <testparams>                
                <param>IDE=1,1,Diff</param>      
                <param>ParentVhd=VHDXParentDiff.vhdx</param>
                <param>TC_COUNT=DSK_VHDX-75</param>            
        </testparams>
    </test>

.Parameter vmName
    Name of the VM to read intrinsic data from.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\DiffDiskGrowthSetup.ps1 -vmName sles11sp3x64 -hvServer localhost -testParams "IDE=1,1,Diff;ParentVhd=VHDXParentDiff.vhdx;sshkey=rhel5_id_rsa.ppk;ipv4=10.200.50.192;RootDir=" 

.Link
    None.
#>



param([string] $vmName, [string] $hvServer, [string] $testParams)


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
    if ($ControllerID -lt 0 -or $controllerID -gt 3)
    {
        write-output "    Error: Bad SCSI controller ID: $controllerID"
        return $False
    }

    #
    # Check if the controller already exists.
    #
    $scsiCtrl = Get-VMScsiController -VMName $vmName -ComputerName $hvServer
    if ($scsiCtrl.Length -1 -ge $controllerID)
    {
        "Info : SCSI ontroller already exists"
    }
    else
    {
        $error.Clear()
        Add-VMScsiController -VMName $vmName -ComputerName $hvServer
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


#######################################################################
#
# Main script body
#
#######################################################################

"DiffDiskGrowthSetup.ps1"
"  vmName = ${vmName}"
"  hvServer = ${hvServer}"
"  testParams = ${testParams}"

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

$controllerType = $null
$controllerID = $null
$lun = $null
$vhdType = $null
$parentVhd = $null

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

    $tokens = $p.Trim().Split('=')
    
    if ($tokens.Length -ne 2)
    {
	    # Just ignore it
         continue
    }
    
    $lValue = $tokens[0].Trim()
    $rValue = $tokens[1].Trim()

    #
    # ParentVHD test param?
    #
    if ($lValue -eq "ParentVHD")
    {
        $parentVhd = $rValue
        continue
    }

    #
    # Controller type testParam?
    #
    if (@("IDE", "SCSI") -contains $lValue)
    {
        $controllerType = $lValue
        
        $SCSI = $false
        if ($controllerType -eq "SCSI")
        {
            $SCSI = $true
        }
            
        $diskArgs = $rValue.Split(',')
        
        if ($diskArgs.Length -ne 3)
        {
            "Error: Incorrect number of disk arguments: $p"
            return $False
        }
        
        $controllerID = $diskArgs[0].Trim()
        $lun = $diskArgs[1].Trim()
        $vhdType = $diskArgs[2].Trim()
        
        #
        # Just a reminder. The test case is testing differencing disks.
        # If we are asked to create a disk other than a differencing disk,
        # then the wrong setup script was specified.
        #
        if ($vhdType -ne "Diff")
        {
            "Error: The differencing disk test requires a differencing disk"
            return $False
        }
    }
}

#
# Make sure we have all the required data to do our job
#
if (-not $controllerType)
{
    "Error: No controller type specified in the test parameters"
    return $False
}

if (-not $controllerID)
{
    "Error: No controller ID specified in the test parameters"
    return $False
}

if (-not $lun)
{
    "Error: No LUN specified in the test parameters"
    return $False
}

if (-not $parentVhd)
{
    $parentVhd = "DynamicParent.vhd"
    "Info : no parent vhd specified.  Defaulting to ${parentVhd}"
}

#
# Make sure the disk does not already exist
#
if ($SCSI)
{
    if ($ControllerID -lt 0 -or $ControllerID -gt 3)
    {
        "Error: CreateHardDrive was passed a bad SCSI Controller ID: $ControllerID"
        return $false
    }
        
    #
    # Create the SCSI controller if needed
    #
    $sts = CreateController $vmName $hvServer $controllerID
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
        return $false
    }
}

$drives = Get-VMHardDiskDrive -VMName $vmName -ComputerName $hvServer -ControllerType $controllerType -ControllerNumber $controllerID -ControllerLocation $lun 
if ($drives)
{
    write-output "Error: drive $controllerType $controllerID $Lun already exists"
    return $retVal
}

$hostInfo = Get-VMHost -ComputerName $hvServer
if (-not $hostInfo)
{
    "Error: Unable to collect Hyper-V settings for ${hvServer}"
    return $False
}

$defaultVhdPath = $hostInfo.VirtualHardDiskPath
if (-not $defaultVhdPath.EndsWith("\"))
{
    $defaultVhdPath += "\"
}


if ($parentVhd.EndsWith(".vhd"))
{
    # To Make sure we do not use exisiting  Diff disk , del if exisit 
    $vhdName = $defaultVhdPath + ${vmName} +"-" + ${controllerType} + "-" + ${controllerID}+ "-" + ${lun} + "-" + "Diff.vhd"  
}
else
{
    $vhdName = $defaultVhdPath + ${vmName} +"-" + ${controllerType} + "-" + ${controllerID}+ "-" + ${lun} + "-" + "Diff.vhdx"  
}

#$vhdFileInfo = GetRemoteFileInfo -filename $vhdName -server $hvServer
$vhdFileInfo = GetRemoteFileInfo  $vhdName  $hvServer
if ($vhdFileInfo)
{
    $delSts = $vhdFileInfo.Delete()
    if (-not $delSts -or $delSts.ReturnValue -ne 0)
    {
        "Error: unable to delete the existing .vhd file: ${vhdFilename}"
        rturn $False
    }
}

#
# Make sure the parent VHD is an absolute path, and it exists
#
$parentVhdFilename = $parentVhd
if (-not [System.IO.Path]::IsPathRooted($parentVhd))
{
    $parentVhdFilename = $defaultVhdPath + $parentVhd
}

$parentFileInfo = GetRemoteFileInfo  $parentVhdFilename  $hvServer
if (-not $parentFileInfo)
{
    "Error: Cannot find parent VHD file: ${parentVhdFilename}"
    return $False
}

#
# Create the .vhd file
$newVhd = New-Vhd -Path $vhdName  -ParentPath $parentVhdFilename  -ComputerName $hvServer -Differencing          
if (-not $newVhd)
{
    "Error: unable to create a new .vhd file"
    return $False
}
#
# Just double check to make sure the .vhd file is a differencing disk
#
if ($newVhd.ParentPath -ne $parentVhdFilename)
{
    "Error: the VHDs parent does not match the provided parent vhd path"
    return $False
}

#
# Attach the .vhd file to the new drive
#
$error.Clear()
$disk = Add-VMHardDiskDrive -VMName $vmName -ComputerName $hvServer -ControllerType $controllerType -ControllerNumber $controllerID -ControllerLocation $lun -Path $vhdName    
if ($error.Count -gt 0)
{
    "Error: Add-VMHardDiskDrive failed to add drive on ${controllerType} ${controllerID} ${Lun}s"
    $error[0].Exception
    return $retVal
}
else
{
    write-output "Success"
    $retVal = $true
}
    
return $retVal
