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
ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTFAILED="TestFailed"

tokens=("Operating system shutdown" "Time Synchronization" "Heartbeat"
        "Data Exchange" "Guest services" "Dynamic Memory" "mouse"
        "keyboard" "Synthetic network adapter" "Synthetic SCSI Controller")

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}
}

UpdateSummary()
{
    echo $1 >> ~/summary.log
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

#######################################################################
# Main script body
#######################################################################

# Create the state.txt file so ICA knows we are running
UpdateTestState $ICA_TESTRUNNING

# Source the constants file
if [ -e constants.sh ]; then
    . constants.sh
else
    LogMsg "WARN: Unable to source the constants file."
fi

# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

if [ ! ${TC_COVERED} ]; then
    LogMsg "The TC_COVERED variable is not defined!"
    echo "The TC_COVERED variable is not defined!" >> ~/summary.log
fi

echo "This script covers test case: ${TC_COVERED}" >> ~/summary.log

dos2unix utils.sh
. utils.sh

GetDistro
case $DISTRO in
    redhat_5|centos_5*)
        LogMsg "Error: RedHat/CentOS 5.x not supported."
        UpdateSummary "Error: RedHat/CentOS 5.x not supported."
        UpdateTestState $ICA_TESTFAILED
        exit 1
    ;;
esac

# check if lsvmbus exists
lsvmbus_path=`which lsvmbus`
if [ -z $lsvmbus_path ]; then
    LogMsg "Error: lsvmbus not found."
    UpdateSummary "Error: lsvmbus not found."
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

if [ "$generation" -eq "1" ]; then
    tokens+=("Synthetic IDE Controller")
fi

$lsvmbus_path
for token in "${tokens[@]}"; do
    $lsvmbus_path | grep "$token"
    if [ $? -ne 0 ]; then
        LogMsg "Error: $token not found in lsvmbus information."
        UpdateSummary "Error: $token not found in lsvmbus information."
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
done

UpdateSummary "All VMBus device IDs have been found."
UpdateTestState $ICA_TESTCOMPLETED
exit 0