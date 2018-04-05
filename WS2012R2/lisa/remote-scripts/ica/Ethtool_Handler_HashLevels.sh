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
# Ethtool_Handler_HashLevels.sh
# Description:
#	This script will first check the existence of ethtool on vm and that
#   the network flow hashing options are supported from ethtool.
#	While L4 hash is enabled by default the script will try to exclude it and 
#   included back. It will check each time if the results are as expected.
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

CheckResults()
{
	action=$1
	sts=$(ethtool -n ${SYNTH_NET_INTERFACES[$__iterator]} rx-flow-hash $protocol 2>&1)
	if [ $action == "excluded" ] && [[ $sts = *"[TCP/UDP src port]"* && $sts = *"[TCP/UDP dst port]"* ]]; then
		LogMsg "$sts"
		LogMsg "Protocol: $protocol NOT excluded."
		UpdateSummary "Protocol: $protocol NOT excluded."
		UpdateTestState $ICA_TESTFAILED
		exit 1 
	elif [ $action == "included" ] && ! [[ $sts = *"[TCP/UDP src port]"* && $sts = *"[TCP/UDP dst port]"* ]]; then 
		LogMsg "$sts"
		LogMsg "Protocol: $protocol NOT included."
		UpdateSummary "Protocol: $protocol NOT included."
		UpdateTestState $ICA_TESTFAILED
		exit 1
	else
		LogMsg "$sts"
		LogMsg "Protocol: $protocol $action."
		UpdateSummary "Protocol: $protocol $action."
	fi
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

#Check if protocol parameter is provided in constants file
if [ ! ${protocol} ]; then
	LogMsg "The test parameter protocol is not defined in constants file!"
	UpdateSummary "The test parameter protocol is not defined in constants file!"
	UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#Check if ethtool exist and install it if not
VerifyIsEthtool

#Get interfaces
ListInterfaces

#Check if kernel support network flow hashing options with ethtool
sts=$(ethtool -n ${SYNTH_NET_INTERFACES[$__iterator]} rx-flow-hash $protocol 2>&1)
if [[ $sts = *"Operation not supported"* ]]; then
	LogMsg "$sts"
	LogMsg "Operation not supported. Test Skipped."
	UpdateSummary "Operation not supported. Test Skipped."
	UpdateTestState $ICA_TESTSKIPPED
	exit 2
fi
LogMsg "$sts"

#L4 hash is enabled as default
#try to exclude TCP/UDP port numbers in hashing
ethtool -N ${SYNTH_NET_INTERFACES[$__iterator]} rx-flow-hash $protocol sd
if [ $? -ne 0 ]; then
	LogMsg "Error: Cannot exclude $protocol!"
	UpdateSummary "Error: Cannot exclude $protocol!"
	UpdateTestState $ICA_TESTFAILED
	exit 1
fi

#check if was excluded
CheckResults "excluded"

#try to include TCP/UDP port numbers in hashing
ethtool -N ${SYNTH_NET_INTERFACES[$__iterator]} rx-flow-hash $protocol sdfn
if [ $? -ne 0 ]; then
	LogMsg "Error: Cannot include $protocol!"
	UpdateSummary "Error: Cannot include $protocol!"
	UpdateTestState $ICA_TESTFAILED
	exit 1
fi

#check if was included
CheckResults "included"

LogMsg "Exclude/Include $protocol on ${SYNTH_NET_INTERFACES[$__iterator]} successfully."
UpdateSummary "Exclude/Include $protocol on ${SYNTH_NET_INTERFACES[$__iterator]} successfully."
UpdateTestState $ICA_TESTCOMPLETED