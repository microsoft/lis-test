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

#######################################################################
#
# perf_ntttcp_server.sh
#
# Description:
#     A multiple-thread based Linux network throughput benchmark tool.
#     For the test to run you have to install ntttcp-for-linux from github: https://github.com/Microsoft/ntttcp-for-linux
#
# Requirements:
#   - GCC installed
#
#Example run
#
#To measure the network performance between two multi-core serves running SLES 12, NODE1 (192.168.4.1) and NODE2 (192.168.4.2), connected via a 40 GigE connection.
#
#On NODE1 (the receiver), run: ./ntttcp -r
#######################################################################

ICA_TESTRUNNING="TestRunning"
ICA_NTTTCPRUNNING="NtttcpRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"

LogMsg() {
    echo `date "+%a %b %d %T %Y"` ": ${1}"
}

UpdateTestState() {
    echo $1 > ~/state.txt
}

#######################################################################
#
# Main script body
#
#######################################################################
cd ~
UpdateTestState $ICA_TESTRUNNING
LogMsg "Starting running the script"

#
# Delete any old summary.log file
#
LogMsg "Cleaning up old summary.log"
if [ -e ~/summary.log ]; then
    rm -f ~/summary.log
fi

touch ~/summary.log

# Convert eol
dos2unix utils.sh
# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}
dos2unix perf_utils.sh
# Source perf_utils.sh
. perf_utils.sh || {
    echo "Error: unable to source perf_utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Source constants file and initialize most common variables
UtilsInit
# In case of error
case $? in
    0)
        # do nothing, init succeeded
        ;;
    1)
        LogMsg "Unable to cd to $LIS_HOME. Aborting..."
        UpdateSummary "Unable to cd to $LIS_HOME. Aborting..."
        SetTestStateAborted
        exit 3
        ;;
    2)
        LogMsg "Unable to use test state file. Aborting..."
        UpdateSummary "Unable to use test state file. Aborting..."
        # need to wait for test timeout to kick in
        # hailmary try to update teststate
        sleep 60
        echo "TestAborted" > state.txt
        exit 4
        ;;
    3)
        LogMsg "Error: unable to source constants file. Aborting..."
        UpdateSummary "Error: unable to source constants file"
        SetTestStateAborted
        exit 5
        ;;
    *)
        # should not happen
        LogMsg "UtilsInit returned an unknown error. Aborting..."
        UpdateSummary "UtilsInit returned an unknown error. Aborting..."
        SetTestStateAborted
        exit 6
        ;;
esac

