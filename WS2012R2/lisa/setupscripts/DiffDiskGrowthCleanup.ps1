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
    This cleanup script, which runs after the VM is booted, will removes an  differencing hard drive to the specified VM.

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
    setupScripts\DiffDiskGrowthCleanup.ps1 -vmName sles11sp3x64 -hvServer localhost -testParams "IDE=1,1,Diff;ParentVhd=VHDXParentDiff.vhdx;sshkey=rhel5_id_rsa.ppk;ipv4=10.200.50.192;RootDir=" 

.Link
    None.
#>



param([String] $vmName, [String] $hvServer, [String] $testParams)


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


#######################################################################
#
# Main script body
#
#######################################################################

"DynamicDiskGrowthCleanup.ps1"
"  vmName = ${vmName}"
"  hvServer = ${hvServer}"
"  testParams = ${testParams}"

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
        if ($controllerType -eq "IDE")
        {
            $IDE = $true
        }
            
        $diskArgs = $rValue.Split(',')
        
        if ($diskArgs.Length -ne 3)
        {
            "Error: Incorrect number of disk arguments: $p"
            return $Ralse
        }
        
        $controllerID = $diskArgs[0].Trim()
        $lun = $diskArgs[1].Trim()
        $vhdType = $diskArgs[2].Trim()
        
        if ($vhdType -ne "Diff")
        {
            "Error: The differencing disk test requires a differencing disk"
            return $False
        }
    }
}

#
# Make sure we have all the data we need to do our job
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

#
# Delete the drive if it exists
#

$controller = $null
$drive = $null

if($ide)
{
    $controller = Get-VMIdeController -VMName $vmName -ComputerName $hvServer -ControllerNumber $controllerID
}
if($scsi)
{
    $controller = Get-VMScsiController -VMName $vmName -ComputerName $hvServer -ControllerNumber $controllerID
}

if ($controller)
{
    $drive = Get-VMHardDiskDrive $controller -ControllerLocation $lun
    if ($drive)
    {
        write-output "Info : Removing $controllerType $controllerID $lun"
        $sts = Remove-VMHardDiskDrive $drive
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
# Put a true string at the end of the script output
# and exit with a status of zero.
#
return $True
