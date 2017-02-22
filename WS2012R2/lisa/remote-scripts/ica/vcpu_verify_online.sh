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
# VCPU_verify_online.sh
#
# Description:
#	This script was created to automate the testing of VCPU online or offline.
#   This script will verify if all the CPUs can be offline by checking
#	the /proc/cpuinfo file.
#	The VM is configured with 4 CPU cores as part of the setup script,
#	as each core can't be offline except vcpu0 for a successful test pass.
#
#	The test performs the following steps:
#		1. Configures the VM with 4 cores (see the test case XML definition)	
#		2. Make sure we have a constants.sh file.
#		3. Looks for the Hyper-v timer property of each CPU under /proc/cpuinfo
#		4. Verifies if each CPU can't be offline exinclude VCPU0.
#     
#	To pass test parameters into test cases, the host will create
#	a file named constants.sh.  This file contains one or more
#	variable definition.
#
# Note: The Host of Hyper-V 2012 R2 don't support the CPU online or offline, so
# To make sure the CPU on guest can't be offline.
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

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi
touch ~/summary.log

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
cpu_count=$(grep -i processor -o /proc/cpuinfo | wc -l)
echo "${cpu_count} CPU cores detected" >> ~/summary.log

#
# Verifying all CPUs can't be offline except CPU0 
#
for ((cpu=1 ; cpu<=$cpu_count ; cpu++)) ;do
    LogMsg "Checking the $cpu on /sys/device/...."
    __file_path="/sys/devices/system/cpu/cpu$cpu/online"
    if [ -e "$__file_path" ]; then
        echo 0 > $__file_path > /dev/null 2>&1
        val=`cat $__file_path`
        if [ $val -ne 0 ]; then
            LogMsg "CPU core ${cpu} can't be offline."
        else
            LogMsg "Error: CPU ${cpu} can be offline!"
            echo "Error: CPU ${cpu} can be offline!" >> ~/summary.log
            UpdateTestState "TestFailed"
            exit 80
        fi
    fi
done

echo "Test pass: no CPU cores could be set to offline mode." >> ~/summary.log
LogMsg "Test completed successfully"
UpdateTestState $ICA_TESTCOMPLETED
exit 0
