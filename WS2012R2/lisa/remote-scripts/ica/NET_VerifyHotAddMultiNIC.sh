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
#
# AddedNic ($ethCount)
#
function AddedNic
{
    ethCount=$1

    echo "Info : Checking the ethCount"
    if [ $ethCount -ne 2 ]; then
        echo "Error: VM should have two NICs now"
        exit 1
    fi

    #
    # Bring the new NIC online
    #
    echo "os_VENDOR=$os_VENDOR"
    if [[ "$os_VENDOR" == "Red Hat" ]] || \
       [[ "$os_VENDOR" == "CentOS" ]]; then
            echo "Info : Creating ifcfg-eth1"
            cp /etc/sysconfig/network-scripts/ifcfg-eth0 /etc/sysconfig/network-scripts/ifcfg-eth1
            sed -i -- 's/eth0/eth1/g' "/etc/sysconfig/network-scripts/ifcfg-eth1"
    elif [ "$os_VENDOR" == "SUSE LINUX" ]; then
            echo "Info : Creating ifcfg-eth1"
            cp /etc/sysconfig/network/ifcfg-eth0 /etc/sysconfig/network/ifcfg-eth1
            sed -i -- 's/eth0/eth1/g' /etc/sysconfig/network/ifcfg-eth1
    elif [ "$os_VENDOR" == "Ubuntu" ]; then
            echo "auto eth1" >> /etc/network/interfaces
            echo "iface eth1 inet dhcp" >> /etc/network/interfaces
    else
        echo "Error: Linux Distro not supported!"
        exit 1
    fi

    echo "Info : Bringing up eth1"
    ifup eth1

    #
    # Verify the new NIC received an IP v4 address
    #
    echo "Info : Verify the new NIC has an IPv4 address"
    ifconfig eth1 | grep -s "inet " > /dev/null
    if [ $? -ne 0 ]; then
        echo "Error: eth1 was not assigned an IPv4 address"
        exit 1
    fi

    echo "Info : eth1 is up"
    echo "Info: NIC Hot Add test passed"
}

#
# RemovedNic ($ethCount)
#
function RemovedNic
{
    ethCount=$1
    if [ $ethCount -ne 1 ]; then
        echo "Error: there are more than one eth devices"
        exit 1
    fi

    # Clean up files & check linux log for errors
    if [[ "$os_VENDOR" == "Red Hat" ]] || \
       [[ "$os_VENDOR" == "CentOS" ]]; then
            echo "Info: Cleaning up RHEL/CentOS"
            rm -f /etc/sysconfig/network-scripts/ifcfg-eth1
            cat /var/log/messages | grep "unable to close device (ret -110)"
            if [ $? -eq 0 ]; then
                echo "Error: /var/log/messages reported netvsc throwed errors"
            fi
    elif [ "$os_VENDOR" == "SUSE LINUX" ]; then
            rm -f /etc/sysconfig/network/ifcfg-eth1
            cat /var/log/messages | grep "unable to close device (ret -110)"
            if [ $? -eq 0 ]; then
                echo "Error: /var/log/messages reported netvsc throwed errors"
            fi
    elif [ "$os_VENDOR" == "Ubuntu" ]; then
            sed -i -e "/auto eth1/d" /etc/network/interfaces
            sed -i -e "/iface eth1 inet dhcp/d" /etc/network/interfaces
            cat /var/log/syslog | grep "unable to close device (ret -110)"
            if [ $? -eq 0 ]; then
                echo "Error: /var/log/syslog reported netvsc throwed errors"
            fi
    else
        echo "Error: Linux Distro not supported!"
        exit 1
    fi
}

#######################################################################
#
# Main script body
#
#######################################################################

#
# Make sure the argument count is correct
#
if [ $# -ne 1 ]; then
    echo "Error: Expected one argument of 'added' or 'removed'"
    echo "       $# arguments were provided"
    exit 1
fi

#
# Determine how many eth devices the OS sees
#
ethCount=$(ifconfig -a | grep "^eth" | wc -l)
echo "ethCount = ${ethCount}"

#
# Get data about Linux Distribution
#
# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    exit 2
}

GetOSVersion

#
# Set ethCount based on the value of $1
#
case "$1" in
added)
    AddedNic $ethCount
    ;;
removed)
    RemovedNic $ethCount
    ;;
*)
    echo "Error: Unknown argument of $1"
    exit 1
    ;;
esac

exit 0
