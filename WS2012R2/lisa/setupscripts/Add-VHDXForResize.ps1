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
    This setup script, that will run before the VM is booted, will add VHDx Hard Driver on 
	a SCSI controller to VM.


.Description
     This is a setup script that will run before the VM is booted.
     The script will create a minimum 3GB vhdx file, and mount it to the
     specified hard drive. 


     The .xml entry to specify this startup script would be:


         <setupScript>SetupScripts\Add-VHDXForResize.ps1.ps1</setupScript>


	The  scripts will always pass the vmName, hvServer, and a string of testParams from the 
	test definition separated by semicolons. The testParams for this script identifies VHDx
	type, sector size and the default size.
	The following are some examples
	
	"dynamic=True;sectorSize=512;defaultSize=5GB" 	: Add a 5GB, 512 sector size, dynamic VHDx
	"dynamic=False;sectorSize=4096;defaultSize=5GB"	: Add a 5GB, 4096 sector size, static VHDx

	Test params xml entry:
    <testParams>
		<param>dynamic=True</param>
        <param>sectorSize=512</param>
		<param>defaultSize=5GB</param>
    <testParams>

.Parameter vmName
    Name of the VM to add disk from .

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\Add-VHDXForResize.ps1 -vmName VM_NAME -hvServer HYPERV_SERVER -testParams "dynamic=True;sectorSize=512;defaultSize=5GB"
#>
############################################################################


param([string] $vmName, [string] $hvServer, [string] $testParams)

###########################################################################
#
# CheckCreateSCSIController
#
# Description
#	Checks if a SCSI controller already exists, if it does not exists
#	a new one is created	
#
############################################################################
function CheckCreateSCSIController([string] $vmName, [string] $hvServer)
{
	$retVal = $True
	
    #
    # Check if the controller already exists.
    #
    $scsiCtrl = Get-VMScsiController -VMName $vmName -ComputerName $hvServer
    if ($scsiCtrl.Length -lt 1)
    {
		#
		# Creating SCSI controller
		#
        $error.Clear()
        Add-VMScsiController -VMName $vmName -ComputerName $hvServer
        if ($error.Count -gt 0)
        {
            "    Error: Add-VMScsiController failed to add 'SCSI Controller"
            $error[0].Exception
            $retVal = $False
			return $retVal
        }
        "Info : SCSI Controller successfully added"
		return $retVal
    }
	
	"Info : SCSI controller already exists"
    return $retVal
}

###########################################################################
#
# CreateAttachVHDxTestDiskDrive
#
# Description
#	Creates and attach a new VHDx test hard disk 
#
############################################################################
function CreateAttachVHDxTestDiskDrive( [string] $vmName, [string] $hvServer, 
						[System.Boolean] $vhdxType, [string]$sectorSize,
						[string] $defaultSize )
{
	$vmDrive = Get-VMHardDiskDrive -VMName $vmName -ComputerName $hvServer
	$lastSlash = $vmDrive[0].Path.LastIndexOf("\")
	
	$defaultVhdPath = $vmDrive[0].Path.Substring(0,$lastSlash)
	if (-not $defaultVhdPath.EndsWith("\"))
	{
		$defaultVhdPath += "\"
	}
	$newVHDxSize = ConvertStringToUInt64 $defaultSize
	$vhdxName = $defaultVhdPath + $vmName + "-" + $sectorSize + "-test.vhdx"
	
	$sts = New-VHD -Path $vhdxName -size $newVHDxSize -Dynamic:$vhdxType -LogicalSectorSize $sectorSize	  -ComputerName $hvServer
	if ($sts -eq $null)
	{
		"Error: New-VHD failed to create the new .vhdx file: $($vhdxName)"
		return $False
	}
	
	$error.Clear()
	Add-VMHardDiskDrive -VMName $vmName -Path $vhdxName -ControllerType SCSI -ComputerName $hvServer
	if ($error.Count -gt 0)
	{
		"Error: Add-VMHardDiskDrive failed to add drive on SCSI controller "
		$error[0].Exception
		return $False
	}
	
	"VHDx disk drive successfully added"
	return $True
}

############################################################################
#
# Main entry point for script
#
############################################################################

$retVal = $False

$dynamic 		= $False
$sectorSize 	= $null
$defaultSize 	= 3GB

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

$params = $testParams.TrimEnd(";").Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    $value = $fields[1].Trim()

    switch ($fields[0].Trim())
    {
    "Dynamic"    	{ $dynamic  = $True }
    "SectorSize"	{ $sectorSize    = $fields[1].Trim() }
	"DefaultSize"	{ $defaultSize  = $fields[1].Trim() }
    default     {}  # unknown param - just ignore it
    }
}

# Source STOR_VHDXResize_Utils.ps1
if (Test-Path ".\setupScripts\STOR_VHDXResize_Utils.ps1")
{
    . .\setupScripts\STOR_VHDXResize_Utils.ps1
}
else
{
    "Error: Could not find setupScripts\STOR_VHDXResize_Utils.ps1"
    return $false
}

#
# Check/create SCSI controller
#
$sts = CheckCreateSCSIController $vmName $hvServer
if (-not $sts[$sts.Length-1])
{
    "Error: Unable to create SCSI controller"
	return $retVal
}

#
# Create/attach new VHDx hard disk drive
#
$sts = CreateAttachVHDxTestDiskDrive $vmName $hvServer $dynamic $sectorSize $defaultSize
if (-not $sts[$sts.Length-1])
{
	Write-Output "Failed to create hard drive"
	return $retVal
}

$retVal = $True
echo $retVal
return $retVal
