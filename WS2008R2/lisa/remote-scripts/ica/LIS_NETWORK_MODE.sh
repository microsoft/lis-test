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
#     Integration services.this script test the if network mode #     can be setup to "normal" and "promiscous" mode.
#     
#     steps:
#	 1. Make sure we were given a configuration file.
#	 2. Verify LIC modules netvsc is loaded.
#     3. This script should be run only after LIC is installed.
#	 5. Make sure by default network is set to Normal mode.     
#     6. Make sure you can change the mode to promiscous.


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

# Source the constants file
if [ -e ~/${CONSTANTS_FILE} ]; then
    source ~/${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    LogMsg "$msg"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

#Since it require to ping external network external network ip must be defined
if [ ! ${REPOSITORY_SERVER} ]; then
	LogMsg "The REPOSITORY_SERVER variable is not defined."
	echo "The REPOSITORY_SERVER variable is not defined." >> ~/summary.log
	UpdateTestState $ICA_TESTABORTED
	exit 20
fi

#Check for Testcase count
if [ ! ${TC_COUNT} ]; then
    LogMsg "The TC_COUNT variable is not defined."
	echo "The TC_COUNT variable is not defined." >> ~/summary.log
    LogMsg "Terminating the test."
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

echo "Covers : ${TC_COUNT}" >> ~/summary.log

#
# Get the modules tree
#
MODULES=~/modules.txt
lsmod | grep hv_* > $MODULES

grep -q "netvsc" $MODULES
sts=$?
if [ 0 -ne ${sts} ]; then
    LogMsg "netvsc Failed to load on the system, please check if you have LIS installed"
    echo "netvsc Failed to load on the system, please check if you have LIS installed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 40
else
    LogMsg "netvsc Module is up and running inside guest VM. "
fi

# Constant file path
#NET_PATH="/sys/devices/vmbus_0_0"
NET_PATH=`find /sys/devices -name net | grep vmbus*`
if [ ! -e ${NET_PATH} ]; then
    LogMsg "Network device path $NET_PATH does not exists"
    LogMsg "Exiting test as aborted "
    UpdateTestState $ICA_TESTABORTED
	exit 50

fi


# #f tmp file is present please delter it do the apporpriate check by if and all.

rm -rf ~/tmp.txt

cd $NET_PATH
#find -name eth* | cut -f 4 -d "/"  > ~/tmp.txt
ls > /root/tmp.txt

#NET_PATH=( `cat ~/tmp.txt | tr '.' ' ' `)
NET_DEVICE=( `cat ~/tmp.txt `)

LogMsg "Net device present in the VM is: $NET_DEVICE"

#
#Enabling/disabling promisc mode
#

ifconfig $NET_DEVICE promisc

ifconfig $NET_DEVICE | grep -q "PROMISC" 
if [ $? -ne 0 ];	then
    LogMsg "Error entering $NET_DEVICE promisc mode"
    echo "Error entering $NET_DEVICE promisc mode" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 60
fi

cat /var/log/messages | grep "promisc"
if [ $? -ne 0 ];	then
    LogMsg "Error entering $NET_DEVICE promisc mode"
    echo "Error entering $NET_DEVICE promisc mode" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 70
fi

LogMsg "Promiscuous Mode Enable  : Passed"
echo "Promiscuous Mode Enable  : Passed" >> ~/summary.log

rm -rf ~/pingdata

LogMsg "ping -s ${pkt} -c 5 ${TARGET_ADDR}"
ping -c 5 ${REPOSITORY_SERVER} > ~/pingdata
	
loss=`cat ~/pingdata | grep "packet loss" | cut -d " " -f 6`
LogMsg "Packet loss is : ${loss}"
if [ "${loss}" != "0%" ] ; then
    LogMsg "Ping failed in PROMISC mode"
    echo "Ping failed in PROMISC mode" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 78
else
    LogMsg "Ping Successful"
    sleep 1
fi
	
ifconfig $NET_DEVICE -promisc

ifconfig | grep -q "PROMISC"
if [ $? -eq 0 ]; 	then
    LogMsg "Error disabling $NET_DEVICE promisc mode"
    echo "Error disabling $NET_DEVICE promisc mode" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 90
fi

rm -rf ~/pingdata

LogMsg "Promiscuous Mode Disable : Passed"
echo "Promiscuous Mode Disable : Passed" >> ~/summary.log

LogMsg "#########################################################"
LogMsg "Result : Test Completed Succesfully"
LogMsg "Exiting with state: TestCompleted."
UpdateTestState $ICA_TESTCOMPLETED

exit 0