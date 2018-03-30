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

########################################################################
#
# Description:
#
# This script contains all SR-IOV related functions that are used
# in the SR-IOV test suite.
#
# iperf3 3.1.x or newer is required for the output logging features
#
########################################################################

# iperf3 download location
iperf3_version=3.2
iperf3_url=https://github.com/esnet/iperf/archive/$iperf3_version.tar.gz

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Source constants file and initialize most common variables
UtilsInit

# In case of error
case $? in
    0)
        # Do nothing
        ;;
    1)
        LogMsg "ERROR: Unable to cd to $LIS_HOME. Aborting..."
        UpdateSummary "ERROR: Unable to cd to $LIS_HOME. Aborting..."
        SetTestStateAborted
        exit 3
        ;;
    2)
        LogMsg "ERROR: Unable to use test state file. Aborting..."
        UpdateSummary "ERROR: Unable to use test state file. Aborting..."
        # Need to wait for test timeout to kick in
        sleep 60
        echo "TestAborted" > state.txt
        exit 4
        ;;
    3)
        LogMsg "ERROR: unable to source constants file. Aborting..."
        UpdateSummary "ERROR: unable to source constants file"
        SetTestStateAborted
        exit 5
        ;;
    *)
        # Should not happen
        LogMsg "ERROR: UtilsInit returned an unknown error. Aborting..."
        UpdateSummary "ERROR: UtilsInit returned an unknown error. Aborting..."
        SetTestStateAborted
        exit 6
        ;;
esac

# Declare global variables
declare -i vfCount

#
# VerifyVF - check if the VF driver is use
#
VerifyVF()
{
    msg="ERROR: Failed to install pciutils"

    # Check for pciutils. If it's not on the system, install it
    lspci --version
    if [ $? -ne 0 ]; then
        LogMsg "INFO: pciutils not found. Trying to install it"

        GetDistro
        case "$DISTRO" in
            suse*)
                zypper --non-interactive in pciutils
                if [ $? -ne 0 ]; then
                    LogMsg "$msg"
                    UpdateSummary "$msg"
                    SetTestStateFailed
                    exit 1
                fi
            ;;

            ubuntu*|debian*)
                apt update
                apt install pciutils -y
                if [ $? -ne 0 ]; then
                    LogMsg "$msg"
                    UpdateSummary "$msg"
                    SetTestStateFailed
                    exit 1
                fi
            ;;

            redhat*|centos*)
                yum install pciutils -y
                if [ $? -ne 0 ]; then
                    LogMsg "$msg"
                    UpdateSummary "$msg"
                    SetTestStateFailed
                    exit 1
                fi
            ;;

            *)
                msg="ERROR: OS Version not supported in VerifyVF!"
                LogMsg "$msg"
                UpdateSummary "$msg"
                SetTestStateFailed
                exit 1
            ;;
        esac
    fi

    # Using lsmod command, verify if driver is loaded
    lsmod | grep 'mlx4_core\|mlx4_en\|ixgbevf'
    if [ $? -ne 0 ]; then
        msg="ERROR: Neither mlx4_core\mlx4_en or ixgbevf drivers are in use!"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    fi

    # Using the lspci command, verify if NIC has SR-IOV support
    lspci -vvv | grep 'mlx4_core\|mlx4_en\|ixgbevf'
    if [ $? -ne 0 ]; then
        msg="No NIC with SR-IOV support found!"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    fi

    interface=$(ls /sys/class/net/ | grep -v 'eth0\|eth1\|lo' | head -1)
    ifconfig -a | grep $interface
        if [ $? -ne 0 ]; then
        msg="ERROR: VF device, $interface , was not found!"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    fi

    return 0
}

#
# Check_SRIOV_Parameters - check if the needed parameters for SR-IOV
# testing are present in constants.sh
#
Check_SRIOV_Parameters()
{
    # Parameter provided in constants file
    declare -a STATIC_IPS=()

    if [ "${VF_IP1:-UNDEFINED}" = "UNDEFINED" ]; then
        msg="ERROR: The test parameter VF_IP1 is not defined in constants file. Will try to set addresses via dhcp"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateAborted
        exit 1
    fi

    if [ "${VF_IP2:-UNDEFINED}" = "UNDEFINED" ]; then
        msg="ERROR: The test parameter VF_IP2 is not defined in constants file. No network connectivity test will be performed."
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateAborted
        exit 1
    fi

    IFS=',' read -a networkType <<< "$NIC"
    if [ "${NETMASK:-UNDEFINED}" = "UNDEFINED" ]; then
        msg="ERROR: The test parameter NETMASK is not defined in constants file . Defaulting to 255.255.255.0"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateAborted
        exit 1
    fi

    if [ "${sshKey:-UNDEFINED}" = "UNDEFINED" ]; then
        msg="ERROR: The test parameter sshKey is not defined in ${LIS_CONSTANTS_FILE}"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateAborted
        exit 1
    fi

    if [ "${REMOTE_USER:-UNDEFINED}" = "UNDEFINED" ]; then
        msg="ERROR: The test parameter REMOTE_USER is not defined in ${LIS_CONSTANTS_FILE}"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateAborted
        exit 1
    fi

    return 0
}

