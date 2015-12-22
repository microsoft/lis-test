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


   <cleanupScript>SetupScripts\Remove-VhdxHardDisk.ps1</cleanupScript>


  The  scripts will always pass the vmName, hvServer, and a string of testParams from the
	test definition separated by semicolons.

	Test params xml entry:
    <testParams>
		<param>dynamic=True</param>
    <testParams>

   Cleanup scripts need to parse the testParam string to find any
   parameters it needs.


   All setup and cleanup scripts must return a boolean ($true or $false)
  to indicate if the script completed successfully or not.

	.Parameter vmName
		Name of the VM to remove disk from .

	.Parameter hvServer
		Name of the Hyper-V server hosting the VM.

	.Parameter testParams
		Test data for this test case

	.Example
		setupScripts\Remove-VHDXHardDisk -vmName VM_NAME -hvServer HYPERV_SERVER -testParams "sectorSize=512"
#>
############################################################################

param([string] $vmName, [string] $hvServer, [string] $testParams)

############################################################################
#
# Main entry point for script
#
############################################################################

$retVal 	= $False

$sectorSize = $null
$defaultSize = 3GB
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
[int]$max = 0
$v = $null
foreach($p in $params){
    $fields = $p.Split("=")
    $value = $fields[0].Trim()
    switch -wildcard ($value)
    {
    "Type?"          { $v = $value.substring(4) }
    "SectorSize?"    { $v = $value.substring(10) }
    "DefaultSize?"   { $v = $value.substring(11) }
    default     {}  # unknown param - just ignore it
    }
    if ([int]$v -gt $max -and $v -ne $null){
        $max = [int]$v
    }
}
for($pair=0; $pair -le $max; $pair++){

  foreach ($p in $params)
  {
    $fields = $p.Split("=")
    $value = $fields[1].Trim()
    switch  ($fields[0].Trim())
    {
      "Type$pair"         { $type    = $fields[1].Trim() }
      "SectorSize$pair"    { $sectorSize   = $fields[1].Trim() }
      "DefaultSize$pair"   { $defaultSize = $fields[1].Trim() }
      "Type"         { $type    = $fields[1].Trim() }
      "SectorSize"    { $sectorSize   = $fields[1].Trim() }
      "DefaultSize"   { $defaultSize = $fields[1].Trim() }
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

  $vhdxName = $vmName + "-" + $defaultSize + "-" + $sectorSize + "-test"
  $vhdxDisks = Get-VMHardDiskDrive -VMName $vmName -ComputerName $hvServer

  foreach ($vhdx in $vhdxDisks)
  {
  	$vhdxPath = $vhdx.Path
  	if ($vhdxPath.Contains($vhdxName))
  	{
  		$error.Clear()
  		"Info : Removing drive $vhdxName"
  		Remove-VMHardDiskDrive -vmName $vmName -ControllerType $vhdx.controllerType -ControllerNumber $vhdx.controllerNumber -ControllerLocation $vhdx.ControllerLocation -ComputerName $hvServer
  		if ($error.Count -gt 0)
  		{
  			"Error: Remove-VMHardDiskDrive failed to delete drive on SCSI controller "
  			$error[0].Exception
  			return $retVal
  		}

  		$error.Clear()
  		"Info: Deleting vhdx file $vhdxPath"
      $remoteDrive = $vhdxPath.Substring(0,1)
      $remotePath = $vhdxPath.Substring(3)
  		Remove-Item -Path "\\${hvServer}\${remoteDrive}$\${remotePath}"
  		if ($error.Count -gt 0)
  		{
  			"Error: Failed to delete VHDx File "
  			$error[0].Exception
  			return $retVal
  		}
  	}
  }
}

$retVal = $True
return $True