# Make sure the required test parameters are defined
# Parameter provided in constants file
#  ipv4 is the IP Address of the interface used to communicate with the VM, which needs to remain unchanged
#  it is not touched during this test (no dhcp or static ip assigned to it)
if [ "${STATIC_IP2:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter STATIC_IP2 is not defined in constants file! Make sure you are using the latest LIS code."
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
    exit 30
else
    CheckIP "$STATIC_IP2"
    if [ 0 -ne $? ]; then
        msg="Test parameter STATIC_IP2 = $STATIC_IP2 is not a valid IP Address"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateAborted
        exit 10
    fi
fi

#Get test synthetic interface
declare __iface_ignore
# Get the interface associated with the given ipv4
__iface_ignore=$(ip -o addr show | grep "$STATIC_IP2" | cut -d ' ' -f2)
# Retrieve synthetic network interfaces
GetSynthNetInterfaces
if [ 0 -ne $? ]; then
    msg="No synthetic network interfaces found"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi
# Remove interface if present
SYNTH_NET_INTERFACES=(${SYNTH_NET_INTERFACES[@]/$__iface_ignore/})
if [ ${#SYNTH_NET_INTERFACES[@]} -eq 0 ]; then
    msg="The only synthetic interface is the one which LIS uses to send files/commands to the VM."
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
    exit 10
fi

# SRIOV setup (transparent VF)
if [ "${SRIOV}" = "yes" ]; then
    # Check if the SR-IOV driver is in use
    VerifyVF
    if [ $? -ne 0 ]; then
        msg="ERROR: VF is not loaded! Make sure you are using compatible hardware"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi
    __vf_ignore='enP2p0s2'
    SYNTH_NET_INTERFACES=(${SYNTH_NET_INTERFACES[@]/$__vf_ignore/})
fi

LogMsg "Found ${#SYNTH_NET_INTERFACES[@]} synthetic interface(s): ${SYNTH_NET_INTERFACES[*]} in VM"
# Test interfaces
declare -i __iterator
for __iterator in "${!SYNTH_NET_INTERFACES[@]}"; do
    ip link show "${SYNTH_NET_INTERFACES[$__iterator]}" >/dev/null 2>&1
    if [ 0 -ne $? ]; then
        msg="Invalid synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 20
    fi
done

# Config static IP - with transparent-vf it is not necessary to run bondvf.sh
if [[ "${SRIOV}" = "yes" ]] || [[ "${SRIOV}" = "no" ]]; then
    #Config static ip on the client side.
    config_staticip ${SERVER_IP} ${NETMASK}
    if [ $? -ne 0 ]; then
        echo "ERROR: Function config_staticip failed."
        LogMsg "ERROR: Function config_staticip failed."
        UpdateTestState $ICA_TESTABORTED
    fi
fi
# Config static IP - using bondvf.sh
if [ "${SRIOV}" = "bond" ]; then
    # Check if the SR-IOV driver is in use
    VerifyVF
    if [ $? -ne 0 ]; then
        msg="ERROR: VF is not loaded! Make sure you are using compatible hardware"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi
    # Run bondvf.sh platform specific script
    RunBondingScript
    bondCount=$?
    if [ $bondCount -eq 99 ]; then
        msg="ERROR: Running the bonding script failed. Please double check if it is present on the system"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    else
        LogMsg "BondCount returned by SR-IOV_Utils: $bondCount"
    fi
    # Set static IP to the bond
    perf_ConfigureBond ${SERVER_IP}
    if [ $? -ne 0 ]; then
        msg="ERROR: Could not set a static IP to the bond!"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi
fi

# Flushing firewall rules
iptables -F
if [ $? -ne 0 ]; then
    msg="ERROR: Failed to flush iptables rules. Continuing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi
ip6tables -F
if [ $? -ne 0 ]; then
    msg="ERROR: Failed to flush ip6tables rules. Continuing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

#Check distro
GetDistro
case "$DISTRO" in
debian*|ubuntu*)
    disable_firewall
    if [[ $? -ne 0 ]]; then
        msg="ERROR: Unable to disable firewall.Exiting"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
    LogMsg "Installing dependency tools on Ubuntu"
    apt-get update && apt-get install build-essential git sysstat dstat -y
    if [ $? -ne 0 ]; then
        msg="ERROR: dependencies failed to install"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
    fi
    ;;
redhat_5|redhat_6|centos_6|centos_5)
    yum install -y bc sysstat dstat
    if [ $? -ne 0 ]; then
        msg="ERROR: dependencies failed to install"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
    fi
    LogMsg "Check irqbalance status on RHEL 5/6.x."
    service irqbalance status
    if [ $? -eq 3 ]; then
        LogMsg "Enabling irqbalance on Redhat 5/6.x"
        service irqbalance start
        if [ $? -ne 0 ]; then
            msg="ERROR: Failed to start irqbalance. Failing."
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        service irqbalance status
    fi
    disable_firewall
    if [[ $? -ne 0 ]]; then
        msg="ERROR: Unable to disable firewall.Exiting"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
    ;;
redhat_7|centos_7)
    yum install -y bc sysstat dstat
    if [ $? -ne 0 ]; then
        msg="ERROR: dependencies failed to install"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
    fi
    LogMsg "Check irqbalance status on RHEL 7.xx."
    systemctl status irqbalance
    if [ $? -eq 3 ]; then
        LogMsg "Enabling irqbalance on Redhat 7.x"
        systemctl enable irqbalance && systemctl start irqbalance
        if [ $? -ne 0 ]; then
            msg="ERROR: Failed to start irqbalance. Failing."
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        systemctl status irqbalance
    fi
    LogMsg "Check firewalld status on RHEL 7.xx."
    systemctl status firewalld
    if [ $? -ne 3 ]; then
        LogMsg "Disabling firewall on Redhat 7.x"
        systemctl stop firewalld && systemctl disable firewalld
        if [ $? -ne 0 ]; then
            msg="ERROR: Failed to turn off firewalld. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
    fi
    disable_firewall
    if [[ $? -ne 0 ]]; then
        msg="ERROR: Unable to disable firewall.Exiting"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
    ;;
suse_12)
    zypper -n in dstat sysstat gcc
    if [ $? -ne 0 ]; then
        msg="ERROR: dependencies failed to install"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
    fi
    LogMsg "Check iptables status on SLES 12"
    service SuSEfirewall2 status
    if [ $? -ne 3 ]; then
        service SuSEfirewall2 stop
        if [ $? -ne 0 ]; then
            msg="ERROR: Failed to stop iptables"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 85
        fi
        chkconfig SuSEfirewall2 off
        if [ $? -ne 0 ]; then
            msg="ERROR: Failed to turn off iptables. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
    fi
    ;;
esac

if [ $DISTRO -eq "suse_12" ]; then
    ldconfig
    if [ $? -ne 0 ]; then
        msg="Warning: Couldn't run ldconfig, there might be shared library errors"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
    fi
fi

#Apling performance parameters
setup_sysctl "$(declare -p sysctl_tcp_params)"
if [ $? -ne 0 ]; then
    echo "Unable to add performance parameters."
    LogMsg "Unable to add performance parameters."
    UpdateTestState $ICA_TESTABORTED
fi

setup_lagscope
if [ $? -ne 0 ]; then
    echo "Unable to compile lagscope."
    LogMsg "Unable to compile lagscope."
    UpdateTestState $ICA_TESTABORTED
fi

#Install NTTTCP for network throughput
setup_ntttcp
if [ $? -ne 0 ]; then
    echo "Unable to compile ntttcp-for-linux."
    LogMsg "Unable to compile ntttcp-for-linux."
    UpdateTestState $ICA_TESTABORTED
fi

LogMsg "Enlarging the system limit"
ulimit -n 20480
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to enlarged system limit"
    UpdateTestState $ICA_TESTABORTED
fi

mkdir /root/$log_folder

sleep 3
UpdateTestState $ICA_NTTTCPRUNNING
LogMsg "Ntttcp server instances are now ready to run"
