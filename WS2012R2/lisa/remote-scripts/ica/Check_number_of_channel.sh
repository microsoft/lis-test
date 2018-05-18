#!/bin/bash
############################################################################
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
#############################################################################
#############################################################################
#
# Check_number_of_channel.sh
# Description:
#	This script will first check the existence of ethtool on vm and that
#   the channel parameters are supported from ethtool.
#	It will check if number of cores is matching with number of current 
#   channel.
#
#############################################################################
ICA_TESTRUNNING="TestRunning"
ICA_TESTSKIPPED="TestSkipped"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTFAILED="TestFailed"
ICA_TESTABORTED="TestAborted"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}
}

UpdateSummary()
{
    echo -e $1 >> ~/summary.log
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

#######################################################################
#
# Main script body
#
#######################################################################
#set the iterator
__iterator=0

#Create the state.txt file so ICA knows we are running
UpdateTestState $ICA_TESTRUNNING

#Convert eol
dos2unix utils.sh

#Source utils.sh
. utils.sh || {
	echo "Error: unable to source utils.sh!"
	UpdateTestState $ICA_TESTABORTED
	exit 2
}

#Source constants file and initialize most common variables
UtilsInit

#skipp when host older than 2012R2
vmbus_version=`dmesg | grep "Vmbus version" | awk -F: '{print $(NF)}' | awk -F. '{print $1}'`
if [ $vmbus_version -lt 3 ]; then
	LogMsg "Info: Host version older than 2012R2. Skipping test."
	UpdateSummary "Info: Host version older than 2012R2. Skipping test."
	UpdateTestState $ICA_TESTSKIPPED
	exit 1
fi

#Check if ethtool exist and install it if not
VerifyIsEthtool

#Get interfaces
ListInterfaces

#Check if kernel support channel parameters with ethtool
sts=$(ethtool -l ${SYNTH_NET_INTERFACES[$__iterator]} 2>&1)
if [[ $sts = *"Operation not supported"* ]]; then
	LogMsg "$sts"
	LogMsg "Operation not supported. Test Skipped."
	UpdateSummary "Operation not supported. Test Skipped."
	UpdateTestState $ICA_TESTSKIPPED
	exit 2
fi

#Get number of channels
channels=$(ethtool -l ${SYNTH_NET_INTERFACES[$__iterator]} | grep "Combined" | sed -n 2p | grep -o '[0-9]*')
#Get number of cores
cores=$(cat /proc/cpuinfo | grep processor | wc -l)

if [ $channels != $cores ]; then
	LogMsg "Expected: $cores channels and actual $channels."
	UpdateSummary "Expected: $cores channels and actual $channels."
	UpdateTestState $ICA_TESTFAILED
	exit 1
fi

msg="Number of channels: $channels and number of cores: $cores."
LogMsg "$msg"
UpdateSummary "$msg"
UpdateTestState $ICA_TESTCOMPLETED