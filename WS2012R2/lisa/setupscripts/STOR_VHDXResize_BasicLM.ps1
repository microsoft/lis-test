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
    Verify basic VHDx Hard Disk resizing.
.Description
    This is a PowerShell test case script that implements Dynamic
    Resizing of VHDX after migration
    Ensures that the VM sees the newly attached VHDx Hard Disk
    Creates partitions, filesytem, mounts partitions, sees if it can perform
    Read/Write operations on the newly created partitions and deletes partitions

    A typical test case definition for this test script would look
    similar to the following:
        <test>
            <testName>VHDXResizeLM</testName>
            <testScript>SetupScripts\STOR_VHDXResize_BasicLM.ps1</testScript>
            <setupScript>SetupScripts\Add-VhdxHardDisk.ps1</setupScript>
            <cleanupScript>SetupScripts\Remove-VhdxHardDisk.ps1</cleanupScript>
            <timeout>600</timeout>
            <onError>Continue</onError>
            <testparams>
                <param>SCSI=0,0,Dynamic,512,3GB</param>
                <param>NewSize=4GB</param>
                <param>TC_COVERED=STOR-VHDx-01</param>
            </testparams>
        </test>
.Parameter vmName
    Name of the VM to attached and resize the VHDx Hard Disk.
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
.Parameter testParams
    Test data for this test case
.Example
    setupScripts\STOR_VHDXResize_BasicLM.ps1 -vmName "VM_Name" -hvServer "HYPERV_SERVER" -TestParams "ipv4=255.255.255.255;sshKey=YOUR_KEY.ppk;TC_COVERED=STOR-VHDx-01"
#>

param( [String] $vmName,
       [String] $hvServer,
       [String] $testParams
)

$sshKey     = $null
$ipv4       = $null
$newSize    = $null
$rootDir    = $null
$TC_COVERED = $null
$TestLogDir = $null
$TestName   = $null

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
# Convert size String
#
#######################################################################
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

    if ($str.EndsWith("MB"))
    {
        $num = $str.Replace("MB","")
        $uint64Size = ([Convert]::ToUInt64($num)) * 1MB
    }
    elseif ($str.EndsWith("GB"))
    {
        $num = $str.Replace("GB","")
        $uint64Size = ([Convert]::ToUInt64($num)) * 1GB
    }
    elseif ($str.EndsWith("TB"))
    {
        $num = $str.Replace("TB","")
        $uint64Size = ([Convert]::ToUInt64($num)) * 1TB
    }
    else
    {
        Write-Error -Message "Invalid newSize parameter: ${str}" -Category InvalidArgument -ErrorAction SilentlyContinue
        return $null
    }

    return $uint64Size
}

