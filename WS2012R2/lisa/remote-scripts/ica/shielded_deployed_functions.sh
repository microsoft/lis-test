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

AddRecoveryKey ()
{
    # Get root mapper
    root=$(dmsetup ls --target crypt | grep -v boot |  awk {'print $1'})
    
    # Add key to boot partition
    yes shielded_test_pass | cryptsetup luksAddKey /dev/sda2 --master-key-file <(dmsetup table --showkey /dev/mapper/boot | awk '{print$5}' | xxd -r -p)
    if [ $? -ne 0 ]; then
        msg="ERROR: Failed to add key to boot partition"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    else
        SetTestStateCompleted
    fi   

    # Add key to root partition
    yes shielded_test_pass | cryptsetup luksAddKey /dev/sda3 --master-key-file <(dmsetup table --showkey /dev/mapper/${root} | awk '{print$5}' | xxd -r -p)
    if [ $? -ne 0 ]; then
        msg="ERROR: Failed to add key to root partition"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    else
        SetTestStateCompleted
    fi  
}

TestRecoveryKey ()
{
    # Open LUKS partitions
    yes shielded_test_pass | cryptsetup luksOpen /dev/sdb3 encrypted_root
    if [ $? -ne 0 ]; then
        msg="ERROR: Failed to open root LUKS device"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1    
    fi  
    yes shielded_test_pass | cryptsetup luksOpen /dev/sdb2 encrypted_boot
    if [ $? -ne 0 ]; then
        msg="ERROR: Failed to open boot LUKS device"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1    
    fi  

    # Make necessary changes to lvm name. Root partitions might throw a conflict
    lvm_uuid=$(vgdisplay | grep UUID | tail -1 | awk {'print $3'})
    vgrename $lvm_uuid 'Test_LVM'
    vgchange -ay

    # Mount the partitions
    mkdir boot_part && mkdir root_part
    mount /dev/mapper/encrypted_boot boot_part/
    if [ $? -ne 0 ]; then
        msg="ERROR: Failed to mount boot partition"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1    
    fi  

    mount /dev/Test_LVM/root root_part
    if [ $? -ne 0 ]; then
        msg="ERROR: Failed to mount root partition"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1    
    fi  

    SetTestStateCompleted
}