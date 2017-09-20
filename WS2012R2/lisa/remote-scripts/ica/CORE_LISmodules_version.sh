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
#	CORE_LISmodules_version.sh
#
#	Description:
#		This script was created to automate the testing of a Linux
#	Integration services. The script will verify the list of given
#	LIS kernel modules and verify if the version matches with the 
#	Linux kernel release number.
#
#		To pass test parameters into test cases, the host will create
#	a file named constants.sh. This file contains one or more
#	variable definition.
#
########################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
	# Adding the timestamp to the log file
    echo `date "+%a %b %d %T %Y"` : ${1}    
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

# Verifies first if the modules are loaded
for module in ${HYPERV_MODULES[@]}; do
	load_status=$( lsmod | grep $module 2>&1)

	# Check to see if the module is loaded
	if [[ $load_status =~ $module ]]; then
		version=$(modinfo $module | grep vermagic: | awk '{print $2}')
		if [[ "$version" == "$(uname -r)" ]]; then
			LogMsg "Found a kernel matching version for $module module: ${version}"
			echo "Found a kernel matching version for $module module: ${version}" >> ~/summary.log
		else
			LogMsg "Error: LIS module $module doesn't match the kernel build version!"
			echo "Error: LIS module $module doesn't match the kernel build version!" >> ~/summary.log
			UpdateTestState $ICA_TESTABORTED
			exit 10
		fi
	fi
done

UpdateTestState $ICA_TESTCOMPLETED
exit 0
