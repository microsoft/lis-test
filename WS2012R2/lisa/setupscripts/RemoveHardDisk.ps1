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
    This setup script will run after the VM shuts down, then delete the VHD.

.Description
   This is a cleanup script that will run after the VM shuts down.
   This script will delete the hard drive, and if no other drives
   are attached to the controller, delete the controller.

   Note: The controller will not be removed if it is an IDE.
         IDE Lun 0 will not be removed.

   Cleanup scripts) are run in a separate PowerShell environment,
   so they do not have access to the environment running the ICA
  scripts.  Since this script uses the PowerShell Hyper-V library,
   these modules must be loaded by this startup script.

   The .xml entry for this script could look like either of the
   following:

   <cleanupScript>SetupScripts\delHardDisk.ps1</cleanupScript>
   The ICA scripts will always pass the vmName, hvServer, and a
   string of testParams from the test definition, separated by
   semicolons. The testParams for this script identify disk
   controllers, hard drives, and .vhd types.  The testParams
   have the format of:
     ControllerType=Controller Index, Lun or Port, vhdType

   An actual testparams definition may look like the following

     <testParams>
         <param>SCSI=0,0,Fixed</param>
        <param>IDE=0,1,Dynamic</param>
     <testParams>

   The above example will be parsed into the following string by the
   ICA scripts and passed to the cleanup script:

       "SCSI=0,0,Fixed;IDE=0,1,Dynamic"

   Cleanup scripts need to parse the testParam string to find any
   parameters it needs.


   SCSI=0,0,Dynamic : Add a hard drive on SCSI controller 0, Lun 0, vhd type of Dynamic disk
   IDE=1,1,Fixed  : Add a hard drive on IDE controller 1, IDE port 1, vhd type of Fixed disk

    A typical XML definition for this test case would look similar
    to the following:
       <test>
            <testName>VHD_SCSI_Fixed</testName>
            <testScript>STOR_Lis_Disk.sh</testScript>
            <files>remote-scripts/ica/STOR_Lis_Disk.sh</files>
            <setupScript>setupscripts\AddHardDisk.ps1</setupScript>
            <cleanupScript>setupscripts\RemoveHardDisk.ps1</cleanupScript>
            <timeout>18000</timeout>
            <testparams>
                    <param>SCSI=0,0,Fixed</param>
            </testparams>
            <onError>Abort</onError>
        </test>

.Parameter vmName
    Name of the VM to remove disk from .

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\RemoveHardDisk.ps1 -vmName VM -hvServer localhost -testParams "SCSI=0,0,Dynamic;sshkey=pki.ppk;ipv4=IPaddr;RootDir="

.Link
    None.
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

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
        "Error: Invalid test parameter: $p"
        $retVal = $false
        continue
    }

    $field_value = $fields[0].Trim().ToLower()
    if ($field_value -ne "scsi" -and $field_value -ne "ide")
    {
        # Just ignore the parameter
        continue
    }
    else
    {
        $controllerType = $fields[0].Trim().ToUpper()
    }
}
$vhdName = $vmName + "-" + $controllerType
$vhdDisks = Get-VMHardDiskDrive -VMName $vmName -ComputerName $hvServer
foreach ($vhd in $vhdDisks)
{
    $vhdPath = $vhd.Path
    if ($vhdPath.Contains($vhdName) -or $vhdPath.Contains('Target')){
        $error.Clear()
        "Info : Removing drive $vhdName"

        Remove-VMHardDiskDrive -vmName $vmName -ControllerType $vhd.controllerType -ControllerNumber $vhd.controllerNumber -ControllerLocation $vhd.ControllerLocation -ComputerName $hvServer
        if ($error.Count -gt 0)
        {
            "Error: Remove-VMHardDiskDrive failed to delete drive on SCSI controller "
            $error[0].Exception
            return $retVal
        }
    }
}

$hostInfo = Get-VMHost -ComputerName $hvServer
if (-not $hostInfo)
{
    "Error: Unable to collect Hyper-V settings for ${hvServer}"
    return $retVal
}

$defaultVhdPath = $hostInfo.VirtualHardDiskPath
$defaultVhdPath = $defaultVhdPath.Replace(':','$')
if (-not $defaultVhdPath.EndsWith("\"))
{
    $defaultVhdPath += "\"
}

Get-ChildItem \\$hvServer\$defaultVhdPath -Filter $vhdName* | `
Foreach-Object  {
    $remotePath = $_.FullName
    $localPath = $remotePath.Substring($hvServer.Length+3).Replace('$',':')
    Invoke-Command $hvServer -ScriptBlock  {Dismount-VHD -Path $args[0] -ErrorAction SilentlyContinue} -ArgumentList $localPath
    $error.Clear()
    Remove-Item -Path $_.FullName
    if ($error.Count -gt 0)
    {
        "Error: Failed to delete VHDx File "
        $error[0].Exception
        return $retVal
    }
}

$retVal = $true

"RemoveHardDisk returning $retVal"

return $retVal
