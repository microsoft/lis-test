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

# Description:
#     This script was created to automate the testing of a Linux
#     Integration services.this script test the if   
#     network adapter is present inside guest vm and is equal to
#     Hyper-V setting pane by performing the following
#     
#	  Setups the bridge

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

LogMsg "########################################################"
LogMsg "This is Test Case to create bridge "

cd ~

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

#
# Source the constants file
#
if [ -e ~/${CONSTANTS_FILE} ]; then
    source ~/${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    LogMsg "$msg"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

#
# Check for Testcase count
#
if [ ! ${TC_COUNT} ]; then
    LogMsg "The TC_COUNT variable is not defined."
	echo "The TC_COUNT variable is not defined." >> ~/summary.log
    LogMsg "Terminating the test."
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

#
# Check for Bridge IP
#
if [ ! ${BridgeIP} ]; then
    LogMsg "The BridgeIP variable is not defined."
	echo "The BridgeIP variable is not defined." >> ~/summary.log
    LogMsg "Terminating the test."
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi
echo "Covers : ${TC_COUNT}" >> ~/summary.log

#Stop Firewall
service iptables stop 2>&1 > /dev/null

# Constant file path
#NET_PATH="/sys/devices/vmbus_0_0"
NO=`find /sys/devices -name net | grep vmbus* | wc -l`

j=1
while [ $NO -gt 0 ] 
do
    NET_PATH=`find /sys/devices -name net | grep vmbus* | sed -n ${NO}p`
    if [ ! -e ${NET_PATH} ]; then
        LogMsg "Network device path $NET_PATH does not exists"
        echo "Network device path $NET_PATH does not exists" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
	    exit 40
    fi 
    cd $NET_PATH
	#
	# To get latest synthetic device
	#
    eval DEVICE$j=`ls`
	j=$[$j+1]
	NO=$[$NO-1]
done

#
# Setup the bridge
#

brctl addbr br0
if [ $? -ne 0 ]; then
    LogMsg "Bridge can't be created"
	echo "Bridge can't be created" >> ~/summary.log
	UpdateTestState $ICA_TESTFAILED
	exit 50
fi

brctl addif br0 $DEVICE1
if [ $? -ne 0 ]; then
    LogMsg "$DEVICE1 can't be added to Bridge"
	echo "$DEVICE1 can't be added to Bridge" >> ~/summary.log
	UpdateTestState $ICA_TESTFAILED
	exit 60
fi

brctl addif br0 $DEVICE2
if [ $? -ne 0 ]; then
    LogMsg "$DEVICE2 can't be added to Bridge"
	echo "$DEVICE2 can't be added to Bridge" >> ~/summary.log
	UpdateTestState $ICA_TESTFAILED
	exit 70
fi

echo "Devices ${DEVICE1} and ${DEVICE2} are added to bridge" >> ~/summary.log

ifconfig br0 $BridgeIP up

ifconfig br0 | grep br0
if [ $? -ne 0 ]; then
    LogMsg "Bridge not setup correctly"
	echo "Bridge not setup correctly" >> ~/summary.log
	UpdateTestState $ICA_TESTFAILED
	exit 80
fi
echo "Bridge successfully created" >> ~/summary.log

LogMsg "#########################################################"
LogMsg "Exiting with state: TestCompleted."
UpdateTestState $ICA_TESTCOMPLETED
exit 0