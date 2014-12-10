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

#  This script verifies that LIS modules are loaded properly

ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestAborted"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

# adding check for summary.log
if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

#
# Create the state.txt file so the ICA script knows
# we are running
#
UpdateTestState $ICA_TESTRUNNING

if [ -e ~/constants.sh ]; then
	. ~/constants.sh
else
	LogMsg "ERROR: Unable to source the constants file."
	UpdateTestState "TestAborted"
	exit 1
fi

#Check for Testcase count
if [ ! ${TC_COUNT} ]; then
    LogMsg "The TC_COUNT variable is not defined."
	echo "The TC_COUNT variable is not defined." >> ~/summary.log
    LogMsg "Terminating the test."
    UpdateTestState "TestAborted"
    exit 1
fi

echo "Covers : ${TC_COUNT}" >> ~/summary.log

### Display info on the Hyper-V modules that are loaded ###

#
# Get the modules tree
#
MODULES=~/modules.txt
lsmod | grep hv_* > $MODULES


#
# Did VMBus load
#
LogMsg "Checking if VMBus loaded"

grep -q "vmbus" $MODULES
if [ $? -ne 0 ]; then
    msg="Vmbus not loaded"
    LogMsg "Error: ${msg}"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

#
# Did storvsc load
#
LogMsg "Checking if storvsc loaded"

grep -q "storvsc" $MODULES
if [ $? -ne 0 ]; then
    msg="storvsc not loaded"
    LogMsg "Error: ${msg}"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 30
fi

#
# Did netvsc load
#
LogMsg "Checking if netvsc loaded"

grep -q "netvsc" $MODULES
if [ $? -ne 0 ]; then
    msg="netvsc not loaded"
    LogMsg "Error: ${msg}"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi


#
# Did utils load
#
LogMsg "Checking if utils loaded"

grep -q "utils" $MODULES
if [ $? -ne 0 ]; then
    msg="utils not loaded"
    LogMsg "Error: ${msg}"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 30
fi


#
# Is boot disk under LIS control
#
DISKDATA=~/tmp
fdisk -l>~/tmp
LogMsg "Checking if boot device is under LIS control"

grep -q "/dev/sda" $DISKDATA
if [ $? -ne 0 ]; then
    msg="Boot disk not controlled by LIS"
    LogMsg "Error: ${msg}"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 70
fi

#
# If we got here, all tests passed
#
echo "LIS modules verified" >> ~/summary.log
LogMsg "Updating test case state to completed"

UpdateTestState $ICA_TESTCOMPLETED

exit 0
