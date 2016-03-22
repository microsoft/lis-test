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
# Description:
#	This script compares the host provided Numa Nodes values
#	with the numbers of CPUs and ones detected on a Linux guest VM.
#	To pass test parameters into test cases, the host will create
#	a file named constants.sh. This file contains one or more
#	variable definition.
#
################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

UpdateTestState() {
    echo $1 > $HOME/state.txt
}

UpdateSummary() {
	# To add the timestamp to the log file
    echo `date "+%a %b %d %T %Y"` : ${1} >> ~/summary.log
}

cd ~
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

UpdateTestState "TestRunning"

if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
else
    echo "ERROR: Unable to source the constants file!"
    UpdateSummary "ERROR: Unable to source the constants file!"
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    UpdateSummary "Error: unable to source utils.sh!"
    UpdateTestState $ICA_TESTABORTED
    exit 1
}

# Source constants file and initialize most common variables
UtilsInit

#
# Check if numactl is installed
#
numactl -s
if [ $? -ne 0 ]; then
	echo "Error: numactl is not installed."
	UpdateSummary "Error: numactl is not installed."
	UpdateTestState $ICA_TESTABORTED
	exit 1
fi

#
# Check Numa nodes
#

NumaNodes=`numactl -H | grep cpu | wc -l`
echo "Info : Detected NUMA nodes = ${NumaNodes}"
echo "Info : Expected NUMA nodes = ${expected_number}"

#
# We do a matching on the values from host and guest
#
if ! [[ $NumaNodes = $expected_number ]]; then
	echo "Error: Guest VM presented value $NumaNodesm and the host has $expected_number . Test Failed!"
	UpdateSummary "Error: Guest VM presented value $NumaNodesm and the host has $expected_number . Test Failed!"
    UpdateTestState $ICA_TESTFAILED
    exit 30
else
    echo "Info: Numa nodes value is matching with the host. VM presented value is $NumaNodes"
    UpdateSummary "Info: Numa nodes value is matching with the host. VM presented value is $NumaNodes"
fi

#
# If we got here, all validations have been successful and no errors have occurred
#
echo "Test Completed Successfully"
UpdateSummary "Test Completed Successfully"
UpdateTestState "TestCompleted"