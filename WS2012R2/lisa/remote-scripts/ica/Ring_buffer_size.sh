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
# Ring_buffer_size.sh
# Description:
#    This script will first check the existence of ethtool on vm and that
#    the ring settings from ethtool are supported.
#    Then it will try to set new size of ring buffer for RX-Received packets
#    and TX-Trasmitted packets.
#	 If the new values were set then the test is PASS.
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
declare -i __iterator=0

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

#Check if parameters rx and tx are provided in constants file
if [ ! ${rx} ] || [ ! ${tx} ]; then
	LogMsg "The test parameters tx and rx are not defined in constants file!"
	UpdateSummary "The test parameters tx an rx are not defined in constants file!"
	UpdateTestState $ICA_TESTABORTED
    exit 1
fi

#Check if ethtool exist and install it if not
VerifyIsEthtool

#Get interfaces
ListInterfaces

#bring up interfaces through DHCP
while [ $__iterator -lt ${#SYNTH_NET_INTERFACES[@]} ]; do
	LogMsg "Trying to get an IP Address via DHCP on interface ${SYNTH_NET_INTERFACES[$__iterator]}"
	CreateIfupConfigFile "${SYNTH_NET_INTERFACES[$__iterator]}" "dhcp"
	if [ $? -ne 0 ]; then
		msg="Unable to get address for ${SYNTH_NET_INTERFACES[$__iterator]} through DHCP"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi

	# add some interface output
	LogMsg "$(ip -o addr show ${SYNTH_NET_INTERFACES[$__iterator]} | grep -vi inet6)"
	: $((__iterator++))
done

#reset the iterator
__iterator=0

#Check if kernel support ring settings from ethtool
sts=$(ethtool -g ${SYNTH_NET_INTERFACES[$__iterator]} 2>&1)
if [[ $sts = *"Operation not supported"* ]]; then
	LogMsg "$sts"
	LogMsg "Operation not supported. Test Skipped."
	UpdateSummary "Operation not supported. Test Skipped."
	UpdateTestState $ICA_TESTSKIPPED
	exit 2
fi

#Take the initial values
rx_value=$(echo "$sts" | grep RX: | sed -n 2p | grep -o '[0-9]*')
tx_value=$(echo "$sts" | grep TX: | sed -n 2p | grep -o '[0-9]*')
LogMsg "RX: $rx_value | TX: $tx_value."

#Try to change RX and TX with new values
ethtool -G ${SYNTH_NET_INTERFACES[$__iterator]} rx $rx tx $tx
if [ $? -ne 0 ]; then
	LogMsg "Cannot change RX and TX values."
	UpdateSummary "Cannot change RX and TX values."
	UpdateTestState $ICA_TESTFAILED
	exit 1
fi

#Take the values after changes
new_sts=$(ethtool -g ${SYNTH_NET_INTERFACES[$__iterator]} 2>&1)
rx_modified=$(echo "$new_sts" | grep RX: | sed -n 2p | grep -o '[0-9]*')
tx_modified=$(echo "$new_sts" | grep TX: | sed -n 2p | grep -o '[0-9]*')
LogMsg "RX_modified: $rx_modified | TX_modified: $tx_modified."

#Compare provided values with values after changes
if [ $rx_modified == $rx ] && [ $tx_modified == $tx ]; then
    LogMsg "Successfully changed RX and TX values on ${SYNTH_NET_INTERFACES[$__iterator]}."
	UpdateSummary "Successfully changed RX and TX values on ${SYNTH_NET_INTERFACES[$__iterator]}."
	UpdateTestState $ICA_TESTCOMPLETED
	exit 0
else
	LogMsg "The values provided aren't matching the real values of RX and TX. Check the logs."
	UpdateSummary "The values provided aren't matching the real values of RX and TX. Check the logs."
	UpdateTestState $ICA_TESTFAILED
	exit 1
fi
