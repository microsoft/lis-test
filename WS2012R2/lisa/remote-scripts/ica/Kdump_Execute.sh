#!/bin/bash

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

ICA_TESTABORTED="TestAborted"

kdump_conf=/etc/kdump.conf
dump_path=/var/crash
sys_kexec_crash=/sys/kernel/kexec_crash_loaded

#
# Functions definitions
#
LogMsg()
{
    # To add the time-stamp to the log file
    echo `date "+%a %b %d %T %Y"` ": ${1}"
}

UpdateTestState()
{
    echo $1 >> ~/state.txt
}

#######################################################################
#
# LinuxRelease()
#
#######################################################################
LinuxRelease()
{
    DISTRO=`grep -ihs "buntu\|Suse\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux" /etc/{issue,*release,*version}`

    case $DISTRO in
        *buntu*)
            echo "UBUNTU";;
        Fedora*)
            echo "FEDORA";;
        CentOS*)
            echo "CENTOS";;
        *SUSE*)
            echo "SLES";;
        *Red*Hat*)
            echo "RHEL";;
        Debian*)
            echo "DEBIAN";;
    esac
}

#######################################################################
#
# Rhel()
#
#######################################################################
Rhel()
{
    LogMsg "Waiting 70 seconds for kdump to become active."
    echo "Waiting 70 seconds for kdump to become active." >> summary.log
    sleep 70

    systemctl status kdump.service | grep -q "active"
    if  [ $? -ne 0 ]; then
        service kdump status | grep "operational"
        if  [ $? -eq 0 ]; then
            LogMsg "Kdump is active after reboot"
            echo "Success: kdump service is active after reboot." >> ~/summary.log
        else
            LogMsg "ERROR: kdump service is not active after reboot!"
            echo "ERROR: kdump service is not active after reboot!" >> ~/summary.log
            UpdateTestState "TestAborted"
            exit 2   
        fi
    else
        LogMsg "Kdump is active after reboot"
        echo "Success: kdump service is active after reboot." >> ~/summary.log 
    fi     
}

#######################################################################
#
# Sles()
#
#######################################################################
Sles()
{
    LogMsg "Waiting 50 seconds for kdump to become active."
    echo "Waiting 50 seconds for kdump to become active." >> summary.log
    sleep 50
    
    if systemctl is-active kdump.service | grep -q "active"; then
        LogMsg "Kdump is active after reboot"
        echo "Success: kdump service is active after reboot." >> ~/summary.log
    else
        rckdump status | grep "running"
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: kdump service is not active after reboot!"
            echo "ERROR: kdump service is not active after reboot!" >> ~/summary.log
            UpdateTestState "TestAborted"
            exit 1
        else
            LogMsg "Kdump is active after reboot"
            echo "Success: kdump service is active after reboot." >> ~/summary.log    
        fi
    fi
}


#######################################################################
#
# Ubuntu()
#
#######################################################################
Ubuntu()
{
    sleep 50
    LogMsg "Waiting 50 seconds for kdump to become active."
    echo "Waiting 50 seconds for kdump to become active." >> summary.log
    
    if [ -e $sys_kexec_crash -a `cat $sys_kexec_crash` -eq 1 ]; then
        LogMsg "Kdump is active after reboot"
        echo "Success: kdump service is active after reboot." >> ~/summary.log
    else
        LogMsg "ERROR: kdump service is not active after reboot!"
        echo "ERROR: kdump service is not active after reboot!" >> ~/summary.log
        UpdateTestState "TestAborted"
        exit 10
    fi
}

#######################################################################
#
# kdump_loaded()
#
#######################################################################
kdump_loaded()
{
    echo "Checking if kdump is loaded after reboot..." >> summary.log
    CRASHKERNEL=`grep -i crashkernel= /proc/cmdline`;
    
    if [ ! -e $sys_kexec_crash ] && [ -z "$CRASHKERNEL" ] ; then
        LogMsg "FAILED: kdump is not enabled after reboot."
        echo "FAILED: Verify the configuration settings for kdump and grub. Kdump is not enabled after reboot." >> ~/summary.log
        UpdateTestState "TestFailed"
        exit 10
    else
        LogMsg "Kdump is loaded after reboot."
        echo "Success: Kdump is loaded after reboot." >> ~/summary.log
    fi    
}

ConfigureNMI()
{
    sysctl -w kernel.unknown_nmi_panic=1
    if [ $? -ne 0]; then
        LogMsg "Failed to enable kernel to call panic when it receives a NMI."
        echo "Failed to enable kernel to call panic when it receives a NMI." >> summary.log
        UpdateTestState "TestAborted"
        exit 3
    else
        LogMsg "Success: enabling kernel to call panic when it receives a NMI."
        echo "Success: enabling kernel to call panic when it receives a NMI." >> summary.log
    fi        
}

#######################################################################
#
# Main script body
#
#######################################################################

#
# Configure kdump - this has distro specific behaviour
#
# Must allow some time for the kdump service to become active
ConfigureNMI
distro=`LinuxRelease`
case $distro in
    "CENTOS" | "RHEL")
        kdump_loaded
        Rhel
    ;;
    "UBUNTU")
        kdump_loaded
        Ubuntu
    ;;
    "SLES")
        systemctl start atd
        kdump_loaded
        Sles
    ;;
     *)
        kdump_loaded
        Rhel
    ;; 
esac

#
# Preparing for the kernel panic
#
echo "Preparing for kernel panic..." >> summary.log
sync
sleep 6

echo 1 > /proc/sys/kernel/sysrq
