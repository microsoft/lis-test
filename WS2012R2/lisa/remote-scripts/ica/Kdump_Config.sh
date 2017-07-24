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
kdump_sysconfig=/etc/sysconfig/kdump

#
# Source utils.sh to get more utils
# Get $DISTRO, LogMsg directly from utils.sh
#
dos2unix utils.sh
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
# RhelExtraSettings()
#
#######################################################################
RhelExtraSettings(){

    LogMsg "Adding extra kdump parameters(Rhel)..."
    UpdateSummary "Adding extra kdump parameters (Rhel)..."

    to_be_updated=(
            'core_collector makedumpfile'
            'disk_timeout'
            'blacklist'
            'extra_modules'
        )

    value=(
        '-c --message-level 1 -d 31'
        '100'
        'hv_vmbus hv_storvsc hv_utils hv_netvsc hid-hyperv hyperv_fb hyperv-keyboard'
        'ata_piix sr_mod sd_mod'
        )

    for (( item=0; item<${#to_be_updated[@]-1}; item++))
    do
        sed -i "s/${to_be_updated[item]}.*/#${to_be_updated[item]} ${value[item]}/g" $kdump_conf
        echo "${to_be_updated[item]} ${value[item]}" >> $kdump_conf
    done

    kdump_commandline=(
        'irqpoll'
        'maxcpus='
        'reset_devices'
        'ide_core.prefer_ms_hyperv='
    )

    value_kdump=(
        ''
        '1'
        ''
        '0'
    )

    kdump_commandline_arguments=$(grep KDUMP_COMMANDLINE_APPEND $kdump_sysconfig |  sed 's/KDUMP_COMMANDLINE_APPEND="//g' | sed 's/"//g')


    for (( item=0; item<${#kdump_commandline[@]-1}; item++))
    do
        if [ $? -eq 0 ]; then
            kdump_commandline_arguments=$(echo ${kdump_commandline_arguments} | sed "s/${kdump_commandline[item]}\S*//g")
        fi
        kdump_commandline_arguments="$kdump_commandline_arguments ${kdump_commandline[item]}${value_kdump[item]}"
    done

    sed -i "s/KDUMP_COMMANDLINE_APPEND.*/KDUMP_COMMANDLINE_APPEND=\"$kdump_commandline_arguments\"/g" $kdump_sysconfig
}

#######################################################################
#
# ConfigRhel()
#
#######################################################################
ConfigRhel()
{
    # Modifying kdump.conf settings
    LogMsg "Configuring kdump (Rhel)..."
    UpdateSummary "Configuring kdump (Rhel)..."
    sed -i '/^path/ s/path/#path/g' $kdump_conf
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to comment path in /etc/kdump.conf. Probably kdump is not installed."
        UpdateSummary "ERROR: Failed to comment path in /etc/kdump.conf. Probably kdump is not installed."
        SetTestStateAborted
        exit 1
    else
        echo path $dump_path >> $kdump_conf
        LogMsg "Success: Updated the path to /var/crash."
        UpdateSummary "Success: Updated the path to /var/crash."
    fi

    sed -i '/^default/ s/default/#default/g' $kdump_conf
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to comment default behaviour in /etc/kdump_conf. Probably kdump is not installed."
        UpdateSummary "ERROR: Failed to comment default behaviour in /etc/kdump.conf. Probably kdump is not installed."
        SetTestStateAborted
        exit 1
    else
        echo 'default reboot' >>  $kdump_conf
        LogMsg "Success: Updated the default behaviour to reboot."
        UpdateSummary "Success: Updated the default behaviour to reboot."
    fi

    if [[ -z "$os_RELEASE" ]]; then
        GetOSVersion
    fi

    if [[ $os_RELEASE.$os_UPDATE =~ ^5.* ]] || [[ $os_RELEASE.$os_UPDATE =~ ^6.[0-2] ]] ; then
        RhelExtraSettings
    fi

    if [[ -d /boot/grub2 ]]; then
        LogMsg "Update grub"
        if grep -iq "crashkernel=" /etc/default/grub
        then
            sed -i "s/crashkernel=\S*/crashkernel=$crashkernel/g" /etc/default/grub
        else
            sed -i "s/^GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"crashkernel=$crashkernel /g" /etc/default/grub
        fi
        grep -iq "crashkernel=$crashkernel" /etc/default/grub
        if [ $? -ne 0 ]; then
            LogMsg "FAILED: Could not set the new crashkernel value in /etc/default/grub."
            UpdateSummary "FAILED: Could not set the new crashkernel value in /etc/default/grub."
            SetTestStateAborted
            exit 1
        else
            LogMsg "Success: updated the crashkernel value to: $crashkernel."
            UpdateSummary "Success: updated the crashkernel value to: $crashkernel."
        fi

        if [[ -d /sys/firmware/efi ]]; then
            grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg
        else
            grub2-mkconfig -o /boot/grub2/grub.cfg
        fi
    else
        if [ -x "/sbin/grubby" ]; then
            if grep -iq "crashkernel=" /boot/grub/grub.conf
            then
                sed -i "s/crashkernel=\S*/crashkernel=$crashkernel/g" /boot/grub/grub.conf
            else
                sed -i "s/rootdelay=300/rootdelay=300 crashkernel=$crashkernel/g" /boot/grub/grub.conf
            fi
            grep -iq "crashkernel=$crashkernel" /boot/grub/grub.conf
            if [ $? -ne 0 ]; then
                LogMsg "ERROR: Could not set the new crashkernel value."
                UpdateSummary "ERROR: Could not set the new crashkernel value."
                SetTestStateAborted
                exit 1
            else
                LogMsg "Success: updated the crashkernel value to: $crashkernel."
                UpdateSummary "Success: updated the crashkernel value to: $crashkernel."
            fi
        fi
    fi

    # Enable kdump service
    LogMsg "Enabling kdump"
    UpdateSummary "Enabling kdump..."
    chkconfig kdump on --level 35
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to enable kdump."
        UpdateSummary "ERROR: Failed to enable kdump."
        SetTestStateAborted
        exit 1
    else
        LogMsg "Success: kdump enabled."
        UpdateSummary "Success: kdump enabled."
    fi

    # Configure to dump file on nfs server if it is the case
    if [ $vm2ipv4 != "" ]; then
        yum install -y nfs-utils
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Failed to install nfs."
            UpdateSummary "ERROR: Failed to configure nfs."
            SetTestStateAborted
            exit 1
        fi
        echo "dracut_args --mount \"$vm2ipv4:/mnt /var/crash nfs defaults\"" >> /etc/kdump.conf
        service kdump restart
    fi
}


#######################################################################
#
# ConfigSles()
#
#######################################################################
ConfigSles()
{
    LogMsg "Configuring kdump (Sles)..."
    UpdateSummary "Configuring kdump (Sles)..."

    if [[ -d /boot/grub2 ]]; then
        if grep -iq "crashkernel=" /etc/default/grub
        then
            sed -i "s/crashkernel=\S*/crashkernel=$crashkernel/g" /etc/default/grub
        else
            sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"crashkernel=$crashkernel /g" /etc/default/grub
        fi
        grep -iq "crashkernel=$crashkernel" /etc/default/grub
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Could not set the new crashkernel value in /etc/default/grub."
            UpdateSummary "ERROR: Could not set the new crashkernel value in /etc/default/grub."
            SetTestStateAborted
            exit 1
        else
            LogMsg "Success: updated the crashkernel value to: $crashkernel."
            UpdateSummary "Success: updated the crashkernel value to: $crashkernel."
        fi
        grub2-mkconfig -o /boot/grub2/grub.cfg
    fi

    if [[ -d /boot/grub ]]; then
        if grep -iq "crashkernel=" /boot/grub/menu.lst
        then
            sed -i "s/crashkernel=\S*/crashkernel=$crashkernel/g" /boot/grub/menu.lst
        else
            sed -i "s/rootdelay=300/rootdelay=300 crashkernel=$crashkernel/g" /boot/grub/menu.lst
        fi
        grep -iq "crashkernel=$crashkernel" /boot/grub/menu.lst
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Could not configure set the new crashkernel value in /etc/default/grub."
            UpdateSummary "ERROR: Could not configure set the new crashkernel value in /etc/default/grub."
            SetTestStateAborted
            exit 1
        else
            LogMsg "Success: updated the crashkernel value to: $crashkernel."
            UpdateSummary "Success: updated the crashkernel value to: $crashkernel."
        fi
    fi

    LogMsg "Enabling kdump"
    UpdateSummary "Enabling kdump"
    chkconfig boot.kdump on
    if [ $? -ne 0 ]; then
        systemctl enable kdump.service
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: FAILED to enable kdump."
            UpdateSummary "ERROR: FAILED to enable kdump."
            SetTestStateAborted
            exit 1
        else
            LogMsg "Success: kdump enabled."
            UpdateSummary "Success: kdump enabled."
        fi
    else
        LogMsg "Success: kdump enabled."
        UpdateSummary "Success: kdump enabled."
    fi

    if [ $vm2ipv4 != "" ]; then
        zypper --non-interactive install nfs-client
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Failed to install nfs."
            UpdateSummary "ERROR: Failed to configure nfs."
            SetTestStateAborted
            exit 1
        fi
        sed -i 's\KDUMP_SAVEDIR="/var/crash"\KDUMP_SAVEDIR="nfs://'"$vm2ipv4"':/mnt"\g' /etc/sysconfig/kdump
        service kdump restart
    fi

}

#######################################################################
#
# ConfigUbuntu()
#
#######################################################################
ConfigUbuntu()
{
    LogMsg "Configuring kdump (Ubuntu)..."
    UpdateSummary "Configuring kdump (Ubuntu)..."
    sed -i 's/USE_KDUMP=0/USE_KDUMP=1/g' /etc/default/kdump-tools
    grep -q "USE_KDUMP=1" /etc/default/kdump-tools
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: kdump-tools are not existent or cannot be modified."
        UpdateSummary "ERROR: kdump-tools are not existent or cannot be modified."
        SetTestStateAborted
        exit 1
    fi
    sed -i "s/crashkernel=\S*/crashkernel=$crashkernel/g" /boot/grub/grub.cfg
    grep -q "crashkernel=$crashkernel" /boot/grub/grub.cfg
    if [ $? -ne 0 ]; then
        LogMsg "WARNING: Could not configure set the new crashkernel value in /etc/default/grub. Maybe the default value is wrong. We try other configure."
        UpdateSummary "WARNING: Could not configure set the new crashkernel value in /etc/default/grub. Maybe the default value is wrong. We try other configure."

        sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"crashkernel=$crashkernel /g" /etc/default/grub
        grep -q "crashkernel=$crashkernel" /etc/default/grub
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Failed to configure the new crashkernel."
            UpdateSummary "ERROR: Failed to configure the new crashkernel."
            SetTestStateAborted
            exit 1
        else
            update-grub
            LogMsg "Succesfully updated the crashkernel value to: $crashkernel."
            UpdateSummary "Succesfully updated the crashkernel value to: $crashkernel."
        fi
    else
        LogMsg "Success: updated the crashkernel value to: $crashkernel."
        UpdateSummary "Success: updated the crashkernel value to: $crashkernel."
    fi
    sed -i 's/LOAD_KEXEC=true/LOAD_KEXEC=false/g' /etc/default/kexec

    # Configure to dump file on nfs server if it is the case
    apt-get update -y
    sleep 10

    if [ $vm2ipv4 != "" ]; then
        apt-get install -y nfs-kernel-server
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Failed to install nfs."
            UpdateSummary "ERROR: Failed to configure nfs."
            SetTestStateAborted
            exit 1
        fi

        apt-get install nfs-common -y
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Failed to install nfs-common."
            echo "ERROR: Failed to configure nfs-common." >> summary.log
            UpdateTestState "TestAborted"
            exit 1
        fi
        echo "NFS=\"$vm2ipv4:/mnt\"" >> /etc/default/kdump-tools
        service kexec restart
    fi
}

#######################################################################
#
# Main script body
#
#######################################################################
crashkernel=$1
vm2ipv4=$2

#
# Checking the negotiated VMBus version
#
vmbus_string=`dmesg | grep "Vmbus version:"`

if [ "$vmbus_string" = "" ]; then
    LogMsg "WARNING: Negotiated VMBus version is not 3.0. Kernel might be old or patches not included."
    LogMsg "Test will continue but it might not work properly."
    UpdateSummary "WARNING: Full support for kdump is not present, test execution might not work as expected"
fi

#
# Configure kdump - this has distro specific behaviour
#
GetDistro
case $DISTRO in
    centos* | redhat*)
        ConfigRhel
    ;;
    ubuntu*)
        if [ "$crashkernel" == "auto" ]; then
            LogMsg "WARNING: crashkernel=auto doesn't work for Ubuntu. Please use this pattern: crashkernel=X@Y."
            UpdateSummary "WARNING: crashkernel=auto doesn't work for Ubuntu. Please use this pattern: crashkernel=X@Y."
            SetTestStateAborted
            exit 1
        else
            ConfigUbuntu
        fi
    ;;
    suse*)
        if [ "$crashkernel" == "auto" ]; then
            LogMsg "WARNING: crashkernel=auto doesn't work for SLES. Please use this pattern: crashkernel=X@Y."
            UpdateSummary "WARNING: crashkernel=auto doesn't work for SLES. Please use this pattern: crashkernel=X@Y."
            SetTestStateAborted
            exit 1
        else
            ConfigSles
        fi
    ;;
     *)
        msg="WARNING: Distro '${distro}' not supported, defaulting to RedHat"
        LogMsg "${msg}"
        UpdateSummary "${msg}"
        ConfigRhel
    ;;
esac

# Cleaning up any previous crash dump files
mkdir -p /var/crash
rm -rf /var/crash/*
