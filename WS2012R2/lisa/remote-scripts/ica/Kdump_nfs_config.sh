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
# ConfigRhel()
#
#######################################################################
ConfigRhel()
{
    # Modifying kdump.conf settings
    LogMsg "Configuring nfs (Rhel)..."
    echo "Configuring kdump (Rhel)..." >> summary.log
    yum install -y nfs-utils
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to install nfs."
        echo "ERROR: Failed to configure nfs." >> summary.log
        UpdateTestState "TestAborted"
        exit 2
    fi

    echo "/mnt *(rw,no_root_squash,sync)" >> /etc/exports
    service nfs restart
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to restart nfs service."
        echo "ERROR: Failed to restart nfs service." >> summary.log
        UpdateTestState "TestAborted"
        exit 2
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
    zypper --non-interactive install nfs-kernel-server
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to install nfs."
        echo "ERROR: Failed to configure nfs." >> summary.log
        UpdateTestState "TestAborted"
        exit 2
    fi

    echo "/mnt *(rw,no_root_squash,sync)" >> /etc/exports
    systemctl enable rpcbind.service
    systemctl restart rpcbind.service
    systemctl enable nfsserver.service
    systemctl restart nfsserver.service
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to restart nfs service."
        echo "ERROR: Failed to restart nfs service." >> summary.log
        UpdateTestState "TestAborted"
        exit 2
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
    apt-get install -y nfs-kernel-server
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to install nfs."
        echo "ERROR: Failed to configure nfs." >> summary.log
        UpdateTestState "TestAborted"
        exit 2
    fi

    echo "/mnt *(rw,no_root_squash,sync)" >> /etc/exports
    service nfs-kernel-server restart
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to restart nfs service."
        echo "ERROR: Failed to restart nfs service." >> summary.log
        UpdateTestState "TestAborted"
        exit 2
    fi
}

#######################################################################
#
# Main script body
#
#######################################################################
UpdateTestState $ICA_TESTRUNNING

cd ~
# Delete any old summary.log file
if [ -e ~/summary.log ]; then
    rm -f ~/summary.log
fi

touch ~/summary.log

#
# Configure kdump - this has distro specific behaviour
#
distro=`LinuxRelease`
case $distro in
    "CENTOS" | "RHEL")
        ConfigRhel
    ;;
    "UBUNTU")
        ConfigUbuntu
    ;;
    "SLES")
        ConfigSles
    ;;
     *)
        msg="WARNING: Distro '${distro}' not supported, defaulting to RedHat"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        ConfigRhel
    ;;
esac
UpdateTestState "TestCompleted"
