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
# Check_clocksource.sh
#
# Description:
#	This script was created to check if the current_clocksource is not null.
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
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
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
# Check the file of current_clocksource
#
CheckSource()
{
    if ! [[ $(find /sys/devices/system/clocksource/clocksource0/current_clocksource -type f -size +0M) ]]; then
        LogMsg "Test Failed. No file was found current_clocksource greater than 0M."
        echo "Test Failed. No file was found in clocksource of size greater than 0M." >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 1
    else
        __file_name=$(cat /sys/devices/system/clocksource/clocksource0/current_clocksource)
        if [[ "$__file_name" =~ "hyperv_clocksource" ]]; then
            LogMsg "Test successful. Proper file was found."
        else
            LogMsg "Test failed. Proper file was NOT found."
            echo "Test failed. Proper file was NOT found." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    fi
}

#
# MAIN SCRIPT
#
CheckSource
echo "Test passed: the current_clocksource is not null and value is right." >> ~/summary.log
LogMsg "Test completed successfully"
UpdateTestState $ICA_TESTCOMPLETED
