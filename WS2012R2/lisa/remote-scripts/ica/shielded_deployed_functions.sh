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
# Description:
#   Functions for Deployed Shielded VMs test cases
########################################################################

# Source utils.sh
. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Source constants file and initialize most common variables
UtilsInit

UpgradeBootComponent()
{
	GetDistro
    case "$DISTRO" in
        suse*)
            zypper --non-interactive in grub2
            if [ $? -ne 0 ]; then
                msg="ERROR: Failed to install grub2"
                LogMsg "$msg"
                UpdateSummary "$msg"
                SetTestStateFailed
                exit 1
        	else
            	SetTestStateCompleted
            fi
            ;;
        ubuntu*)
            apt-get install grub -y
            if [ $? -ne 0 ]; then
                msg="ERROR: Failed to install grub2"
                LogMsg "$msg"
                UpdateSummary "$msg"
                SetTestStateFailed
                exit 1
            else
            	SetTestStateCompleted
            fi
            ;;
        redhat*|centos*)
            yum install grub2 -y
            if [ $? -ne 0 ]; then
                msg="ERROR: Failed to install grub2"
                LogMsg "$msg"
                UpdateSummary "$msg"
                SetTestStateFailed
                exit 1
        	else
            	SetTestStateCompleted
            fi
            ;;
        *)
            msg="ERROR: OS Version not supported"
            LogMsg "$msg"
            UpdateSummary "$msg"
            SetTestStateFailed
            exit 1
        ;;
    esac
}

AddSerial ()
{
	GetDistro
    case "$DISTRO" in
        suse*)
            boot_filepath="/boot/grub2/grub.cfg"
            ;;
        ubuntu*)
            boot_filepath="/boot/grub/grub.cfg"
            ;;
        redhat*|centos*)
            boot_filepath="/boot/efi/EFI/redhat/grub.cfg"
            ;;
        *)
            msg="ERROR: OS Version not supported"
            LogMsg "$msg"
            UpdateSummary "$msg"
            SetTestStateFailed
            exit 1
        ;;
    esac

    sed -i "/vmlinuz-`uname -r`/ s/$/ console=tty0 console=ttyS1/" $boot_filepath
    if [ $? -ne 0 ]; then
        msg="ERROR: Failed to modify grub"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
	else
    	SetTestStateCompleted
    fi
}