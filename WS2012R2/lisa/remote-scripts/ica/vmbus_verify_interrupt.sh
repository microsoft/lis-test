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
# vmbus_verify_interrupt.sh
# Description:
#	This script was created to automate the testing of a Linux
#	Integration services. This script will verify if all the CPUs 
#	inside a Linux VM are processing VMBus interrupts, by checking 
#	the /proc/interrupts file.
#	The VM must have at least 2 CPU cores, otherwise the script will 
#	return an error message.
#
#	The test performs the following steps:
#	 1. Make sure we have a constants.sh file.
#    2. Looks for the Hyper-v timer property of each CPU under /proc/interrupts
#	 3. Verifies if each CPU has more than 0 interrupts processed.
#     
#	 To pass test parameters into test cases, the host will create
#    a file named constants.sh.  This file contains one or more
#    variable definition.
#
################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

#
# Update LISA with the current status
#
cd ~
UpdateTestState $ICA_TESTRUNNING
LogMsg "Updating test case state to running"

#
# Source the constants file
#
if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

#
# Identifying the test-case ID
#
if [ ! ${TC_COVERED} ]; then
    LogMsg "The TC_COVERED variable is not defined!"
	echo "The TC_COVERED variable is not defined!" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

echo "This script covers test case: ${TC_COVERED}" >> ~/summary.log

#
# Getting the CPUs count
#
cpu_count=$(grep CPU -o /proc/interrupts | wc -l)
if [ $cpu_count -eq 1 ]; then
	LogMsg "The script requires at least 2 CPU cores!"
	echo "The script requires at least 2 CPU cores!" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
	exit 10
fi

LogMsg "${cpu_count} CPUs found"
echo "${cpu_count} CPUs found" >> ~/summary.log

#
# Verifying if VMBUS interrupts are processed by all CPUs by checking the /proc/interrupts file 
#
nonCPU0inter=0

while read line
do
    if [[ $line = *hyperv* ]]; then
        for ((  i=0 ;  i<=$cpu_count-1;  i++ ))
        do
            intrCount=`echo $line | cut -f $(( $i+2 )) -d ' '` 
            if [ $intrCount -ne 0 ]; then
                (( nonCPU0inter++ ))
				LogMsg "CPU core ${i} is processing VMBUS interrupts"
				echo "CPU core ${i} is processing VMBUS Interrupts" >> ~/summary.log
            fi
        done
    fi
done < "/proc/interrupts"

if [ $nonCPU0inter -ge 2 ]; then
	LogMsg "Test Passed! At least 2 CPU cores are processing interrupts."
	echo "Test Passed! At least 2 CPU cores are processing interrupts." >> ~/summary.log
	            else
                LogMsg "Error: Only 1 CPU core is processing VMBUS Interrupts!"
				echo "Error: Only 1 CPU core is processing VMBUS Interrupts!" >> ~/summary.log
                UpdateTestState "TestFailed"
                exit 10
fi

LogMsg "Test completed successfully"
UpdateTestState "TestCompleted"
exit 0
