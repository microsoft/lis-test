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
dos2unix perf_utils.sh
dos2unix SR-IOV_Utils.sh

. perf_utils.sh || {
    echo "Error: unable to source perf_utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Source perf_utils.sh
. SR-IOV_Utils.sh || {
    echo "Error: Unable to source SR-IOV_Utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

#Apling performance parameters
setup_sysctl
if [ $? -ne 0 ]; then
    echo "Unable to add performance parameters."
    LogMsg "Unable to add performance parameters."
    UpdateTestState $ICA_TESTABORTED
fi


iptables -F
ip6tables -F
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
    LogMsg "Installing sar on Ubuntu"
    apt-get install sysstat -y
    if [ $? -ne 0 ]; then
        msg="Error: sysstat failed to install"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 85
    fi
    apt-get install build-essential git -y
    if [ $? -ne 0 ]; then
        msg="Error: Build essential failed to install"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 85
    fi
    ;;
redhat_5|redhat_6|centos_6|centos_5)
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
    fi
    LogMsg "Check iptables status on RHEL"
    systemctl status firewalld
    if [ $? -ne 3 ]; then
        LogMsg "Disabling firewall on Redhat 7"
        systemctl disable firewalld
        if [ $? -ne 0 ]; then
            msg="Error: Failed to stop firewalld"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 85
        fi
        systemctl stop firewalld
        if [ $? -ne 0 ]; then
            msg="Error: Failed to turn off firewalld. Continuing"
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
    LogMsg "Check iptables status on SLES 12"
    service SuSEfirewall2 status
    if [ $? -ne 3 ]; then
        iptables -F;
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush iptables rules. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
        service SuSEfirewall2 stop
        if [ $? -ne 0 ]; then
            msg="Error: Failed to stop iptables"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 85
        fi
        chkconfig SuSEfirewall2 off
        if [ $? -ne 0 ]; then
            msg="Error: Failed to turn off iptables. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
    fi
    ;;
esac

LogMsg "Enlarging the system limit"
ulimit -n 30480
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to enlarged system limit"
    UpdateTestState $ICA_TESTABORTED
fi

#Install LAGSCOPE tool for latency
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

# Start ntttcp server instances
#
sleep 3
LogMsg "Ntttcp is ready to start in server mode."

UpdateTestState $ICA_NTTTCPRUNNING
LogMsg "Ntttcp server instances are now ready to run"