#
# Create1Gfile - it creates a 1GB file that will be sent between VMs as part of testing
#
Create1Gfile()
{
    output_file=large_file

    if [ "${ZERO_FILE:-UNDEFINED}" = "UNDEFINED" ]; then
        file_source=/dev/urandom
    else
        file_source=/dev/zero
    fi

    if [ -d "$HOME"/"$output_file" ]; then
        rm -rf "$HOME"/"$output_file"
    fi

    if [ -e "$HOME"/"$output_file" ]; then
        rm -f "$HOME"/"$output_file"
    fi

    dd if=$file_source of="$HOME"/"$output_file" bs=1 count=0 seek=1G
    if [ 0 -ne $? ]; then
        msg="ERROR: Unable to create file $output_file in $HOME"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    fi

    LogMsg "Successfully created $output_file"
    return 0
}

#
# ConfigureVF - will set the given VF_IP(s) (from constants file)
# for each vf present 
#
ConfigureVF()
{
    vfCount=$(find /sys/devices -name net -a -ipath '*vmbus*' | grep pci | wc -l)
    if [ $vfCount -eq 0 ]; then
        msg="ERROR: No VFs are present in the Guest VM!"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    fi

    __iterator=1
    __ipIterator=1
    LogMsg "Iterator: $__iterator"
    # LogMsg "vfCount: $vfCount"

    # Set static IPs for each vf created
    while [ $__iterator -le $vfCount ]; do
        LogMsg "Network config will start"

        # Extract vfIP value from constants.sh
        staticIP=$(cat constants.sh | grep IP$__ipIterator | head -1 | tr = " " | awk '{print $2}')

        if is_ubuntu ; then
            __file_path="/etc/network/interfaces"
            # Change /etc/network/interfaces 
            echo "auto eth$__iterator" >> $__file_path
            echo "iface eth$__iterator inet static" >> $__file_path
            echo "address $staticIP" >> $__file_path
            echo "netmask $NETMASK" >> $__file_path
            ifup eth$__iterator

        elif is_suse ; then
            __file_path="/etc/sysconfig/network/ifcfg-eth$__iterator"
            rm -f $__file_path

            # Replace the BOOTPROTO, IPADDR and NETMASK values found in ifcfg file
            echo "DEVICE=eth$__iterator" >> $__file_path
            echo "NAME=eth$__iterator" >> $__file_path
            echo "BOOTPROTO=static" >> $__file_path
            echo "IPADDR=$staticIP" >> $__file_path
            echo "NETMASK=$NETMASK" >> $__file_path
            echo "STARTMODE=auto" >> $__file_path

            ifup eth$__iterator

        elif is_fedora ; then
            __file_path="/etc/sysconfig/network-scripts/ifcfg-eth$__iterator"
            rm -f $__file_path

            # Replace the BOOTPROTO, IPADDR and NETMASK values found in ifcfg file
            echo "DEVICE=eth$__iterator" >> $__file_path
            echo "NAME=eth$__iterator" >> $__file_path
            echo "BOOTPROTO=static" >> $__file_path
            echo "IPADDR=$staticIP" >> $__file_path
            echo "NETMASK=$NETMASK" >> $__file_path
            echo "ONBOOT=yes" >> $__file_path

            ifup eth$__iterator
        fi
        LogMsg "Network config file path: $__file_path"

        __ipIterator=$(($__ipIterator + 2))
        : $((__iterator++))
    done

    return 0
}

#
# InstallDependencies - install wget and iperf3 if not present
#
InstallDependencies()
{
    msg="ERROR: Failed to install wget"

    # Enable broadcast listening
    echo 0 >/proc/sys/net/ipv4/icmp_echo_ignore_broadcasts

    GetDistro
    case "$DISTRO" in
        suse*)
            # Disable firewall
            rcSuSEfirewall2 stop

            # Check wget
            wget -V > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                zypper --non-interactive in wget
                if [ $? -ne 0 ]; then
                    LogMsg "$msg"
                    UpdateSummary "$msg"
                    SetTestStateFailed
                    exit 1
                fi
            fi
        ;;

        ubuntu*|debian*)
            # Disable firewall
            ufw disable

            # Check wget
            wget -V > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                apt update
                apt install -y wget
                if [ $? -ne 0 ]; then
                    LogMsg "$msg"
                    UpdateSummary "$msg"
                    SetTestStateFailed
                    exit 1
                fi
            fi
        ;;

        redhat*|centos*)
            # Disable firewall
            service firewalld stop

            # Check wget 
            wget -V > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                yum install wget -y
                if [ $? -ne 0 ]; then
                    LogMsg "$msg"
                    UpdateSummary "$msg"
                    SetTestStateFailed
                    exit 1
                fi
            fi
        ;;

        *)
            msg="ERROR: OS Version not supported in InstallDependencies!"
            LogMsg "$msg"
            UpdateSummary "$msg"
            SetTestStateFailed
            exit 1
        ;;
    esac

    # Check if iPerf3 is already installed
    iperf3 -v > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        wget $iperf3_url
        if [ $? -ne 0 ]; then
            msg="ERROR: Failed to download iperf3 from $iperf3_url"
            LogMsg "$msg"
            UpdateSummary "$msg"
            SetTestStateFailed
            exit 1
        fi

        tar xf $iperf3_version.tar.gz
        pushd iperf-$iperf3_version

        ./configure; make; make install
        # update shared libraries links
        ldconfig
        popd

        iperf3 -v > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            msg="ERROR: Failed to install iperf3"
            LogMsg "$msg"
            UpdateSummary "$msg"
            SetTestStateFailed
            exit 1
        fi
    fi

    return 0
}
