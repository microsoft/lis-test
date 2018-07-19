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

#######################################################################
#
#	Checks if the file copy daemon is running on the Linux guest
#
#######################################################################
function check_fcopy_daemon()
{
	$filename = ".\fcopy_present"

    .\bin\plink -i ssh\${sshKey} root@${ipv4} "ps -ef | grep '[h]v_fcopy_daemon\|[h]ypervfcopyd' > /tmp/fcopy_present"
    if (-not $?) {
        Write-Error -Message  "ERROR: Unable to verify if the fcopy daemon is running" -ErrorAction SilentlyContinue
        Write-Output "ERROR: Unable to verify if the fcopy daemon is running"
        return $False
    }

    .\bin\pscp -i ssh\${sshKey} root@${ipv4}:/tmp/fcopy_present .
    if (-not $?) {
		Write-Error -Message "ERROR: Unable to copy the confirmation file from the VM" -ErrorAction SilentlyContinue
		Write-Output "ERROR: Unable to copy the confirmation file from the VM"
		return $False
    }

    # When using grep on the process in file, it will return 1 line if the daemon is running
    if ((Get-Content $filename  | Measure-Object -Line).Lines -eq  "1" ) {
		Write-Output "Info: hv_fcopy_daemon process is running."
		$retValue = $True
    }

    del $filename
    return $retValue
}

#######################################################
#
#	Stop hypervfcopyd or hv_fcopy_daemon when it is running on vm
#
#######################################################################
function stop_fcopy_daemon()
{
    $sts = check_fcopy_daemon
    if ($sts[-1] -eq $True ){
        .\bin\plink -i ssh\${sshKey} root@${ipv4} "pkill -f 'fcopy'"
        if (-not $?) {
            Write-Error -Message  "ERROR: Unable to kill hypervfcopy daemon" -ErrorAction SilentlyContinue
            Write-Output "ERROR: Unable to kill hypervfcopy daemon"
            return $False
        }
    }
    return $true
}

#######################################################################
#
#	Checks if test file is present
#
#######################################################################
function check_file([String] $testfile)
{
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "wc -c < /tmp/$testfile"
    if (-not $?) {
        Write-Output "ERROR: Unable to read file" -ErrorAction SilentlyContinue
        return $False
    }
	return $True
}

#################################################################
#
# Remove file from vm
#
#################################################################
function remove_file_vm() {
    . .\setupScripts\TCUtils.ps1
    $sts = SendCommandToVM $ipv4 $sshKey "rm -f /mnt/$testfile"
    if (-not $sts) {
        return $False
    }
    return $True
}

#################################################################
#
# Do fdisk /dev/sdb, mkfs /dev/sdb1 and mount /dev/sdb1 to /mnt
#
#################################################################
function Mount-Disk()
{
    $driveName = "/dev/sdb"

    $sts = SendCommandToVM $ipv4 $sshKey "(echo d;echo;echo w)|fdisk ${driveName}"
    if (-not $sts) {
        Write-Output "ERROR: Failed to format the disk in the VM $vmName."
        return $Failed
    }

    $sts = SendCommandToVM $ipv4 $sshKey "(echo n;echo p;echo 1;echo;echo;echo w)|fdisk ${driveName}"
    if (-not $sts) {
        Write-Output "ERROR: Failed to format the disk in the VM $vmName."
        return $Failed
    }

    $sts = SendCommandToVM $ipv4 $sshKey "mkfs.ext4 ${driveName}1"
    if (-not $sts) {
        Write-Output "ERROR: Failed to make file system in the VM $vmName."
        return $Failed
    }

    $sts = SendCommandToVM $ipv4 $sshKey "mount ${driveName}1 /mnt"
    if (-not $sts) {
        Write-Output "ERROR: Failed to mount the disk in the VM $vmName."
        return $Failed
    }

    "Info: $driveName has been mounted to /mnt in the VM $vmName."

    return $True
}

#################################################################
#
# Check systemd available or not
#
#################################################################
function Check-Systemd()
{
    $check1 = $true
    $check2 = $true
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "ls -l /sbin/init | grep systemd"
    if ($? -ne "True"){
        Write-Output "Systemd not found on VM"
        $check1 = $false
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "systemd-analyze --help"
    if ($? -ne "True"){
        Write-Output "Systemd-analyze not present on VM."
        $check2 = $false
    }

    if (($check1 -and $check2) -eq $true) {
        return $true
    } else {
        return $false
    }
}
