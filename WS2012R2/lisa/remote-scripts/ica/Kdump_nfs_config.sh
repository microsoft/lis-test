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
# ConfigRhel()
#
#######################################################################
ConfigRhel()
{
    # Modifying kdump.conf settings
    LogMsg "Configuring nfs (Rhel)..."
    UpdateSummary "Configuring kdump (Rhel)..."
    yum install -y nfs-utils
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to install nfs."
        UpdateSummary "ERROR: Failed to configure nfs."
        SetTestStateAborted
        exit 1
    fi

    grep "/mnt \*" /etc/exports
    if [ $? -ne 0 ]; then
        echo "/mnt *(rw,no_root_squash,sync)" >> /etc/exports
    fi

    service nfs restart
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to restart nfs service."
        UpdateSummary "ERROR: Failed to restart nfs service."
        SetTestStateAborted
        exit 1
    fi

    #disable firewall in case it is running
    ls -l /sbin/init | grep systemd
    if [ $? -ne 0 ]; then
        service iptables stop
    else
        systemctl stop firewalld
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
    zypper --non-interactive install nfs-kernel-server
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to install nfs."
        UpdateSummary "ERROR: Failed to configure nfs."
        SetTestStateAborted
        exit 1
    fi

    grep "/mnt \*" /etc/exports
    if [ $? -ne 0 ]; then
        echo "/mnt *(rw,no_root_squash,sync)" >> /etc/exports
    fi

    systemctl enable rpcbind.service
    systemctl restart rpcbind.service
    systemctl enable nfsserver.service
    systemctl restart nfsserver.service
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to restart nfs service."
        UpdateSummary "ERROR: Failed to restart nfs service."
        SetTestStateAborted
        exit 1
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
    apt-get update
    apt-get install -y nfs-kernel-server
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to install nfs."
        UpdateSummary "ERROR: Failed to configure nfs."
        SetTestStateAborted
        exit 1
    fi

    grep "/mnt \*" /etc/exports
    if [ $? -ne 0 ]; then
        echo "/mnt *(rw,no_root_squash,sync)" >> /etc/exports
    fi

    service nfs-kernel-server restart
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to restart nfs service."
        UpdateSummary "ERROR: Failed to restart nfs service."
        SetTestStateAborted
        exit 1
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
GetDistro

case $DISTRO in
    centos* | redhat* | fedora*)
        ConfigRhel
    ;;
    ubuntu*)
        ConfigUbuntu
    ;;
    suse*)
        ConfigSles
    ;;
     *)
        msg="WARNING: Distro '${distro}' not supported, defaulting to RedHat"
        LogMsg "${msg}"
        UpdateSummary "${msg}"
        ConfigRhel
    ;;
esac

rm -rf /mnt/*
SetTestStateCompleted
