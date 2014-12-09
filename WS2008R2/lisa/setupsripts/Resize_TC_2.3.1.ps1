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
    

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>
#######################################################################
#
# Resize_TC_2.3.1.ps1
#
# Description:
#    This is a PowerShell test case script that implements Dynamic
#    Resizing of VHDX test case 2.3.1 and 2.3.2.
#
#    All test case scripts that run under ICA or LiSA accept three
#    arguments:
#        vmName    : The name of the VM under test.
#        hvServer  : The name of the HyperV server hosting vmName.
#        testParam : A semicolon separated list of test parameters.
#                    Test parameters are key/value pairs.  An example
#                    string of testParams would look like:
#                    "ipv4=10.200.41.2;sshKey=rhel5_id_rsa.ppk;rootDir=D:\ica\trunk\ica"
#
#    Test Params used by this script
#        ipv4    = IPv4 address of the test VM.
#        sshKey  = The SSH key to use when talking to the VM.
#        NewSize = The size, in MB to grow the VHDX.
#    
#
#
#######################################################################

param ([string] $vmName, [String] $hvServer, [string] $testParams)



#######################################################################
#
# MountPartition()
#
#######################################################################
function MountPartition([String] $ipv4, [String] $sshKey, [String] $devName, [String] $partID, [String] $mntPoint)
{
    #
    # Create a mount point if it does not exist
    #
    $sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "ls -1 $mntPoint" 2> $null
    if (-not $?)
    {
        $sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "mkdir $mntPoint" 2> $null
        if (-not $?)
        {
            Write-Error -Message "Unable to create mount point ${mntPoint}" -Category InvalidOperation -ErrorAction SilentlyContinue
            return $False
        }
    }

    #
    # Mount the new partition
    #
    $sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "mount /dev/${devName}${partID} $mntPoint"
    if (-not $?)
    {
        Write-Error -Message "Unable to mount /dev/${devName}${partID} on ${mntPoint}" -Category InvalidOperation -ErrorAction SilentlyContinue
        return $False
    }

    return $True
}


#######################################################################
#
# UnMuontPartition()
#
#######################################################################
function UnMountPartition([String] $ipv4, [String] $sshKey, [String] $mntPoint)
{
    $sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "umount $mntPoint > ~/umount.txt" 2> $null
    if (-not $?)
    {
        Write-Error -Message "Unable to unmount ${mntPoint}" -Category InvalidOperation -ErrorAction SilentlyContinue
        return $False
    }

    return $True
}


#######################################################################
#
# CreateAndFormatPartition()
#
#######################################################################
function CreateAndFormatPartition([String] $ipv4, [String] $sshKey, [String] $devName, [String] $partID)
{
    #
    # Check if the partition does not exist, create it
    #
    $sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "ls -1 /dev/${devName}${partID} > /dev/null" 2> $null
    if (-not $?)
    {
        #
        # Create the new partition
        #
        .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "(echo n;echo p;echo ;echo ;echo ;echo w) | fdisk /dev/${devName} 2> ~/fdisk.txt"
        if (-not $?)
        {
            Write-Error -Message "Unable to create partition table on /dev/${devName}" -Category InvalidOperation -ErrorAction SilentlyContinue
            return $False
        }

        #
        # Format the partition with ext4
        #
        $sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "mkfs -t ext4 /dev/${devName}${partID} 2> ~/mkfs.txt"
        if (-not $?)
        {
            Write-Error -Message "Unable to format /dev/${devName}${partID}" -Category InvalidOperation -ErrorAction SilentlyContinue
            return $False
        }
    }

    #
    # If we made it here, everything worked
    #
    return $True
}


#######################################################################
#
#
#
#######################################################################
function DeletePartition([String] $ipv4, [String] $sshKey, [String] $devName, [String] $partID)
{
    #
    # Check if the partition exist, create it
    #
    $sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "ls -1 /dev/${devName}${partID} > /dev/null" 2> $null
    if ($?)
    {
        #
        # Delete the partition
        #
        .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "(echo d;echo ${partID};echo w) | fdisk /dev/${devName} 2> ~/fdisk.txt"
        if (-not $?)
        {
            Write-Error -Message "Unable to delete partition /dev/${devName}${partID}" -Category InvalidOperation -ErrorAction SilentlyContinue
            return $False
        }
    }

    return $True
}


