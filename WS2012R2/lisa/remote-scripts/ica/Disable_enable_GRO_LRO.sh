#!/bin/bash
####################################################################################
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
#####################################################################################
#####################################################################################
#
# Disable_enable_GRO_LRO.sh
# Description:
#    This script will first check the existence of ethtool on vm and will 
#	disable & enable generic-receive-offload and large-receive-offload from ethtool.
#
#####################################################################################
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
	sts=$(ethtool -k ${SYNTH_NET_INTERFACES[$__iterator]} 2>&1 | grep generic-receive-offload | awk {'print $2'})
	if [ $action == "disabled" ] && [ $sts == "on" ]; then
		LogMsg "Generic-receive-offload NOT disabled."
		UpdateSummary "Generic-receive-offload NOT disabled."
		UpdateTestState $ICA_TESTFAILED
		exit 1 
	elif [ $action == "enabled" ] && [ $sts == "off" ]; then 
		LogMsg "Generic-receive-offload NOT enabled."
		UpdateSummary "Generic-receive-offload NOT enabled."
		UpdateTestState $ICA_TESTFAILED
		exit 1
	else
		LogMsg "Generic-receive-offload is $action."
		UpdateSummary "Generic-receive-offload is $action."
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

#Check if ethtool exist and install it if not
VerifyIsEthtool

#Get the interfaces
ListInterfaces

#Disable/Enable GRO
for (( i = 0 ; i < 2 ; i++ )); do
	#Show GRO status
	sts=$(ethtool -k ${SYNTH_NET_INTERFACES[$__iterator]} 2>&1 | grep generic-receive-offload | awk {'print $2'})
	if [[ "$sts" == "on" ]];then
		#Disable GRO
		ethtool -K ${SYNTH_NET_INTERFACES[$__iterator]} gro off >/dev/null 2>&1
		if [ $? -ne 0 ];then
			LogMsg "Cannot disable generic-receive-offload."
			UpdateSummary "Cannot disable generic-receive-offload."
			UpdateTestState $ICA_TESTFAILED
			exit 1
		fi
		#check if is disabled
		CheckResults "disabled"
	elif [[ "$sts" == "off" ]];then
		#Enable GRO
		ethtool -K ${SYNTH_NET_INTERFACES[$__iterator]} gro on >/dev/null 2>&1
		if [ $? -ne 0 ];then
			LogMsg "Cannot enable generic-receive-offload."
			UpdateSummary "Cannot enable generic-receive-offload."
			UpdateTestState $ICA_TESTFAILED
			exit 1
		fi
		#check if is enabled
		CheckResults "enabled"
	else
		LogMsg "Cannot get status of generic-receive-offload."
		UpdateSummary "Cannot get status of generic-receive-offload."
		UpdateTestState $ICA_TESTFAILED
		exit 1
	fi   
done

#Disable/Enable LRO
LogMsg "LRO status:"
ethtool -k ${SYNTH_NET_INTERFACES[$__iterator]} | grep large-receive-offload 
LogMsg "Enable large-receive-offload:"
ethtool -K ${SYNTH_NET_INTERFACES[$__iterator]} lro on
LogMsg "LRO status:"
ethtool -k ${SYNTH_NET_INTERFACES[$__iterator]} | grep large-receive-offload
LogMsg "Disable large-receive-offload:"
ethtool -K ${SYNTH_NET_INTERFACES[$__iterator]} lro off

UpdateTestState $ICA_TESTCOMPLETED
exit 0