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
#
# Description:
#	This script was created to automate the testing of a Linux
#	Integration services. This script will verify if all the CPUs 
#	inside a Linux VM are processing VMBus interrupts, by checking 
#	the /proc/interrupts file.
#	The VM is configured with 4 CPU cores as part of the setup script,
#	as each core must process the Hyper-V interrupts for a successful test pass.
#
#	The test performs the following steps:
#		1. Configures the VM with 4 cores (see the test case XML definition)	
#		2. Make sure we have a constants.sh file.
#		3. Looks for the Hyper-v timer property of each CPU under /proc/interrupts
#		4. Verifies if each CPU has more than 0 interrupts processed.
#     
#	To pass test parameters into test cases, the host will create
#	a file named constants.sh.  This file contains one or more
#	variable definition.
#
################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

CONSTANTS_FILE="constants.sh"
nonCPU0inter=0

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
fi

echo "This script covers test case: ${TC_COVERED}" >> ~/summary.log

#
# Getting the CPUs count
#
cpu_count=$(grep CPU -o /proc/interrupts | wc -l)
echo "${cpu_count} CPU cores detected" >> ~/summary.log

#
# Verifying if VMBUS interrupts are processed by all CPUs by checking /proc/interrupts 
#
while read line
do
    if [[ ($line = *hyperv* ) || ( $line = *Hypervisor* ) ]]; then
        for (( core=0; core<=$cpu_count-1; core++ ))
        do
            intrCount=`echo $line | cut -f $(( $core+2 )) -d ' '`
            if [ $intrCount -ne 0 ]; then
                (( nonCPU0inter++ ))
                LogMsg "Only CPU core ${core} is processing VMBUS interrupts."
            fi
        done
    fi
done < "/proc/interrupts"

if [ $nonCPU0inter -eq $cpu_count ]; then
	LogMsg "Test Passed! All CPU cores are processing interrupts."
	echo "Test Passed! All CPU cores are processing interrupts." >> ~/summary.log
else
	LogMsg "Test Failed! Not all CPU cores are processing VMBUS interrupts."
	echo "Test Failed! Not all CPU cores are processing VMBUS interrupts." >> ~/summary.log
	UpdateTestState "TestFailed"
	exit 10
fi

LogMsg "Test completed successfully"
UpdateTestState "TestCompleted"
exit 0