#######################################################################
#
# ReadWriteMountPoint()
#
#######################################################################
function ReadWriteMountPoint([String] $ipv4, [String] $sshKey, [String] $mntPoint)
{
    if (-not $ipv4)
    {
        Write-Error -Message "IPv4 argument is null" -Category InvalidArgument -ErrorAction SilentlyContinue
        return $False
    }

    if (-not $sshKey)
    {
        Write-Error -Message "SSHKey argument is null" -Category InvalidArgument -ErrorAction SilentlyContinue
        return $False
    }

    if (-not $mntPoint)
    {
        Write-Error -Message "mntPoint argument is null" -Category InvalidArgument -ErrorAction SilentlyContinue
        return $False
    }

    $linuxCommands = @( "mkdir ${mntPoint}/ICA/",
                        "echo 'testing' > ${mntPoint}/ICA/ICA_Test.txt",
                        "ls ${mntPoint}/ICA/ICA_Test.txt",
                        "cat ${mntPoint}/ICA/ICA_Test.txt",
                        "rm ${mntPoint}/ICA/ICA_Test.txt",
                        "rmdir ${mntPoint}/ICA/"
                      )
    
    foreach ($cmd in $linuxCommands)
    {
        if (-not (SendCommandToVM $ipv4 $sshKey "${cmd}" 2> $null))
        {
            Write-Error -Message "Operation failed on VM: ${cmd}" -Category InvalidOperation -ErrorAction SilentlyContinue
            return $False
        }
    }

    return $True
}


#######################################################################
#
#
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
# Main script body
#
#######################################################################

$retVal = $False

#
# Check the cmdline arguments
#
"Info : Checking command line arguments"

if (-not $vmName)
{
    "Error: The vmName argument was not specified"
    return $False
}

if (-not $hvServer)
{
    "Error: The hvServer argument was not specified"
    return $False
}

if (-not $testParams)
{
    "Error: No testParams specified"
    return $False
}

#
# Display the test params in the log for debug purposes
#
"Test Params: ${testParams}"

#
# Parse the testParams
#
$sshKey    = $null
$ipv4      = $null
$newSize   = $null
$rootDir   = $null
$tcCovered = "undefined"

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    if ($fields.Length -ne 2)
    {
        continue    # Malformed test parameter - just ignore it
    }
    
    $value = $fields[1].Trim()

    switch ($fields[0].Trim())
    {
    "SSHKey"    { $sshKey  = $value }
    "ipv4"      { $ipv4    = $value }
    "newSize"   { $newSize = $value }
    "rootDIR"   { $rootDir = $value }
    "tcCovered" { $tcCovered = $value }
    default     {}  # unknown param - just ignore it
    }
}

#
# Make sure all required test parameters were found
#
if (-not $ipv4)
{
    "Error: no ipv4 parameter in testParams"
    return $False
}

if (-not $sshKey)
{
    "Error: no sshKey parameter in testParams"
    return $False
}

if (-not $newSize)
{
    "Error: no newSize parameter in testParams"
    return $False
}

"Info : ipv4      = ${ipv4}"
"Info : sshKey    = ${sshKey}"
"Info : newSize   = ${newSize}"
"Info : rootDir   = ${rootDir}"
"Info : tcCovered = ${tcCovered}"

#
# Convert the new vhdx size to a UInt64
#
"Info : Converting newSize string to UInt64"
$newVhdxSize = ConvertStringToUInt64 $newSize
if (-not $newVhdxSize)
{
    "Error: Unable to convert testPaam newSize to a valid Vhdx size"
    $error[0].Exception.Message
    return $False
}

"Info : newVhdxSize = ${newVhdxSize}"

#
# Process the rootDir variable.  This is required for LiSA.
#
"Info : Changing working director to rootDir"
if ($rootDir)
{
    if (-not (Test-Path $rootDir))
    {
        "Error: rootDir contains an invalid path"
        return $False
    }

    cd $rootDir
    "Info : current directory is ${PWD}"
}

#
# Log the TCs this script covers in summary.log
#
"Info : Creating .\${vmName}_summary.log"
echo "Covers ${tcCovered}" > .\${vmName}_summary.log

#
# Source the Test Case utilities
#
"Info : Sourcing the TCUtils.ps1 file"
. .\SetupScripts\TCUtils.ps1
if (-not $?)
{
    "Error: Unable to source the TCUtils.ps1 library"
    return $False
}

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
if (-not $vhdPath.EndsWith(".vhdx"))
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
    "Error: Insufficent disk free space"
    "       This test case requires ${newSize} free"
    "       Current free space is $($diskInfo.FreeSpace)"
    echo "Insufficient disk space" >> .\${vmName}_summary.log
    return $False
}

#
# Make sure the Linux guest detected the new drive
#
"Info : Check if the Linux guest sees the drive"
$sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "ls /dev/sdb"  2> $null
if (-not $?)
{
    "Error: Unable to examine disk on VM"
    return $False
}

