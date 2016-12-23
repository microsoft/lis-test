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

ICA_TESTRUNNING="TestRunning"
ICA_TESTABORTED="TestAborted"

kdump_conf=/etc/kdump.conf
dump_path=/var/crash
sys_kexec_crash=/sys/kernel/kexec_crash_loaded
kdump_sysconfig=/etc/sysconfig/kdump

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
# RhelExtraSettings()
#
#######################################################################

RhelExtraSettings(){

    LogMsg "Adding extra kdump parameters(Rhel)..."
    echo "Adding extra kdump parameters (Rhel)..." >> summary.log

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
    echo "Configuring kdump (Rhel)..." >> summary.log
    sed -i '/^path/ s/path/#path/g' $kdump_conf
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to comment path in /etc/kdump.conf. Probably kdump is not installed."
        echo "ERROR: Failed to comment path in /etc/kdump.conf. Probably kdump is not installed." >> summary.log
        UpdateTestState "TestAborted"
        exit 2
    else
        echo path $dump_path >> $kdump_conf
        LogMsg "Success: Updated the path to /var/crash."
        echo "Success: Updated the path to /var/crash." >> summary.log
    fi  

    sed -i '/^default/ s/default/#default/g' $kdump_conf
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to comment default behaviour in /etc/kdump_conf. Probably kdump is not installed."
        echo "ERROR: Failed to comment default behaviour in /etc/kdump.conf. Probably kdump is not installed." >> summary.log
        UpdateTestState "TestAborted"
        exit 2
    else
        echo 'default reboot' >>  $kdump_conf
        LogMsg "Success: Updated the default behaviour to reboot."
        echo "Success: Updated the default behaviour to reboot." >> summary.log
    fi 

    if [[ -z "$os_RELEASE" ]]; then
        GetOSVersion
    fi

    if [[ $os_RELEASE =~ ^5.* ]] || [[ $os_RELEASE =~ ^6.[0-2] ]] ; then
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
            echo "FAILED: Could not set the new crashkernel value in /etc/default/grub." >> ~/summary.log
            UpdateTestState "TestAborted"
            exit 2
        else
            LogMsg "Success: updated the crashkernel value to: $crashkernel."
            echo "Success: updated the crashkernel value to: $crashkernel." >> ~/summary.log    
        fi
        grub2-mkconfig -o /boot/grub2/grub.cfg
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
                echo "ERROR: Could not set the new crashkernel value." >> ~/summary.log
                UpdateTestState "TestAborted"
                exit 2
            else
                LogMsg "Success: updated the crashkernel value to: $crashkernel."
                echo "Success: updated the crashkernel value to: $crashkernel." >> ~/summary.log   
            fi
        fi
    fi

    # Enable kdump service
    LogMsg "Enabling kdump"
    echo "Enabling kdump..." >> summary.log
    chkconfig kdump on --level 35
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to enable kdump."
        echo "ERROR: Failed to enable kdump." >> ~/summary.log
        UpdateTestState "TestAborted"
        exit 1
    else
        LogMsg "Success: kdump enabled."
        echo "Success: kdump enabled." >> ~/summary.log     
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
    echo "Configuring kdump (Sles)..." >> summary.log

    if [[ -d /boot/grub2 ]]; then
        if grep -iq "crashkernel=" /etc/default/grub
        then
            sed -i "s/crashkernel=218M-:109M/crashkernel=$crashkernel/g" /etc/default/grub
        else
            sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"crashkernel=$crashkernel /g" /etc/default/grub
        fi
        grep -iq "crashkernel=$crashkernel" /etc/default/grub
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Could not set the new crashkernel value in /etc/default/grub."
            echo "ERROR: Could not set the new crashkernel value in /etc/default/grub." >> ~/summary.log
            UpdateTestState "TestAborted"
            exit 2
        else
            LogMsg "Success: updated the crashkernel value to: $crashkernel."
            echo "Success: updated the crashkernel value to: $crashkernel." >> ~/summary.log   
        fi
        grub2-mkconfig -o /boot/grub2/grub.cfg
    fi

    if [[ -d /boot/grub ]]; then
        if grep -iq "crashkernel=" /boot/grub/menu.lst
        then
            sed -i "s/crashkernel=218M-:109M/crashkernel=$crashkernel/g" /boot/grub/menu.lst
        else
            sed -i "s/rootdelay=300/rootdelay=300 crashkernel=$crashkernel/g" /boot/grub/menu.lst
        fi
        grep -iq "crashkernel=$crashkernel" /boot/grub/menu.lst
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Could not configure set the new crashkernel value in /etc/default/grub."
            echo "ERROR: Could not configure set the new crashkernel value in /etc/default/grub." >> ~/summary.log
            UpdateTestState "TestAborted"
            exit 2
        else
            LogMsg "Success: updated the crashkernel value to: $crashkernel."
            echo "Success: updated the crashkernel value to: $crashkernel." >> ~/summary.log   
        fi
    fi

    LogMsg "Enabling kdump"
    echo "Enabling kdump" >> ~/summary.log
    chkconfig boot.kdump on
    if [ $? -ne 0 ]; then
        systemctl enable kdump.service
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: FAILED to enable kdump."
            echo "ERROR: FAILED to enable kdump." >> ~/summary.log
            UpdateTestState "TestAborted"
            exit 1
        else
            LogMsg "Success: kdump enabled."
            echo "Success: kdump enabled." >> ~/summary.log
        fi
    else
        LogMsg "Success: kdump enabled."
        echo "Success: kdump enabled." >> ~/summary.log        
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
    echo "Configuring kdump (Ubuntu)..." >> summary.log
    sed -i 's/USE_KDUMP=0/USE_KDUMP=1/g' /etc/default/kdump-tools
    grep -q "USE_KDUMP=1" /etc/default/kdump-tools
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: kdump-tools are not existent or cannot be modified."
        echo "ERROR: kdump-tools are not existent or cannot be modified." >> summary.log
        UpdateTestState "TestAborted"
        exit 1    
    fi
    sed -i "s/crashkernel=\S*/crashkernel=$crashkernel/g" /boot/grub/grub.cfg
    grep -q "crashkernel=$crashkernel" /boot/grub/grub.cfg
    if [ $? -ne 0 ]; then
        LogMsg "WARNING: Could not configure set the new crashkernel value in /etc/default/grub. Maybe the default value is wrong. We try other configure."
        echo "WARNING: Could not configure set the new crashkernel value in /etc/default/grub. Maybe the default value is wrong. We try other configure." >> summary.log

        sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"crashkernel=$crashkernel /g" /etc/default/grub
        grep -q "crashkernel=$crashkernel" /etc/default/grub
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Failed to configure the new crashkernel."
            echo "ERROR: Failed to configure the new crashkernel." >> summary.log
            UpdateTestState "TestAborted"
            exit 2
        else
            update-grub
            LogMsg "Succesfully updated the crashkernel value to: $crashkernel."
            echo "Succesfully updated the crashkernel value to: $crashkernel." >> summary.log
        fi    
    else
        LogMsg "Success: updated the crashkernel value to: $crashkernel."
        echo "Success: updated the crashkernel value to: $crashkernel." >> summary.log
    fi
    sed -i 's/LOAD_KEXEC=true/LOAD_KEXEC=false/g' /etc/default/kexec

}

