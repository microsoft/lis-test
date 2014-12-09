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

# Description :
#    This script will verify if NMI is received from the hyper-v
# host. It will look at the /proc/interrupt file to verify this.

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

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
if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi


#Check for Testcase count
if [ ! ${TC_COUNT} ]; then
    LogMsg "The TC_COUNT variable is not defined."
	echo "The TC_COUNT variable is not defined." >> ~/summary.log
    LogMsg "Terminating the test."
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

echo "Covers : ${TC_COUNT}" >> ~/summary.log

#
# Getting the VCPUs Count
#
cpu=$(grep CPU -o /proc/interrupts | wc -l)
LogMsg "${cpu} CPUs found"

#
# Verifying if NMI is received by checking /proc/interrupts file
#
while read line
do
	if [[ $line = *NMI* ]]; then
        for ((  i=0 ;  i<=$cpu-1;  i++ ))
        do
            nmiCount=`echo $line | cut -f $(( $i+2 )) -d ' '`
            LogMsg "CPU ${i} interrupt count = ${nmiCount}"
            if [ $nmiCount -ne 0 ]; then
                LogMsg "NMI Received at CPU ${i}"
				echo "NMI Received at CPU ${i}" >> ~/summary.log
            else
                LogMsg "Error: CPU {$i} did not receive NMI."
				echo "Error: CPU {$i} did not receive NMI." >> ~/summary.log
                UpdateTestState $ICA_TESTFAILED
                exit 30
            fi
        done
    fi
done < "/proc/interrupts"

LogMsg "Exiting with state: TestCompleted"
UpdateTestState $ICA_TESTCOMPLETED