#
# If there is a partition table on the volume, do not create a new one
#
"Info : Check if there is a partition table on the drive"
$sts = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "ls -1 /dev/sdb1" 2> $null
if (-not $?)
{
    #
    # Create a partition, format the partition, then mount it
    #
    "Info : Create and format /dev/sdb1"
    if (-not (CreateAndFormatPartition $ipv4 $sshKey "sdb" "1"))
    {
        "Error: Unable to create/mount the new partition /dev/sdb1"
        $error[0].Exception.Message
        return $False
    }
}

#
# Mount the partition
#
"Info : Mounting partition /dev/sdb1"
if (-not (MountPartition $ipv4 $sshKey "sdb" "1" "/mnt"))
{
    "Error: Unable to mount partition /dev/sdb1"
    $error[0].Exception.Message
    return $False
}

#
# Make sure we can read/write the partition
#
"Info : Reading/Writing /dev/sdb1"
if (-not (ReadWriteMountPoint $ipv4 $sshKey "/mnt"))
{
    "Error: Unable to read/write on /dev/sdb1"
    $error[0].Exception.Message
    return $False
}

#
# We unmount the partition so fdisk can update the
# partition table when a new partition is created.
#
"Info : Unmounting /dev/sdb1"
UnmountPartition $ipv4 $sshKey "/mnt"

#
# Grow the vhdx file
#
"Info : Resizing the VHDX to ${newSize}"
Resize-VHD -Path $vhdPath -SizeBytes ($newVhdxSize) -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $?)
{
   "Error: Unable to grow VHDX file '${vhdPath}"
   $error[0].Exception.Message
   return $False 
}

#
# Check if the guest sees the added space
#
"Info : Check if the guest sees the new space"
$diskSize = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "fdisk -l | grep Disk | grep /dev/sdb | cut -f 5 -d ' '"
if (-not $?)
{
    "Error: Unable to determine disk size from within the guest after growing the VHDX"
    return $False
}

if ($diskSize -ne $newVhdxSize)
{
    "Error: VM ${vmName} sees a disk size of ${diskSize}, not the expected size of ${newSize}"
    return $False
}

#
# Create a partition, format the partition, then mount it
#
"Info : Create and format /dev/sdb2"
if (-not (CreateAndFormatPartition $ipv4 $sshKey "sdb" "2"))
{
    "Error: Unable to create/mount the new partition"
    $error[0].Exception.Message
    return $False
}

#
# Mount the partition
#
"Info : Mounting /dev/sdb2 on /ICA"
if (-not (MountPartition $ipv4 $sshKey "sdb" "2" "/ICA"))
{
    "Error: Unable to mount partition /dev/sdb2"
    $error[0].Exception.Message
    return $False
}

#
# Make sure we can read/write the new partition
#
"Info : reading/writing /dev/sdb1"
if (-not (ReadWriteMountPoint $ipv4 $sshKey "/ICA"))
{
    "Error: Unable to read/write on /dev/sdb2"
    $error[0].Exception.Message
    return $False
}

#
# Unmount the partition
#
"Info : Unmounting /dev/sdb2 from /ICA"
UnmountPartition $ipv4 $sshKey "/ICA"

#
# Delete partition 2
#
"Info : Deleting partition /dev/sdb2"
if (-not (DeletePartition $ipv4 $sshKey "sdb" "2"))
{
    "Error: Unable to delete partition /dev/sdb2"
    $error[0].Exception.Message
    return $False
}

#
# Shrink the partition
#
"Info : Resizing the VHDX to Minimum size"
Resize-VHD -Path $vhdPath -ToMinimumSize -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $?)
{
    "Error: Unable to shrink /dev/sdb to minimum size"
    $error[0].Exception.Message
    return $False
}

#
# Force a SCSI bus scan
#
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "fdisk -l /dev/sdb" 

#
# Verify we can still read/write to sdb1
#
"Info : Re-Mounting /dev/sdb1"
if (-not (MountPartition $ipv4 $sshKey "sdb" "1" "/mnt"))
{
    "Error: Unable to mount partition /dev/sdb1"
    $error[0].Exception.Message
    return $False
}

"Info : verifying we can still read/write /dev/sdb1"
if (-not (ReadWriteMountPoint $ipv4 $sshKey "/mnt"))
{
    "Error: Unable to read/write on /dev/sdb1"
    $error[0].Exception.Message
    return $False
}

#
# Unmount the partition
#
"Info : Cleaning up - unmounting /dev/sdb1 from /mnt"
UnmountPartition $ipv4 $sshKey "/mnt"

#
# If we made it here, all the checks passed.
#
return $True
