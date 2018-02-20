#####################################################################
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
#####################################################################


<#
.Synopsis
    Functions that hide the OS of the test VM.

.Description
    This file contains functions that are intended to hide
    differences in the OS platforms.  The hope is to hide
    differences in Linux distros and FreeBSD when the
    Integrated Services are released.

    Currently supported OS platforms:
       Linux
           RHEL
           CentOS
           SLES
           Ubuntu
       BSD
           FreeBSD

    Current functions that provide some abstraction
       GetOSDateString()
       GetOSDos2unixCmd()
       StartATDaemon()

.Link
    None.
#>



#####################################################################
#
# GetOSDateString()
#
#####################################################################
function GetOSDateTimeCmd ([System.Xml.XmlElement] $vm)
{
	<#
	.Synopsis
    	Return an OS specific date command to set the date/time
        on the VM.
    .Description
        Return a OS specific date/time command
        Linux:   "date mmddhhMMyyyy"
        FreeBSD: "date -n ccyymmddhhMM"
	#>

    $dateTimeCmd = $null

    if ($vm)
    {
        if ($vm.os)
        {
            $now = [Datetime]::Now
            $os = $vm.os
            switch ($os)
            {
            #
            # Linux does not boot with the correct date/time
            #
            $LinuxOS   { $dateTimeCmd = "date " + $now.ToString("MMddHHmmyyyy") }

            #
            # FreeBSD does boot with correct date/time, so do nothing for now
            #
            $FreeBSDOS { $dateTimeCmd = "date -n " + $now.ToString("yyyyMMddHHmm") }

            #
            # Complain if it's an unknown OS type
            #
            default   { LogMsg 0 "Error: GetOSDateString() - unknown OS type of $($vm.os)" }
            }
        }
        else
        {
            LogMsg 0 "Error: $($vm.vmName) does not have the <os> xml property"
        }
    }

    return $dateTimeCmd
}


#####################################################################
#
# GetOSDos2unixCmd()
#
#####################################################################
function GetOSDos2unixCmd ([System.Xml.XmlElement] $vm, [String] $filename)
{
	<#
	.Synopsis
    	Return a dos2unix command that is OS specific
    .Description
        Return a OS specific dos2unix command string
        Linux:   dos2unix -q filename
        FreeBSD: dos2unix filename
	#>

    if (-not $vm)
    {
        return $null
    }

    if (-not $filename)
    {
        return $null
    }

    $cmdString = $null
    if ($vm.os)
    {
        switch ( $($vm.os) )
        {
        #
        # We use the -q with Linux
        #
        $LinuxOS    { $cmdString = "dos2unix -q ${filename}" }

        #
        # No options with FreeBSD
        #
        $FreeBSDOS  { $cmdString = "dos2unix ${filename}" }

        #
        # Complain if it's an unknown OS type
        #
        default     { LogMsg 0 "Error: GetOSDos2unixString() - unknown OS type of $($vm.os)" }
        }
    }
    else
    {
        LogMsg 0 "Error: $($vm.vmName) does not have the <os> xml property"
    }

    return $cmdString
}


#####################################################################
#
# StartOSAtDaemon()
#
#####################################################################
function StartOSAtDaemon ([System.Xml.XmlElement] $vm)
{
	<#
	.Synopsis
    	Start the daemon that handles batch jobs
    .Description
        Start the daemon that handles batch jobs for the OS running on
        the VM.  Linux has the atd daemon.  FreeBSD uses crond.
	#>

    if (-not $vm)
    {
        return $False
    }

    $daemonStarted = $False

    if ($vm.os)
    {
        switch ($($vm.os))
        {
        #
        # Linux uses atd
        #
        $LinuxOS    {
                        if ( (SendCommandToVM $vm "/etc/init.d/atd start") )
                        {
                             $daemonStarted = $True
                        }
                     }

        #
        # FreeBSD uses crond which is started by default
        #
        $FreeBSDOS  {
                        $daemonStarted = $True
                    }

        #
        # Complain if it's an unknown OS type
        #
        default     {
                        LogMsg 0 "Error: StaratOSAtDaemon() - unknown OS type of '$($vm.os)'"
                    }
        }
    }
    else
    {
        LogMsg 0 "Error: $($vm.vmName) does not have the <os> xml property"
    }

    return $daemonStarted
}


#####################################################################
#
# GetOSType()
#
#####################################################################
function GetOSType ([System.Xml.XmlElement] $vm)
{
	<#
	.Synopsis
    	Ask the OS to provide it's OS type.
    .Description
        Use SSH to send a uname command to the VM.  Use the
        returned name as OSType.
	#>

    # plink will pending at waiting password if sshkey failed auth, so
    # pipe a 'y' to response
    $os = echo y | bin\plink -i ssh\${sshKey} root@${hostname} "uname -s"
    if ($os -eq $null)
    {
        $os = "unknown"
    }

    switch ($os)
    {
        $LinuxOS   {}
        $FreeBSDOS {}
        default    { $os = "unknown" }
    }

    return $os
}

#####################################################################
#
# GetKernelVersion()
#
#####################################################################
function GetKernelVersion ()
{
	<#
	.Synopsis
        Ask the OS to provide Kernel version.
    .Description
        Use SSH to send a uname command to the VM.  Use the
        returned name as Kernel version.
	#>

    # plink will pending at waiting password if sshkey failed auth, so
    # pipe a 'y' to response
    $ver = echo y | bin\plink -i ssh\${sshKey} root@${hostname} "uname -r"

    return $ver
}

#####################################################################
#
# GetFirmwareVersion()
#
#####################################################################
function GetFirmwareVersion ()
{
	<#
	.Synopsis
        Ask the OS to provide firmware version.
    .Description
        Use SSH to send a uname command to the VM.  The firmware is
        based on shell command result.
	#>

    # plink will pending at waiting password if sshkey failed auth, so
    # pipe a 'y' to response
    $cmdResult = echo y | bin\plink -i ssh\${sshKey} root@${hostname} "[ -d /sys/firmware/efi ] && echo 0"

    $firmware = "BIOS"
    if ($cmdResult -eq "0")
    {
        $firmware = "EFI"
    }
    return $firmware
}


#####################################################################
#
# GetOSRunTestCaseCmd()
#
#####################################################################
function GetOSRunTestCaseCmd ([String] $os, [String] $testFilename, [String] $logFilename)
{
	<#
	.Synopsis
    	Build the command string to run the test case
    .Description
        Create a command string that will run the test case and
        also redirect STDOUT and STDERR to the logfile.
	#>

    $runCmd = $null

    switch ($os)
    {
        $LinuxOS
            {
                $runCmd = "bash ~/${testFilename} > ~/${logFilename} 2>&1"
            }

        $FreeBSDOS
            {
                $runCmd = "bash ~/${testFilename} > ~/${logFilename} 2>&1"
            }

        default
            {

                $runCmd = $null
            }
    }

    return $runCmd
}