#######################################################################
#
# Main script body
#
#######################################################################
UpdateTestState $ICA_TESTRUNNING
crashkernel=$1

cd ~
# Delete any old summary.log file
if [ -e ~/summary.log ]; then
    rm -f ~/summary.log
fi

touch ~/summary.log

dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

#
# Checking the negotiated VMBus version 
#
vmbus_string=`dmesg | grep "Vmbus version:3.0"`

if [ "$vmbus_string" = "" ]; then
    LogMsg "WARNING: Negotiated VMBus version is not 3.0. Kernel might be old or patches not included."
    LogMsg "Test will continue but it might not work properly."
    echo "WARNING: Full support for kdump is not present, test execution might not work as expected" >> ~/summary.log
fi

#
# Configure kdump - this has distro specific behaviour
#
distro=`LinuxRelease`
case $distro in
    "CENTOS" | "RHEL")
        ConfigRhel
    ;;
    "UBUNTU")
        if [ "$crashkernel" == "auto" ]; then
            LogMsg "WARNING: crashkernel=auto doesn't work for Ubuntu. Please use this pattern: crashkernel=X@Y."
            echo "WARNING: crashkernel=auto doesn't work for Ubuntu. Please use this pattern: crashkernel=X@Y." >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
            exit 2
        else
            ConfigUbuntu
        fi    
    ;;
    "SLES")
        if [ "$crashkernel" == "auto" ]; then
            LogMsg "WARNING: crashkernel=auto doesn't work for SLES. Please use this pattern: crashkernel=X@Y."
            echo "WARNING: crashkernel=auto doesn't work for SLES. Please use this pattern: crashkernel=X@Y." >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
            exit 2
        else    
            ConfigSles
        fi
    ;;
     *)
        msg="WARNING: Distro '${distro}' not supported, defaulting to RedHat"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        ConfigRhel
    ;; 
esac

# Cleaning up any previous crash dump files
mkdir -p /var/crash
rm -rf /var/crash/*