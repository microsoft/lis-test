
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
# FC_multipath_detect.sh
# Description:
#    The script will count the number of disks shown by multipath.
#    It compares the result with the one received from the host.
#    To pass test parameters into test cases, the host will create
#    a file named constants.sh. This file contains one or more
#    variable definition.
#
################################################################

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

UpdateSummary()
{
    echo $1 >> ~/summary.log
}

cd ~
UpdateTestState "TestRunning"

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

if [ -e $HOME/constants.sh ]; then
	. $HOME/constants.sh
else
	LogMsg "ERROR: Unable to source the constants file."
	UpdateTestState "TestAborted"
	exit 1
fi

#Check for Testcase covered
if [ ! ${TC_COVERED} ]; then
    LogMsg "Error: The TC_COVERED variable is not defined."
	echo "Error: The TC_COVERED variable is not defined." >> ~/summary.log
    UpdateTestState "TestAborted"
    exit 1
fi

echo "Covers : ${TC_COVERED}" >> ~/summary.log

#
# Start the test
#
LogMsg "Starting test"

multipath
if [ $? -ne 0 ]; then
    msg="multipath utility not found. Please install it first."
    LogMsg "Error: ${msg}"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 30
fi

fcDiskCount=`multipath -ll | grep "sd" | wc -l`
if [ $? -ne 0 ]; then
    msg="Failed to count multipath disks."
    LogMsg "Error: ${msg}"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 30
fi

if [ $fcDiskCount -ne $expectedCount ]; then
    msg="Count missmatch between expected $expectedCount and actual $fcDiskCount"
    LogMsg "Error: ${msg}"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 30
else
    msg="Count match between expected $expectedCount and actual $fcDiskCount"
    LogMsg "Success: ${msg}"
    echo $msg >> ~/summary.log
fi

LogMsg "#########################################################"
LogMsg "Result : Test Completed Successfully"
LogMsg "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"
