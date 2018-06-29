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
# netperf_server.sh
#         This script starts netperf in server mode on dependency VM.
#######################################################################

ICA_TESTRUNNING="TestRunning"
ICA_NETPERFRUNNING="netperfRunning"
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

#Delete any old summary.log file
LogMsg "Cleaning up old summary.log"
if [ -e ~/summary.log ]; then
    rm -f ~/summary.log
fi
touch ~/summary.log

#Convert eol
dos2unix utils.sh

#Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 20
}

#Source constants file and initialize most common variables
UtilsInit

#In case of error
case $? in
    0)
        #do nothing, init succeeded
        ;;
    1)
        LogMsg "Unable to cd to $LIS_HOME. Aborting..."
        UpdateSummary "Unable to cd to $LIS_HOME. Aborting..."
        UpdateTestState $ICA_TESTABORTED
        exit 20
        ;;
    2)
        LogMsg "Unable to use test state file. Aborting..."
        UpdateSummary "Unable to use test state file. Aborting..."
        #need to wait for test timeout to kick in
        #hailmary try to update teststate
        sleep 60
        echo "TestAborted" > state.txt
        exit 20
        ;;
    3)
        LogMsg "Error: unable to source constants file. Aborting..."
        UpdateSummary "Error: unable to source constants file"
        UpdateTestState $ICA_TESTABORTED
        exit 20
        ;;
    *)
        #should not happen
        LogMsg "UtilsInit returned an unknown error. Aborting..."
        UpdateSummary "UtilsInit returned an unknown error. Aborting..."
        UpdateTestState $ICA_TESTABORTED
        exit 20
        ;;
esac

#Make sure the required test parameters are defined

if [ "${STATIC_IP2:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter STATIC_IP2 is not defined in constants file!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    UpdateTestState $ICA_TESTABORTED
    exit 20
else

    CheckIP "$STATIC_IP2"
    if [ 0 -ne $? ]; then
        msg="Test parameter STATIC_IP2 = $STATIC_IP2 is not a valid IP Address."
        LogMsg "$msg"
        UpdateSummary "$msg"
        UpdateTestState $ICA_TESTABORTED
        exit 20
    fi
fi

#Download NETPERF
wget https://github.com/HewlettPackard/netperf/archive/netperf-2.7.0.tar.gz > /dev/null 2>&1
if [ $? -ne 0 ]; then
    msg="Error: Unable to download netperf."
    LogMsg "$msg"
    UpdateSummary "$msg"
    UpdateTestState $ICA_TESTFAILED
    exist 1
fi
tar -xvf netperf-2.7.0.tar.gz > /dev/null 2>&1

#Get the root directory of the tarball
rootDir="netperf-netperf-2.7.0"
cd ${rootDir}

#Distro specific setup
GetDistro

case "$DISTRO" in
debian*|ubuntu*)
    service ufw status
    if [ $? -ne 3 ]; then
        LogMsg "Disabling firewall on Ubuntu.."
        iptables -t filter -F
        if [ $? -ne 0 ]; then
            msg="Error: Failed to stop ufw."
            LogMsg "${msg}"
            UpdateSummary "${msg}"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        iptables -t nat -F
        if [ $? -ne 0 ]; then
            msg="Error: Failed to stop ufw."
            LogMsg "${msg}"
            UpdateSummary "${msg}"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi;;
redhat_5|redhat_6)
    LogMsg "Check iptables status on RHEL."
    service iptables status
    if [ $? -ne 3 ]; then
        LogMsg "Disabling firewall on Redhat.."
        iptables -t filter -F
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush iptables rules."
            LogMsg "${msg}"
            UpdateSummary "${msg}"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        iptables -t nat -F
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush iptables nat rules."
            LogMsg "${msg}"
            UpdateSummary "${msg}"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        ip6tables -t filter -F
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush ip6tables rules."
            LogMsg "${msg}"
            UpdateSummary "${msg}"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        ip6tables -t nat -F
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush ip6tables nat rules."
            LogMsg "${msg}"
            UpdateSummary "${msg}"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi;;
redhat_7)
    LogMsg "Check iptables status on RHEL."
    systemctl status firewalld
    if [ $? -ne 3 ]; then
        LogMsg "Disabling firewall on Redhat 7.."
        systemctl disable firewalld
        if [ $? -ne 0 ]; then
            msg="Error: Failed to stop firewalld."
            LogMsg "${msg}"
            UpdateSummary "${msg}"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        systemctl stop firewalld
        if [ $? -ne 0 ]; then
            msg="Error: Failed to turn off firewalld."
            LogMsg "${msg}"
            UpdateSummary "${msg}"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi
    LogMsg "Check iptables status on RHEL 7."
    service iptables status
    if [ $? -ne 3 ]; then
        iptables -t filter -F
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush iptables rules."
            LogMsg "${msg}"
            UpdateSummary "${msg}"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        iptables -t nat -F
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush iptables nat rules."
            LogMsg "${msg}"
            UpdateSummary "${msg}"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        ip6tables -t filter -F
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush ip6tables rules."
            LogMsg "${msg}"
            UpdateSummary "${msg}"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        ip6tables -t nat -F
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush ip6tables nat rules."
            LogMsg "${msg}"
            UpdateSummary "${msg}"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi;;
suse_12)
    LogMsg "Check iptables status on SLES 12."
    service SuSEfirewall2 status
    if [ $? -ne 3 ]; then
        iptables -F;
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush iptables rules."
            LogMsg "${msg}"
            UpdateSummary "${msg}"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        service SuSEfirewall2 stop
        if [ $? -ne 0 ]; then
            msg="Error: Failed to stop iptables."
            LogMsg "${msg}"
            UpdateSummary "${msg}"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        chkconfig SuSEfirewall2 off
        if [ $? -ne 0 ]; then
            msg="Error: Failed to turn off iptables."
            LogMsg "${msg}"
            UpdateSummary "${msg}"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi;;
esac

./configure > /dev/null 2>&1
if [ $? -ne 0 ]; then
    msg="Error: Unable to configure make file for netperf."
    LogMsg "${msg}"
    UpdateSummary "${msg}"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi
make > /dev/null 2>&1
if [ $? -ne 0 ]; then
    msg="Error: Unable to build netperf."
    LogMsg "${msg}"
    UpdateSummary "${msg}"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi
make install > /dev/null 2>&1
if [ $? -ne 0 ]; then
    msg="Error: Unable to install netperf."
    LogMsg "${msg}"
    UpdateSummary "${msg}"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#go back to test root folder
cd ~

# Start netperf server instances
LogMsg "Starting netperf in server mode."

UpdateTestState $ICA_NETPERFRUNNING
LogMsg "Netperf server instances are now ready to run."
netserver -L ${STATIC_IP2} >> ~/summary.log
if [ $? -ne 0 ]; then
    msg="Error: Unable to start netperf in server mode."
    LogMsg "${msg}"
    UpdateSummary "${msg}"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi
