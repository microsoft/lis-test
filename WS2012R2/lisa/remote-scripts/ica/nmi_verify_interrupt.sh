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
# nmi_verify_interrupt.sh
# Description:
#	This script was created to automate the testing of a Linux
#	Integration services. This script will verify if a NMI sent
#	from Hyper-V is received  inside the Linux VM, by checking the
#	/proc/interrupts file.
#	The test performs the following steps:
#	 1. Make sure we have a constants.sh file.
#    2. Looks for the NMI property of each CPU.
#	 3. Verifies if each CPU has received a NMI.
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
    LogMsg "The TC_COVERED variable is not defined."
	echo "The TC_COVERED variable is not defined." >> ~/summary.log
    LogMsg "Terminating the test."
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

echo "This script covers test case: ${TC_COVERED}" >> ~/summary.log

#
# Getting the CPUs NMI property count
#
cpu_count=$(grep CPU -o /proc/interrupts | wc -l)

LogMsg "${cpu_count} CPUs found"
echo "${cpu_count} CPUs found" >> ~/summary.log

#
# Verifying if NMI is received by checking the /proc/interrupts file
#
while read line
do
	if [[ $line = *NMI* ]]; then
        for ((  i=0 ;  i<=$cpu_count-1;  i++ ))
        do
            nmiCount=`echo $line | cut -f $(( $i+2 )) -d ' '`
            LogMsg "CPU ${i} interrupt count = ${nmiCount}"
            if [ $nmiCount -ne 0 ]; then
                LogMsg "NMI received at CPU ${i}"
				echo "NMI received at CPU ${i}" >> ~/summary.log
            else
                LogMsg "Error: CPU {$i} did not receive a NMI!"
				echo "Error: CPU {$i} did not receive a NMI!" >> ~/summary.log
                UpdateTestState $ICA_TESTFAILED
                exit 10
            fi
        done
    fi
done < "/proc/interrupts"

LogMsg "Test completed successfully"
UpdateTestState "TestCompleted"
exit 0