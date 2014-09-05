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


ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during running of test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

#
# Create the state.txt file so ICA knows we are running
#
LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

#
# Cleanup any old summary.log files
#
if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

# Source the constants file
if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    echo $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi


#Check for Testcase count
if [ ! ${TC_COVERED} ]; then
    LogMsg "Error: The TC_COVERED variable is not defined."
    echo "Error: The TC_COVERED variable is not defined." >> ~/summary.log
    UpdateTestState "TestAborted"
    exit 1
fi

echo "Covers : ${TC_COVERED}" >> ~/summary.log

#
# Count the number of SCSI= and IDE= entries in constants
#
diskCount=0
for entry in $(cat ./constants.sh)
do
    # Convert to lower case
    lowStr="$(tr '[A-Z]' '[a-z' <<<"$entry")"

    # does it start wtih ide or scsi
    if [[ $lowStr == ide* ]];
    then
        diskCount=$((diskCount+1))
    fi

    if [[ $lowStr == scsi* ]];
    then
        diskCount=$((diskCount+1))
    fi
done

LogMsg "constants disk count = $diskCount"

### do fdisk to rescan the scsi bus
fdisk -l > /dev/null 
fdisk -l > /dev/null 
fdisk -l > /dev/null 
fdisk -l > /dev/null 

#
# Compute the number of sd* drives on the system.
#
sdCount=0
sdCount=`fdisk -l | grep "Disk /dev/sd*" | wc -l`


#
# Subtract the boot disk from the sdCount, then make
# sure the two disk counts match
#
sdCount=$((sdCount-1))
LogMsg "fdisk -l disk count = $sdCount"

if [ $sdCount == $diskCount ]; then
    LogMsg "constants.sh disk count ($diskCount) does match disk count from /sys/devices ($sdCount)"
	echo "constants.sh disk count ($diskCount) does match disk count from /sys/devices ($sdCount)" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 30 
else
    if [ "$sdCount" == "0" ]; then
	    LogMsg "Hot remove of Disk was successful"
	    echo "Hot remove Disk was successful" >> ~/summary.log
	else
	    LogMsg "Disk count mismatch, count is $sdCount"
		echo "Disk count mismatch, count is $sdCount" >> ~/summary.log
		UpdateTestState $ICA_TESTFAILED
        exit 40
    fi
fi

LogMsg "Exiting with state: TestCompleted."
UpdateTestState $ICA_TESTCOMPLETED

exit 0
