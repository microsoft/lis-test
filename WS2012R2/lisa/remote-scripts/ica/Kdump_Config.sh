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
boot_filepath=""

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
# InstallKexec()
#
#######################################################################
InstallKexec(){
    GetDistro
    case $DISTRO in
        centos* | redhat* | fedora*)
            yum install -y kexec-tools kdump-tools makedumpfile
            if [ $? -ne 0 ]; then
                UpdateSummary "Warning: Kexec-tools failed to install."
            fi
        ;;
        ubuntu* | debian*)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update; apt-get -y install kexec-tools kdump-tools makedumpfile
            if [ $? -ne 0 ]; then
                UpdateSummary "Warning: Kexec-tools failed to install."
            fi
        ;;
        suse*)
            zypper refresh; zypper --non-interactive install kexec-tools kdump makedumpfile
            if [ $? -ne 0 ]; then
                UpdateSummary "Warning: Kexec-tools failed to install."
            fi
        ;;
        *)
            msg="Warning: Distro '${distro}' not supported. Kexec-tools failed to install."
            LogMsg "${msg}"
            UpdateSummary "${msg}"
        ;;
    esac
}
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

    # Extra config for RHEL5 RHEL6.1 RHEL6.2
    if [[ $os_RELEASE.$os_UPDATE =~ ^5.* ]] || [[ $os_RELEASE.$os_UPDATE =~ ^6.[0-2][^0-9] ]] ; then
        RhelExtraSettings
    # Extra config for WS2012 - RHEL6.3+
    elif [[ $os_RELEASE.$os_UPDATE =~ ^6.* ]] && [[ $BuildNumber == "9200" ]] ; then
        echo "extra_modules ata_piix sr_mod sd_mod" >> /etc/kdump.conf
        echo "options ata_piix prefer_ms_hyperv=0" >> /etc/kdump.conf
        echo "blacklist hv_vmbus hv_storvsc hv_utils hv_netvsc hid-hyperv" >> /etc/kdump.conf
        echo "disk_timeout 100" >> /etc/kdump.conf
    fi

    # Extra config for WS2012 - RHEL7
    if [[ $os_RELEASE.$os_UPDATE =~ ^7|8.* ]] && [[ $BuildNumber == "9200" ]] ; then
        echo "extra_modules ata_piix sr_mod sd_mod" >> /etc/kdump.conf
        echo "KDUMP_COMMANDLINE_APPEND=\"ata_piix.prefer_ms_hyperv=0 disk_timeout=100 rd.driver.blacklist=hv_vmbus,hv_storvsc,hv_utils,hv_netvsc,hid-hyperv,hyperv_fb\"" >> /etc/sysconfig/kdump
    fi

    GetGuestGeneration

    if [ $os_GENERATION -eq 2 ] && [[ $os_RELEASE =~ 6.* ]]; then
        boot_filepath=/boot/efi/EFI/BOOT/bootx64.conf
    elif [ $os_GENERATION -eq 1 ] && [[ $os_RELEASE =~ 6.* ]]; then
        boot_filepath=/boot/grub/grub.conf
    elif [ $os_GENERATION -eq 1 ] && [[ $os_RELEASE =~ 7.* || $os_RELEASE =~ 8.* ]]; then
        boot_filepath=/boot/grub2/grub.cfg
    elif [ $os_GENERATION -eq 2 ] && [[ $os_RELEASE =~ 7.* || $os_RELEASE =~ 8.* ]]; then
        boot_filepath=/boot/efi/EFI/redhat/grub.cfg
    else
        boot_filepath=`find /boot -name grub.cfg`
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
    if [ $vm2ipv4 ] && [ $vm2ipv4 != "" ]; then
        yum install -y nfs-utils
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Failed to install nfs."
            UpdateSummary "ERROR: Failed to configure nfs."
            SetTestStateAborted
            exit 1
        fi
        # Kdump configuration differs from RHEL 6 to RHEL 7
        if [ $os_RELEASE -le 6 ]; then
            echo "nfs $vm2ipv4:/mnt" >> /etc/kdump.conf
            if [ $? -ne 0 ]; then
                LogMsg "ERROR: Failed to configure kdump to use nfs."
                UpdateSummary "ERROR: Failed to configure kdump to use nfs."
                SetTestStateAborted
                exit 1
            fi
        else
            echo "dracut_args --mount \"$vm2ipv4:/mnt /var/crash nfs defaults\"" >> /etc/kdump.conf
            if [ $? -ne 0 ]; then
                LogMsg "ERROR: Failed to configure kdump to use nfs."
                UpdateSummary "ERROR: Failed to configure kdump to use nfs."
                SetTestStateAborted
                exit 1
            fi
        fi

        service kdump restart
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Failed to restart Kdump."
            UpdateSummary "ERROR: Failed to restart Kdump."
            SetTestStateAborted
            exit 1
        fi
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
        boot_filepath='/boot/grub2/grub.cfg'
    elif [[ -d /boot/grub ]]; then
        boot_filepath='/boot/grub/menu.lst'
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

    if [ $vm2ipv4 ] && [ $vm2ipv4 != "" ]; then
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
    boot_filepath="/boot/grub/grub.cfg"
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

    # Additional params needed
    sed -i 's/LOAD_KEXEC=true/LOAD_KEXEC=false/g' /etc/default/kexec

    # Configure to dump file on nfs server if it is the case
    apt-get update -y
    sleep 10

    if [ $vm2ipv4 ] && [ $vm2ipv4 != "" ]; then
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
#crashkernel=$1
#vm2ipv4=$2
if [ "$crashkernel" == "" ];then
    LogMsg "ERROR: crashkernel parameter is null."
    UpdateSummary "ERROR: crashkernel parameter is null."
    SetTestStateAborted
    exit 1
