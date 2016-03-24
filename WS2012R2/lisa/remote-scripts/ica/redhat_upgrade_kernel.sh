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


ICA_TESTRUNNING="TestRunning"         # The test is running
ICA_TESTCOMPLETED="TestCompleted"     # The test completed successfully
ICA_TESTABORTED="TestAborted"         # Error during setup of test
ICA_TESTFAILED="TestFailed"           # Error during execution of test

CONSTANTS_FILE="constants.sh"

LogMsg() {
    echo `date "+%a %b %d %T %Y"` ": ${1}"
}

UpdateTestState() {
    echo $1 > ~/state.txt
}

UpdateSummary() {
    echo $1 >> ~/summary.log
}

cd ~
UpdateTestState $ICA_TESTRUNNING
echo "Updating test case state to running"

if [ -e ~/summary.log ]; then
    echo "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

touch ~/summary.log

#
# Source the constants.sh file to pickup definitions from
# the ICA automation
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

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

mkdir -p /tmp/test_upkernel/
if [ $? -ne 0 ]; then
	echo "Error: Unable to create the test directory." >> ~/summary.log
	UpdateTestState $ICA_TESTABORTED
fi

#
# Make sure constants.sh contains the variables we expect
#
if [ "${TC_COVERED:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter TC_COVERED is not defined in ${CONSTANTS_FILE}"
    LogMsg $msg
    echo $msg >> ~/summary.log
    exit 30
fi
if [ "${URL:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the test kernel URL parameter is missing!"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 30
fi
if [ "${UPKERNEL:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter UPKERNEL is not defined in ${CONSTANTS_FILE}"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

#
# Echo TCs we cover
#
echo "Covers ${TC_COVERED}" > ~/summary.log



if is_fedora ; then
	LogMsg "Downloading files..."
	echo "Downloading files and Installing packages..." >> ~/summary.log
	cd /tmp/test_upkernel/
    IFS=',' read -a rpmPackage <<< "$UPKERNEL"
    for file in ${rpmPackage[@]}; do
        wget $URL/$file
        rpm -Uvh $file
	    if [[ $? -ne 0 ]]; then
		    UpdateSummary "Error: Unable to install the test kernel ${file}!"
		    UpdateTestState $ICA_TESTABORTED
		    exit 1
	    fi
	done

	echo "Info: The kernel dependecies pacakages have been successfully installed!" >> ~/summary.log

	LogMsg "Test completed successfully"
	UpdateTestState $ICA_TESTCOMPLETED
	exit 0
fi
