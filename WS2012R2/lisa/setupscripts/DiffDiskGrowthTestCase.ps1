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
    This test script, which runs inside VM it mount the dirve and perform write operation on diff disk.
    And checks to ensure that parent disk size does not change.

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
    setupScripts\STOR_DiffDiskGrowthTestCase.ps1 -vmName VMname -hvServer localhost -testParams "IDE=1,1,Diff;ParentVhd=VHDXParentDiff.vhdx;sshkey=rhel5_id_rsa.ppk;ipv4=IP;RootDir="

.Link
    None.
#>

param ([String] $vmName, [String] $hvServer, [String] $testParams)

######################################################################
# Runs a remote script on the VM an returns the log.
#######################################################################
function RunRemoteScript($remoteScript)
{
    $retValue = $False
    $stateFile     = "state.txt"
    $TestCompleted = "TestCompleted"
    $TestAborted   = "TestAborted"
    $TestRunning   = "TestRunning"
    $timeout       = 6000    

    "./${remoteScript} > ${remoteScript}.log" | out-file -encoding ASCII -filepath runtest.sh 

    echo y | .\bin\pscp -i ssh\${sshKey} .\runtest.sh root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy runtest.sh to the VM"
       return $False
    }      

    echo y | .\bin\pscp -i ssh\${sshKey} .\remote-scripts\ica\${remoteScript} root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy ${remoteScript} to the VM"
       return $False
    }

    echo y | .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix ${remoteScript} 2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to run dos2unix on ${remoteScript}"
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to run dos2unix on runtest.sh" 
        return $False
    }
    
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x ${remoteScript}   2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to chmod +x ${remoteScript}" 
        return $False
    }
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to chmod +x runtest.sh " -
        return $False
    }

    # Run the script on the vm
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "./runtest.sh 2> /dev/null"
    
    # Return the state file
    while ($timeout -ne 0 )
    {
    .\bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${stateFile} . #| out-null
    $sts = $?
    if ($sts)
    {
        if (test-path $stateFile)
        {
            $contents = Get-Content -Path $stateFile
            if ($null -ne $contents)
            {
                    if ($contents -eq $TestCompleted)
                    {                    
                        Write-Output "Info : state file contains Testcompleted"              
                        $retValue = $True
                        break                                             
                                     
                    }

                    if ($contents -eq $TestAborted)
                    {
                         Write-Output "Info : State file contains TestAborted failed. "                                  
                         break
                          
                    }
                    #Start-Sleep -s 1
                    $timeout-- 

                    if ($timeout -eq 0)
                    {                        
                        Write-Output "Error : Timed out on Test Running , Exiting test execution."                    
                        break                                               
                    }                                
                  
            }    
            else
            {
                Write-Output "Warn : state file is empty"
                break
            }
           
        }
        else
        {
             Write-Host "Warn : ssh reported success, but state file was not copied"
             break
        }
    }
    else #
    {
         Write-Output "Error : pscp exit status = $sts"
         Write-Output "Error : unable to pull state.txt from VM." 
         break
    }     
    }

    # Get the logs
    $remoteScriptLog = $remoteScript+".log"
    
    bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${remoteScriptLog} . 
    $sts = $?
    if ($sts)
    {
        if (test-path $remoteScriptLog)
        {
            $contents = Get-Content -Path $remoteScriptLog
            if ($null -ne $contents)
            {
                    if ($null -ne ${TestLogDir})
                    {
                        move "${remoteScriptLog}" "${TestLogDir}\${remoteScriptLog}"
                
                    }

                    else 
                    {
                        Write-Output "INFO: $remoteScriptLog is copied in ${rootDir}"                                
                    }                              
                  
            }    
            else
            {
                Write-Output "Warn: $remoteScriptLog is empty"                
            }           
        }
        else
        {
             Write-Output "Warn: ssh reported success, but $remoteScriptLog file was not copied"             
        }
    }
    
    # Cleanup 
    del state.txt -ErrorAction "SilentlyContinue"
    del runtest.sh -ErrorAction "SilentlyContinue"

    return $retValue
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
# Main script body
#
############################################################################

$retVal = $False

$remoteScript = "PartitionDisks.sh"

#
# Display a little info about our environment
#
"STOR_DiffDiskGrowthTestCase.ps1"
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

$controllerType = $null
$controllerID = $null
$lun = $null
$vhdType = $null
$vhdName = $null
$parentVhd = $null
$sshKey = $null
$ipv4 = $null
$TC_COVERED = $null
$vhdFormat = $null

#
# Parse the testParams string and make sure all
# required test parameters have been specified.
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
        Continue
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

    if ($lValue -eq "vhdFormat")
    {
        $vhdFormat = $rValue
        continue
    }

    if($lValue -eq "TC_COVERED")
    {
        $TC_COVERED = $rValue
        continue
    }

    if (@("IDE", "SCSI") -contains $lValue)
    {
        $controllerType = $lValue

        $diskArgs = $rValue.Trim().Split(',')

        if ($diskArgs.Length -ne 3)
        {
            "Error: Incorrect number of arguments: $p"
            $retVal = $false
            Continue
        }

        $controllerID = $diskArgs[0].Trim()
        $lun = $diskArgs[1].Trim()
        $vhdType = $diskArgs[2].Trim()
        Continue
    }

    if ($lValue -eq "FILESYS")
    {
        $FILESYS = $rValue
        Continue
    }

    if ($lValue -eq "sshKey")
    {
        $sshKey = $rValue
        Continue
    }

    if ($lValue -eq "ipv4")
    {
        $ipv4 = $rValue
        Continue
    }

    if ($lValue -eq "rootdir")
    {
        $rootdir = $rValue
        Continue
    }
}