function RunTest ([String] $filename)
{

    "exec ./${filename}.sh &> ${filename}.log " | out-file -encoding ASCII -filepath runtest.sh

	.\bin\pscp.exe -i ssh\${sshKey} .\runtest.sh root@${ipv4}:
    if (-not $?)
    {
       Write-Error -Message "Error: Unable to copy startstress.sh to the VM" -ErrorAction SilentlyContinue
       return $False
    }

     .\.\bin\pscp.exe -i ssh\${sshKey} .\remote-scripts\ica\${filename}.sh root@${ipv4}:
    if (-not $?)
    {
       Write-Error -Message "Error: Unable to copy ${filename}.sh to the VM" -ErrorAction SilentlyContinue
       return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix ${filename}.sh  2> /dev/null"
    if (-not $?)
    {
         Write-Error -Message "Error: Unable to run dos2unix on ${filename}.sh" -ErrorAction SilentlyContinue
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix runtest.sh  2> /dev/null"
    if (-not $?)
    {
         Write-Error -Message "Error: Unable to run dos2unix on runtest.sh" -ErrorAction SilentlyContinue
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x ${filename}.sh   2> /dev/null"
    if (-not $?)
    {
         Write-Error -Message "Error: Unable to chmod +x ${filename}.sh" -ErrorAction SilentlyContinue
        return $False
    }
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x runtest.sh  2> /dev/null"
    if (-not $?)
    {
         Write-Error -Message "Error: Unable to chmod +x runtest.sh " -ErrorAction SilentlyContinue
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "./runtest.sh 2> /dev/null"
    if (-not $?)
    {
         Write-Error -Message "Error: Unable to run runtest.sh " -ErrorAction SilentlyContinue
        return $False
    }

    del runtest.sh
    return $True
}
#########################################################################
#    get state.txt file from VM.
########################################################################
function CheckResult()
{
    $retVal = $False
    $stateFile     = "state.txt"
	$localStateFile= "${vmName}_state.txt"
    $TestCompleted = "TestCompleted"
    $TestAborted   = "TestAborted"
    $TestRunning   = "TestRunning"
    $timeout       = 6000

    "Info :   pscp -q -i ssh\${sshKey} root@${ipv4}:$stateFile} ."
    while ($timeout -ne 0 )
    {
    .\bin\pscp.exe -q -i ssh\${sshKey} root@${ipv4}:${stateFile} ${localStateFile} #| out-null
    $sts = $?
    if ($sts)
    {
        if (test-path $localStateFile)
        {
            $contents = Get-Content -Path $localStateFile
            if ($null -ne $contents)
            {
                    if ($contents -eq $TestCompleted)
                    {
						# Write-Host "Info : state file contains Testcompleted"
                        $retVal = $True
                        break

                    }

                    if ($contents -eq $TestAborted)
                    {
                         Write-Host "Info : State file contains TestAborted failed. "
                         break

                    }

                    $timeout--

                    if ($timeout -eq 0)
                    {
                        Write-Error -Message "Error : Timed out on Test Running , Exiting test execution."   -ErrorAction SilentlyContinue
                        break
                    }

            }
            else
            {
                Write-Host "Warn : state file is empty"
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
         Write-Error -Message "Error : pscp exit status = $sts" -ErrorAction SilentlyContinue
         Write-Error -Message "Error : unable to pull state.txt from VM." -ErrorAction SilentlyContinue
         break
    }
    }
    del $localStateFile
    return $retVal
}
#########################################################################
#    get summary.log file from VM.
########################################################################
function SummaryLog()
{
    $retVal = $False
    $summaryFile   = "summary.log"
    $localVMSummaryLog = "${vmName}_error_summary.log"

    .\bin\pscp.exe -q -i ssh\${sshKey} root@${ipv4}:${summaryFile} ${localVMSummaryLog} #| out-null
    $sts = $?
    if ($sts)
    {
        if (test-path $localVMSummaryLog)
        {
            $contents = Get-Content -Path $localVMSummaryLog
            if ($null -ne $contents)
            {
                   Write-Output "Error: ${contents}" | Tee-Object -Append -file $summaryLog
            }
            $retVal = $True
        }
        else
        {
             Write-Host "Warn : ssh reported success, but summary file was not copied"
        }
    }
    else #
    {
         Write-Error -Message "Error : pscp exit status = $sts" -ErrorAction SilentlyContinue
         Write-Error -Message "Error : unable to pull summary.log from VM." -ErrorAction SilentlyContinue
    }
     del $summaryFile
     return $retVal
}
#########################################################################
#    get runtest.log file from VM.
########################################################################
function RunTestLog([String] $filename, [String] $logDir, [String] $TestName)
{
    $retVal = $False
    $RunTestFile   = "${filename}.log"

    .\bin\pscp.exe -q -i ssh\${sshKey} root@${ipv4}:${RunTestFile} . #| out-null
    $sts = $?
    if ($sts)
    {
        if (test-path $RunTestFile)
        {
            $contents = Get-Content -Path $RunTestFile
            if ($null -ne $contents)
            {
                    move "${RunTestFile}" "${logDir}\${TestName}_${filename}_vm.log"

                   #Get-Content -Path $RunTestFile >> {$TestLogDir}\*_ps.log
                   $retVal = $True

            }
            else
            {
                Write-Host "Warn : RunTestFile is empty"
            }
        }
        else
        {
             Write-Host "Warn : ssh reported success, but RunTestFile file was not copied"
        }
    }
    else #
    {
         Write-Error -Message "Error : pscp exit status = $sts" -ErrorAction SilentlyContinue
         Write-Error -Message "Error : unable to pull RunTestFile from VM." -ErrorAction SilentlyContinue
         return $False
    }

     return $retVal
}

#######################################################################
#
# MigrateVM()
#
#######################################################################
function MigrateVM()
{

    #
    # Load the cluster commandlet module
    #
    $sts = get-module | select-string -pattern FailoverClusters -quiet
    if (! $sts)
    {
        Import-module FailoverClusters
        return $False
    }

    #
    # Have migration networks been configured?
    #
    $migrationNetworks = Get-ClusterNetwork
    if (-not $migrationNetworks)
    {
        "Error: $vmName - There are no Live Migration Networks configured"
        return $False
    }

    #
    # Get the VMs current node
    #
    $vmResource =  Get-ClusterResource | where-object {$_.OwnerGroup.name -eq "$vmName" -and $_.ResourceType.Name -eq "Virtual Machine"}
    if (-not $vmResource)
    {
        "Error: $vmName - Unable to find cluster resource for current node"
        return $False
    }

    $currentNode = $vmResource.OwnerNode.Name
    if (-not $currentNode)
    {
        "Error: $vmName - Unable to set currentNode"
        return $False
    }

    #
    # Get nodes the VM can be migrated to
    #
    $clusterNodes = Get-ClusterNode
    if (-not $clusterNodes -and $clusterNodes -isnot [array])
    {
        "Error: $vmName - There is only one cluster node in the cluster."
        return $False
    }

    #
    # For the initial implementation, just pick a node that does not
    # match the current VMs node
    #
    $destinationNode = $clusterNodes[0].Name.ToLower()
    if ($currentNode -eq $clusterNodes[0].Name.ToLower())
    {
        $destinationNode = $clusterNodes[1].Name.ToLower()
    }

    if (-not $destinationNode)
    {
        "Error: $vmName - Unable to set destination node"
        return $False
    }

    "Info : Migrating VM $vmName from $currentNode to $destinationNode"

    $error.Clear()
    $sts = Move-ClusterVirtualMachineRole -name $vmName -node $destinationNode
    if ($error.Count -gt 0)
    {
        "Error: $vmName - Unable to move the VM"
        $error
        return $False
    }

}

#######################################################################
#
# Main script body
#
#######################################################################

#
# Make sure the required arguments were passed
#
if (-not $vmName)
{
    "Error: no VMName was specified"
    return $False
}

if (-not $hvServer)
{
    "Error: No hvServer was specified"
    return $False
}

if (-not $testParams)
{
    "Error: No test parameters specified"
    return $False
}

#
# Debug - display the test parameters so they are captured in the log file
#
Write-Output "TestParams : '${testParams}'"

$summaryLog  = "${vmName}_summary.log"
Del $summaryLog -ErrorAction SilentlyContinue

#
# Parse the test parameters
#
$params = $testParams.TrimEnd(";").Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    $value = $fields[1].Trim()

    switch ($fields[0].Trim())
    {
    "SSHKey"    { $sshKey  = $fields[1].Trim() }
    "ipv4"      { $ipv4    = $fields[1].Trim() }
    "newSize"   { $newSize = $fields[1].Trim() }
    "rootDIR"   { $rootDir = $fields[1].Trim() }
    "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    "TestLogDir" { $TestLogDir = $fields[1].Trim() }
    "TestName"   { $TestName = $fields[1].Trim() }
    default     {}  # unknown param - just ignore it
    }
}

if (-not $rootDir)
{
    "Warn : no rootdir was specified"
}
else
{
    cd $rootDir
}

Write-Output "Covers: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Convert the new size
#
$newVhdxSize = ConvertStringToUInt64 $newSize

#
# Make sure the VM has a SCSI 0 controller, and that
# Lun 0 on the controller has a .vhdx file attached.
#
"Info : Check if VM ${vmName} has a SCSI 0 Lun 0 drive"
$scsi00 = Get-VMHardDiskDrive -VMName $vmName -Controllertype SCSI -ControllerNumber 0 -ControllerLocation 0 -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $scsi00)
{
    "Error: VM ${vmName} does not have a SCSI 0 Lun 0 drive"
    $error[0].Exception.Message
    return $False
}

"Info : Check if the virtual disk file exists"
$vhdPath = $scsi00.Path
$vhdxInfo = GetRemoteFileInfo $vhdPath $hvServer
if (-not $vhdxInfo)
{
    "Error: The vhdx file (${vhdPath} does not exist on server ${hvServer}"
    return $False
}

"Info : Verify the file is a .vhdx"
if (-not $vhdPath.EndsWith(".vhdx") -and -not $vhdPath.EndsWith(".avhdx"))
{
    "Error: SCSI 0 Lun 0 virtual disk is not a .vhdx file."
    "       Path = ${vhdPath}"
    return $False
}

#
# Make sure there is sufficient disk space to grow the VHDX to the specified size
#
$deviceID = $vhdxInfo.Drive
$diskInfo = Get-WmiObject -Query "SELECT * FROM Win32_LogicalDisk Where DeviceID = '${deviceID}'"
if (-not $diskInfo)
{
    "Error: Unable to collect information on drive ${deviceID}"
    return $False
}

if ($diskInfo.FreeSpace -le $newVhdxSize + 10MB)
{
    "Error: Insufficient disk free space"
    "       This test case requires ${newSize} free"
    "       Current free space is $($diskInfo.FreeSpace)"
    return $False
}

#
# Make sure if we can perform Read/Write operations on the guest VM
#
$guest_script = "STOR_VHDXResize_PartitionDisk"

$sts = RunTest $guest_script
if (-not $($sts[-1]))
{
    $sts = SummaryLog
	if (-not $($sts[-1]))
	{
		"Warning : Failed getting summary.log from VM"
	}
    "Error: Running '${guest_script}' script failed on VM "
    return $False
}

$CheckResultsts = CheckResult

$sts = RunTestLog $guest_script $TestLogDir $TestName
if (-not $($sts[-1]))
{
    "Warning : Getting RunTestLog.log from VM, will not exit test case execution "
}

if (-not $($CheckResultsts[-1]))
{
    "Error: Running '${guest_script}'script failed on VM. check VM logs , exiting test case execution "
    return $False
}

"Info : Resizing the VHDX to ${newSize}"
Resize-VHD -Path $vhdPath -SizeBytes ($newVhdxSize) -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $?)
{
   "Error: Unable to grow VHDX file '${vhdPath}"
   return $False
}

#
# Check if the guest sees the added space
#
"Info : Check if the guest sees the new space"
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "echo 1 > /sys/block/sdb/device/rescan"
if (-not $?)
{
    "Error: Failed to force SCSI device rescan"
    return $False
}

$diskSize = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "fdisk -l 2> /dev/null | grep Disk | grep sdb | cut -f 5 -d ' '"
if (-not $?)
{
    "Error: Unable to determine disk size from within the guest after growing the VHDX"
    return $False
}

#
# Let system have some time for the volume change to be indicated
#
$sleepTime = 30
Start-Sleep -s $sleepTime

if ($diskSize -ne $newVhdxSize)
{
    "Error: VM ${vmName} sees a disk size of ${diskSize}, not the expected size of ${newVhdxSize}"
    return $False
}

#
# Make sure if we can perform Read/Write operations on the guest VM
#
$guest_script = "STOR_VHDXResize_PartitionDiskAfterResize"

$sts = RunTest $guest_script
if (-not $($sts[-1]))
{
    $sts = SummaryLog
	if (-not $($sts[-1]))
	{
		"Warning : Failed getting summary.log from VM"
	}
    "Error: Running '${guest_script}' script failed on VM "
    return $False
}

$CheckResultsts = CheckResult

$sts = RunTestLog $guest_script $TestLogDir $TestName
if (-not $($sts[-1]))
{
    "Warning : Getting RunTestLog.log from VM, will not exit test case execution "
}

if (-not $($CheckResultsts[-1]))
{
    "Error: Running '${guest_script}'script failed on VM. check VM logs , exiting test case execution "
    return $False
}

#
# Migrate the VM to another host
#
MigrateVM
if (-not $?)
{
    "Error: Unable to migrate VM"
    return $False
}

#
# Make sure if we can perform Read/Write operations on the guest VM
#
$guest_script = "STOR_VHDXResize_PartitionDiskAfterShrink"

$sts = RunTest $guest_script
if (-not $($sts[-1]))
{
    $sts = SummaryLog
	if (-not $($sts[-1]))
	{
		"Warning : Failed getting summary.log from VM"
	}
    "Error: Running '${guest_script}' script failed on VM "
    return $False
}

$CheckResultsts = CheckResult

$sts = RunTestLog $guest_script $TestLogDir $TestName
if (-not $($sts[-1]))
{
    "Warning : Getting RunTestLog.log from VM, will not exit test case execution "
}

if (-not $($CheckResultsts[-1]))
{
    "Error: Running '${guest_script}'script failed on VM. check VM logs , exiting test case execution "
    return $False
}

#
# Migrate the VM back to original host
#
MigrateVM
if (-not $?)
{
    "Error: Unable to migrate VM"
    return $False
}

"Info : The guest sees the new size ($diskSize)"
"Info : VHDx Resize - ${TC_COVERED} is Done"

return $True
