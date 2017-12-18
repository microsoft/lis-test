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

kdump_conf=/etc/kdump.conf
dump_path=/var/crash
sys_kexec_crash=/sys/kernel/kexec_crash_loaded

dos2unix utils.sh

#
# Source utils.sh to get more utils
# Get $DISTRO, LogMsg directly from utils.sh
#
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    exit 1
}

#
# Source constants file and initialize most common variables
#
UtilsInit

#######################################################################
#
# Rhel()
#
#######################################################################
Rhel()
{
    LogMsg "Waiting 50 seconds for kdump to become active."
    UpdateSummary "Waiting 50 seconds for kdump to become active."
    sleep 50

    case $DISTRO in
    "redhat_6" | "centos_6")
        #
        # RHEL6, kdump status has "operational" and "not operational"
        # So, select "not operational" to check inactive
        #
        service kdump status | grep "not operational"
        if  [ $? -eq 0 ]
        then
            LogMsg "ERROR: kdump service is not active after reboot!"
            UpdateSummary "ERROR: kdump service is not active after reboot!"
            SetTestStateAborted
            exit 1
        else
            LogMsg "Kdump is active after reboot."
            UpdateSummary "Success: kdump service is active after reboot."
        fi
        ;;
    "redhat_7" | "centos_7" | fedora*)
        #
        # RHEL7, kdump status has "Active: active" and "Active: inactive"
        # So, select "Active: active" to check active
        #
        timeout=50
        while [ $timeout -ge 0 ]; do
            service kdump status | grep "Active: active" &>/dev/null
            if [ $? -eq 0 ];then
                break
            else
                LogMsg "Wait for kdump service to be active."
                UpdateSummary "Info: Wait for kdump service to be active."
                timeout=$((timeout-5))
                sleep 5
            fi
        done
        if  [ $timeout -gt 0 ]; then
            LogMsg "Kdump is active after reboot."
            UpdateSummary "Success: kdump service is active after reboot."
        else
            LogMsg "ERROR: kdump service is not active after reboot!"
            UpdateSummary "ERROR: kdump service is not active after reboot!"
            SetTestStateAborted
            exit 1
        fi
        ;;
        *)
            LogMsg "FAIL: Unknown OS!"
            UpdateSummary "FAIL: Unknown OS!"
            SetTestStateAborted
            exit 1
        ;;
    esac
}

#######################################################################
#
# Sles()
#
#######################################################################
Sles()
{
    LogMsg "Waiting 50 seconds for kdump to become active."
    UpdateSummary "Waiting 50 seconds for kdump to become active."
    sleep 50

    if systemctl is-active kdump.service | grep -q "active"; then
        LogMsg "Kdump is active after reboot."
        UpdateSummary "Success: kdump service is active after reboot."
    else
        rckdump status | grep "running"
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: kdump service is not active after reboot!"
            UpdateSummary "ERROR: kdump service is not active after reboot!"
            SetTestStateAborted
            exit 1
        else
            LogMsg "Kdump is active after reboot."
            UpdateSummary "Success: kdump service is active after reboot."
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
    LogMsg "Waiting 50 seconds for kdump to become active."
    UpdateSummary "Waiting 50 seconds for kdump to become active."
    sleep 50

    if [ -e $sys_kexec_crash -a `cat $sys_kexec_crash` -eq 1 ]; then
        LogMsg "Kdump is active after reboot."
        UpdateSummary "Success: kdump service is active after reboot."
    else
        LogMsg "ERROR: kdump service is not active after reboot!"
        UpdateSummary "ERROR: kdump service is not active after reboot!"
        SetTestStateAborted
        exit 1
    fi
}

#######################################################################
#
# kdump_loaded()
#
#######################################################################
kdump_loaded()
{
    UpdateSummary "Checking if kdump is loaded after reboot..."
    CRASHKERNEL=`grep -i crashkernel= /proc/cmdline`;

    if [ ! -e $sys_kexec_crash ] && [ -z "$CRASHKERNEL" ] ; then
        LogMsg "FAILED: kdump is not enabled after reboot."
        UpdateSummary "FAILED: Verify the configuration settings for kdump and grub. Kdump is not enabled after reboot."
        SetTestStateFailed
        exit 1
    else
        LogMsg "Kdump is loaded after reboot."
        UpdateSummary "Success: Kdump is loaded after reboot."
    fi
}

#######################################################################
#
# ConfigureNMI()
#
#######################################################################
ConfigureNMI()
{
    sysctl -w kernel.unknown_nmi_panic=1
    if [ $? -ne 0 ]; then
        LogMsg "Failed to enable kernel to call panic when it receives a NMI."
        UpdateSummary "Failed to enable kernel to call panic when it receives a NMI."
        SetTestStateAborted
        exit 1
    else
        LogMsg "Success: enabling kernel to call panic when it receives a NMI."
        UpdateSummary "Success: enabling kernel to call panic when it receives a NMI."
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

#
# As $DISTRO from utils.sh get the DETAILED Disro. eg. redhat_6, redhat_7, ubuntu_13, ubuntu_14
# So, redhat* / ubuntu* / suse*
#
GetDistro
case $DISTRO in
    centos* | redhat* | fedora*)
        kdump_loaded
        Rhel
    ;;
    ubuntu*)
        kdump_loaded
        Ubuntu
    ;;
    suse*)
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
echo "Preparing for kernel panic..."
sync
sleep 6

echo 1 > /proc/sys/kernel/sysrq
