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
# CORE_StressReloadModules.sh
#
# Description:
#    This script will first check the existence of Hyper-V kernel modules.
#    Then it will reload the modules in a loop in order to stress the system.
#    It also checks that hyperv_fb cannot be unloaded.
#    When done it will bring up the eth0 interface and check again for
#    the presence of Hyper-V modules.
#
################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState()
{
    echo "$1" > $HOME/state.txt
}

UpdateSummary()
{
    echo "$1" >> ~/summary.log
}

VerifyModules()
{
    MODULES=~/modules.txt
    lsmod | grep hv_* > $MODULES

    #
    # Did VMBus load
    #
    LogMsg "Info: Checking if hv_vmbus is loaded..."

    grep -q "vmbus" $MODULES
    if [ $? -ne 0 ]; then
        msg="Warning: hv_vmbus not loaded or built-in"
        LogMsg "${msg}"
        echo "$msg" >> ~/summary.log
    fi
    LogMsg "Info: hv_vmbus loaded OK"

    #
    # Did storvsc load
    #
    LogMsg "Info: Checking if storvsc is loaded..."

    grep -q "storvsc" $MODULES
    if [ $? -ne 0 ]; then
        msg="Warning: hv_storvsc not loaded or built-in"
        LogMsg "${msg}"
        echo "$msg" >> ~/summary.log
    fi
    LogMsg "Info: hv_storvsc loaded OK"

    #
    # Did netvsc load
    #
    LogMsg "Info: Checking if hv_netvsc is loaded..."

    grep -q "hv_netvsc" $MODULES
    if [ $? -ne 0 ]; then
        msg="Error: hv_netvsc not loaded"
        LogMsg "${msg}"
        echo "$msg" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
    LogMsg "Info: hv_netvsc loaded OK"

    #
    # Did utils load
    #
    LogMsg "Info: Checking if hv_utils is loaded..."

    grep -q "utils" $MODULES
    if [ $? -ne 0 ]; then
        msg="Error: hv_utils not loaded"
        LogMsg "${msg}"
        echo "$msg" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
    LogMsg "Info: hv_utils loaded OK"
}

#######################################################################
#
# Main script body
#
#######################################################################

# Create the state.txt file so ICA knows we are running
UpdateTestState $ICA_TESTRUNNING

# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
fi

echo "Covers: ${TC_COVERED}" >> ~/summary.log

VerifyModules

modprobe -r hyperv_fb
if [ $? -eq 0 ]; then
    msg="Error: hyperv_fb could be disabled!"
    LogMsg "${msg}"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

# if not set the LoopCount, set as 100 by default
if [ "${LoopCount:-UNDEFINED}" = "UNDEFINED" ]; then
    LoopCount=100
fi

# if not set the sleep duration, set as 1 second by default
if [ "${Duration:-UNDEFINED}" = "UNDEFINED" ]; then
    Duration=1
fi

msg="Info: module unload/load loop count set as $LoopCount"
LogMsg "${msg}"
echo "$msg" >> ~/summary.log

pass=0
START=$(date +%s)
while [ $pass -lt $LoopCount ]
do
    modprobe -r hv_netvsc
    sleep $Duration
    modprobe hv_netvsc
    sleep $Duration
    modprobe -r hv_utils
    sleep $Duration
    modprobe hv_utils
    sleep $Duration
    modprobe -r hid_hyperv
    sleep $Duration
    modprobe hid_hyperv
    sleep $Duration
    pass=$((pass+1))
    echo $pass
done
END=$(date +%s)
DIFF=$(echo "$END - $START" | bc)

echo "Info: Finished testing, bringing up eth0"
ifdown eth0 && ifup eth0
dhclient
if [[ $? -ne 0 ]]; then
    msg="Error: dhclient exited with an error"
    LogMsg "${msg}"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi
VerifyModules

# inet\b only shows the IPv4 address of the interface
ipAddress=$(ip addr show eth0 | grep "inet\b")
if [ -z "$ipAddress" ]; then
    LogMsg "Info: Waiting 30 seconds for interface to receive an IP"
    sleep 30
fi

echo "Info: Test ran for ${DIFF} seconds" >> ~/summary.log

LogMsg "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"