if ($null -eq $rootdir)
{
    "ERROR: Test parameter rootdir was not specified"
    return $False
}

cd $rootdir

# del $summaryLog -ErrorAction SilentlyContinue
$summaryLog = "${vmName}_summary.log"
"Covers: ${TC_COVERED}" >> $summaryLog
#
# Make sure we have all the data we need to do our job
#
if (-not $controllerType)
{
    "Error: Missing controller type in test parameters"
    return $False
}

if (-not $controllerID)
{
    "Error: Missing controller index in test parameters"
    return $False
}

if (-not $lun)
{
    "Error: Missing lun in test parameters"
    return $False
}

if (-not $vhdType)
{
    "Error: Missing vhdType in test parameters"
    return $False
}

if (-not $vhdFormat)
{
    "Error: No vhdFormat specified in the test parameters"
    return $False
}

if (-not $FILESYS)
{
    "Error: Test parameter FILESYS was not specified"
    return $False
}

if (-not $sshKey)
{
    "Error: Missing sshKey test parameter"
    return $False
}

if (-not $ipv4)
{
    "Error: Missing ipv4 test parameter"
    return $False
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

if ($vhdFormat -eq "vhd")
{
    $vhdName = $defaultVhdPath + ${vmName} +"-" + ${controllerType} + "-" + ${controllerID}+ "-" + ${lun} + "-" + "Diff.vhd"
}
else
{
    $vhdName = $defaultVhdPath + ${vmName} +"-" + ${controllerType} + "-" + ${controllerID}+ "-" + ${lun} + "-" + "Diff.vhdx"
}

#
# The .vhd file should have been created by our
# setup script. Make sure the .vhd file exists.
#
$vhdFileInfo = GetRemoteFileInfo $vhdName $hvServer
if (-not $vhdFileInfo)
{
    "Error: VHD file does not exist: ${vhdFilename}"
    return $False
}

$vhdInitialSize = $vhdFileInfo.FileSize

#
# Make sure the .vhd file is a differencing disk
#
$vhdInfo = Get-VHD -path $vhdName -ComputerName $hvServer
if (-not $vhdInfo)
{
    "Error: Unable to retrieve VHD information on VHD file: ${vhdFilename}"
    return $False
}

if ($vhdInfo.VhdType -ne "Differencing")
{
    "Error: VHD `"${vhdName}`" is not a Differencing disk"
    return $False
}

#
# Collect info on the parent VHD
#
$parentVhdFilename = $vhdInfo.ParentPath

$parentFileInfo = GetRemoteFileInfo $parentVhdFilename $hvServer
if (-not $parentFileInfo)
{
    "Error: Unable to collect file information on parent VHD `"${parentVhd}`""
    return $False
}

$parentInitialSize = $parentFileInfo.FileSize

# Format the disk
Start-Sleep -Seconds 30

$sts = RunRemoteScript $remoteScript
if (-not $sts[-1])
{
    Write-Output "ERROR executing $remoteScript on VM. Exiting test case!" >> $summaryLog
    Write-Output "ERROR: Running $remoteScript script failed on VM!"
    Write-Output "Here are the remote logs:`n`n###################"
    $logfilename = ".\$remoteScript.log"
    Get-Content $logfilename
    Write-Output "###################`n"
    return $False
}
Write-Output "$remoteScript execution on VM: Success"
Write-Output "Here are the remote logs:`n`n###################"
$logfilename = ".\$remoteScript.log"
Get-Content $logfilename
Write-Output "###################`n"
Write-Output "$remoteScript execution on VM: Success" >> $summaryLog
Remove-Item $logfilename

# return $true
#
# Tell the guest OS on the VM to mount the differencing disk
#

# $sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "mount /dev/sdb1 /mnt" | out-null
# if (-not $?)
# {
#     "Error: Unable to send mount request to VM"
#     return $False
# }

$sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "mkdir -p /mnt/2/DiffDiskGrowthTestCase" | out-null
if (-not $?)
{
    "Error: Unable to send mkdir request to VM"
    return $False
}

#
# Tell the guest OS to write a few MB to the differencing disk
#
$sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dd if=/dev/sda1 of=/mnt/2/DiffDiskGrowthTestCase/test.dat count=2048 > /dev/null 2>&1" | out-null
if (-not $?)
{
    "Error: Unable to send cp command to VM to grow the .vhd"
    return $False
}

# return $true

#
# Tell the guest OS on the VM to unmount the differencing disk
#
$sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "umount /mnt/1 | umount /mnt/2" | out-null
if (-not $?)
{
    "Warn : Unable to send umount request to VM"
    return $False
}

#
# Save the current size of the parent VHD and differencing disk
#
$parentInfo = GetRemoteFileInfo $parentVhdFilename $hvServer
$parentFinalSize = $parentInfo.fileSize

$vhdInfo = GetRemoteFileInfo $vhdFilename $hvServer
$vhdFinalSize = $vhdInfo.FileSize

#
# Make sure the parent matches its initial size
#
if ($parentFinalSize -eq $parentInitialSize)
{
    #
    # The parent VHD was not written to
    #
    "Info: The parent .vhd file did not change in size"
    $retVal = $true
}

if ($vhdFinalSize -gt $vhdInitialSize)
{
    "Info : The differencing disk grew in size from ${vhdInitialSize} to ${vhdFinalSize}"
}

return $retVal
