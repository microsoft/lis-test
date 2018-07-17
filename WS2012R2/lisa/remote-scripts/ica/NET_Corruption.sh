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

function InstallNetcat {
    LogMsg "Installing netcat"
    SetTestStateRunning
    if [[ "$os_VENDOR" == "Red Hat" ]] || \
    [[ "$os_VENDOR" == "Fedora" ]] || \
    [[ "$os_VENDOR" == "CentOS" ]]; then
        yum install nc -y
    elif [ "$os_VENDOR" == "SUSE LINUX" ] || \
    [ "$os_VENDOR" == "SLE" ]; then
        zypper install -y netcat
    elif [ "$os_VENDOR" == "Ubuntu" ] || \
    [ "$os_VENDOR" == "Debian" ]; then
        apt-get install netcat -y
    else
        LogMsg "Warning: Linux Distro not supported!"
        UpdateSummary "Warning: Linux Distro not supported!"
    fi

    return 0
}


function ConfigInterface {
    AddNIC "eth1"
    sleep 5

    if [ $? -eq 0 ]; then
        ip_address=$(ip addr show $IFACE | grep "inet\b" | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | sed -n 2p)
        msg="Info : Successfully set IP address - ${ip_address}"
        LogMsg "${msg}"
        UpdateSummary "${msg}"
    else
        return 1
    fi

    # Disable reverse protocol filters
    sysctl -w net.ipv4.conf.all.rp_filter=0
    sysctl -w net.ipv4.conf.default.rp_filter=0
    sysctl -w net.ipv4.conf.eth0.rp_filter=0
    sysctl -w net.ipv4.conf.eth1.rp_filter=0
    sleep 2

    #Check if ethtool exist and install it if not
    VerifyIsEthtool

    # Disable tcp segmentation offload
    ethtool -K eth1 tso off
    ethtool -K eth1 gso off

    return 0
}


function AddNIC {
    ifName=$1

    #
    # Bring the new NIC online
    #
    LogMsg "os_VENDOR=$os_VENDOR"
    SetTestStateRunning
    if [[ "$os_VENDOR" == "Red Hat" ]] || \
    [[ "$os_VENDOR" == "Fedora" ]] || \
    [[ "$os_VENDOR" == "CentOS" ]]; then
        LogMsg "Info : Creating ifcfg-${ifName}"
        cp /etc/sysconfig/network-scripts/ifcfg-eth0 /etc/sysconfig/network-scripts/ifcfg-${ifName}
        sed -i -- "s/eth0/${ifName}/g" /etc/sysconfig/network-scripts/ifcfg-${ifName}
        sed -i -e "s/HWADDR/#HWADDR/" /etc/sysconfig/network-scripts/ifcfg-${ifName}
        sed -i -e "s/UUID/#UUID/" /etc/sysconfig/network-scripts/ifcfg-${ifName}
    elif [ "$os_VENDOR" == "SUSE LINUX" ] || \
    [ "$os_VENDOR" == "SUSE" ] || [ "$os_VENDOR" == "SLE" ]; then
        LogMsg "Info : Creating ifcfg-${ifName}"
        cp /etc/sysconfig/network/ifcfg-eth0 /etc/sysconfig/network/ifcfg-${ifName}
        sed -i -- "s/eth0/${ifName}/g" /etc/sysconfig/network/ifcfg-${ifName}
        sed -i -e "s/HWADDR/#HWADDR/" /etc/sysconfig/network/ifcfg-${ifName}
        sed -i -e "s/UUID/#UUID/" /etc/sysconfig/network/ifcfg-${ifName}
    elif [ "$os_VENDOR" == "Ubuntu" ] || \
    [ "$os_VENDOR" == "Debian" ]; then
        echo "auto ${ifName}" >> /etc/network/interfaces
        echo "iface ${ifName} inet dhcp" >> /etc/network/interfaces
    else
        LogMsg "Error: Linux Distro not supported!"
        UpdateSummary "Error: Linux Distro not supported!"
        SetTestStateAborted
        return 1
    fi

    # In some cases the interface does not receive an IP address from first try
    let max_attempts=3
    let counter=1
    let next_step=0
    while [ $next_step -eq 0 ];do
        LogMsg "Info : Bringing up ${ifName} on attempt ${counter}"
        UpdateSummary "Info : Bringing up ${ifName} on attempt ${counter}"
        ifup ${ifName}

        #
        # Verify the new NIC received an IPv4 address
        #
        LogMsg "Info : Verify the new NIC has an IPv4 address"
        # ifconfig ${ifName} | grep -s "inet " > /dev/null
        ip addr show ${ifName} | grep "inet\b" > /dev/null
        if [ $? -ne 0 ]; then
            LogMsg "Error: ${ifName} was not assigned an IPv4 address"
            if [ $counter -eq $max_attempts ]; then
                UpdateSummary "Error: ${ifName} was not assigned an IPv4 address"
                SetTestStateFailed
                return 1
            else
                let counter=$counter+1
            fi
        else
            let next_step=1
        fi
    done

    LogMsg "Info : ${ifName} is up"
    return 0
}


#######################################################################
#
# Main script body
#
#######################################################################
filePath=$1
port=$2

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    exit 2
}

UtilsInit

if [ "${FILE_SIZE:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="Error : Parameter FILE_SIZE was not found"
    LogMsg "${msg}"
    UpdateSummary "${msg}"
    SetTestStateAborted
    exit 30
fi

if [ "${CORRUPTION:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="Error : Parameter CORRUPTION was not found"
    LogMsg "${msg}"
    UpdateSummary "${msg}"
    SetTestStateAborted
    exit 30
fi

msg="Creating new file of size ${FILE_SIZE}"
LogMsg "${msg}"
UpdateSummary "${msg}"

dd if=/dev/urandom of=$filePath bs=$FILE_SIZE count=1

if [ 0 -ne $? ]; then
    msg="Unable to create file"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

GetOSVersion
ConfigInterface

# Disable iptables
iptables -F
iptables -X

InstallNetcat
if [ 0 -ne $? ]; then
    msg="Unable to install netcat"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

tc qdisc add dev eth1 root netem corrupt ${CORRUPTION}
if [ 0 -ne $? ]; then
    msg="Unable to set corruption to ${CORRUPTION}"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

UpdateSummary "Starting to listen on port 1234"
echo "nc -v -w 30 -l -p $port < $filePath &" > $3
chmod +x $3
LogMsg "Setup completed"
UpdateSummary "Setup completed"
exit 0