fi
LogMsg "INFO: crashkernel=$crashkernel; vm2ipv4=$vm2ipv4"
UpdateSummary "INFO: crashkernel=$crashkernel; vm2ipv4=$vm2ipv4"
#
# Checking the negotiated VMBus version
#
vmbus_string=`dmesg | grep "Vmbus version:"`

if [ "$vmbus_string" = "" ]; then
    LogMsg "WARNING: Negotiated VMBus version is not 3.0. Kernel might be old or patches not included."
    LogMsg "Test will continue but it might not work properly."
    UpdateSummary "WARNING: Full support for kdump is not present, test execution might not work as expected"
fi

InstallKexec

#
# Configure kdump - this has distro specific behaviour
#
GetDistro
case $DISTRO in
    centos* | redhat*)
        ConfigRhel
    ;;
    ubuntu*|debian*)
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
    fedora*)
        if [ "$crashkernel" == "auto" ]; then
            LogMsg "WARNING: crashkernel=auto doesn't work for Fedora. Please use this pattern: crashkernel=X@Y."
            UpdateSummary "WARNING: crashkernel=auto doesn't work for Fedora. Please use this pattern: crashkernel=X@Y."
            SetTestStateSkipped
            exit 1
        else
            ConfigRhel
        fi
    ;;
     *)
        msg="WARNING: Distro '${distro}' not supported, defaulting to RedHat"
        LogMsg "${msg}"
        UpdateSummary "${msg}"
        ConfigRhel
    ;;
esac

command -v grub2-editenv
if [ $? -eq 0 ] && [[ ! -z `grub2-editenv - list | grep -i kernelopts` ]]; then
    # set kernelopts by grub2-editenv
    newopts=`grub2-editenv - list | grep -i kernelopts | sed "s/kernelopts=//g; s/crashkernel=\S*/crashkernel=$crashkernel/g"`
    grub2-editenv - set kernelopts="$newopts"
else
    # Remove old crashkernel params
    sed -i "s/crashkernel=\S*//g" $boot_filepath

    # Remove console params; It could interfere with the testing
    sed -i "s/console=\S*//g" $boot_filepath

    # Add the crashkernel param
    sed -i "/vmlinuz-`uname -r`/ s/$/ crashkernel=$crashkernel/" $boot_filepath
fi

if [ $? -ne 0 ]; then
    LogMsg "ERROR: Could not set the new crashkernel value $crashkernel"
    UpdateSummary "ERROR: Could not set the new crashkernel value $crashkernel"
    SetTestStateAborted
    exit 1
else
    LogMsg "Success: updated the crashkernel value to: $crashkernel."
    UpdateSummary "Success: updated the crashkernel value to: $crashkernel."
fi

# Cleaning up any previous crash dump files
mkdir -p /var/crash
rm -rf /var/crash/*
SetTestStateCompleted
