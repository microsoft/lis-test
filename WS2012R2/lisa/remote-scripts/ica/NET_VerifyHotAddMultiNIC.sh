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


expectedCount=0
declare os_VENDOR os_RELEASE os_UPDATE os_PACKAGE os_CODENAME

########################################################################
# Determine what OS is running
########################################################################
# GetOSVersion
function GetOSVersion {
    # Figure out which vendor we are
    if [[ -x "`which sw_vers 2>/dev/null`" ]]; then
        # OS/X
        os_VENDOR=`sw_vers -productName`
        os_RELEASE=`sw_vers -productVersion`
        os_UPDATE=${os_RELEASE##*.}
        os_RELEASE=${os_RELEASE%.*}
        os_PACKAGE=""
        if [[ "$os_RELEASE" =~ "10.7" ]]; then
            os_CODENAME="lion"
        elif [[ "$os_RELEASE" =~ "10.6" ]]; then
            os_CODENAME="snow leopard"
        elif [[ "$os_RELEASE" =~ "10.5" ]]; then
            os_CODENAME="leopard"
        elif [[ "$os_RELEASE" =~ "10.4" ]]; then
            os_CODENAME="tiger"
        elif [[ "$os_RELEASE" =~ "10.3" ]]; then
            os_CODENAME="panther"
        else
            os_CODENAME=""
        fi
    elif [[ -x $(which lsb_release 2>/dev/null) ]]; then
        os_VENDOR=$(lsb_release -i -s)
        os_RELEASE=$(lsb_release -r -s)
        os_UPDATE=""
        os_PACKAGE="rpm"
        if [[ "Debian,Ubuntu,LinuxMint" =~ $os_VENDOR ]]; then
            os_PACKAGE="deb"
        elif [[ "SUSE LINUX" =~ $os_VENDOR ]]; then
            lsb_release -d -s | grep -q openSUSE
            if [[ $? -eq 0 ]]; then
                os_VENDOR="openSUSE"
            fi
        elif [[ $os_VENDOR == "openSUSE project" ]]; then
            os_VENDOR="openSUSE"
        elif [[ $os_VENDOR =~ Red.*Hat ]]; then
            os_VENDOR="Red Hat"
        fi
        os_CODENAME=$(lsb_release -c -s)
    elif [[ -r /etc/redhat-release ]]; then
        # Red Hat Enterprise Linux Server release 5.5 (Tikanga)
        # Red Hat Enterprise Linux Server release 7.0 Beta (Maipo)
        # CentOS release 5.5 (Final)
        # CentOS Linux release 6.0 (Final)
        # Fedora release 16 (Verne)
        # XenServer release 6.2.0-70446c (xenenterprise)
        os_CODENAME=""
        for r in "Red Hat" CentOS Fedora XenServer; do
            os_VENDOR=$r
            if [[ -n "`grep \"$r\" /etc/redhat-release`" ]]; then
                ver=`sed -e 's/^.* \([0-9].*\) (\(.*\)).*$/\1\|\2/' /etc/redhat-release`
                os_CODENAME=${ver#*|}
                os_RELEASE=${ver%|*}
                os_UPDATE=${os_RELEASE##*.}
                os_RELEASE=${os_RELEASE%.*}
                break
            fi
            os_VENDOR=""
        done
        os_PACKAGE="rpm"
    elif [[ -r /etc/SuSE-release ]]; then
        for r in openSUSE "SUSE Linux"; do
            if [[ "$r" = "SUSE Linux" ]]; then
                os_VENDOR="SUSE LINUX"
            else
                os_VENDOR=$r
            fi

            if [[ -n "`grep \"$r\" /etc/SuSE-release`" ]]; then
                os_CODENAME=`grep "CODENAME = " /etc/SuSE-release | sed 's:.* = ::g'`
                os_RELEASE=`grep "VERSION = " /etc/SuSE-release | sed 's:.* = ::g'`
                os_UPDATE=`grep "PATCHLEVEL = " /etc/SuSE-release | sed 's:.* = ::g'`
                break
            fi
            os_VENDOR=""
        done
        os_PACKAGE="rpm"
    # If lsb_release is not installed, we should be able to detect Debian OS
    elif [[ -f /etc/debian_version ]] && [[ $(cat /proc/version) =~ "Debian" ]]; then
        os_VENDOR="Debian"
        os_PACKAGE="deb"
        os_CODENAME=$(awk '/VERSION=/' /etc/os-release | sed 's/VERSION=//' | sed -r 's/\"|\(|\)//g' | awk '{print $2}')
        os_RELEASE=$(awk '/VERSION_ID=/' /etc/os-release | sed 's/VERSION_ID=//' | sed 's/\"//g')
    fi
    export os_VENDOR os_RELEASE os_UPDATE os_PACKAGE os_CODENAME
}

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
GetOSVersion

#
# Set expectedCount based on the value of $1
#
case "$1" in
added)
    AddedNic $ethCount
    ;;
removed)
    RemovedNic $ethCount
    ;;
*)
    echo "Error: Unknow argument of $1"
    exit 1
    ;;
esac

exit 0
