#!/bin/bash

#####################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
#####################################################################

# Description:
#	This script verifies that the Dynamic Memory kernel module (hv_balloon) is loaded.
#
#	Steps:
#	1. Verify that hv_balloon is loaded.
#
#	The test is successful if the hv_balloon kernel module is loaded.
#	Parameters required:
#
#
#	Optional parameters:
#		TC_COVERED
#
#	Parameter explanation:
#	TC_COVERED is the LIS testcase number
#
#############################################################################################################

# Convert eol
dos2unix Utils.sh

# Source Utils.sh
. Utils.sh || {
	echo "Error: unable to source Utils.sh!"
	echo "TestAborted" > state.txt
	exit 2
}

# Source constants file and initialize most common variables
UtilsInit

# In case of error
case $? in
	0)
		#do nothing, init succeeded
		;;
	1)
		LogMsg "Unable to cd to $LIS_HOME. Aborting..."
		UpdateSummary "Unable to cd to $LIS_HOME. Aborting..."
		SetTestStateAborted
		exit 3
		;;
	2)
		LogMsg "Unable to use test state file. Aborting..."
		UpdateSummary "Unable to use test state file. Aborting..."
		# need to wait for test timeout to kick in
			# hailmary try to update teststate
			sleep 60
			echo "TestAborted" > state.txt
		exit 4
		;;
	3)
		LogMsg "Error: unable to source constants file. Aborting..."
		UpdateSummary "Error: unable to source constants file"
		SetTestStateAborted
		exit 5
		;;
	*)
		# should not happen
		LogMsg "UtilsInit returned an unknown error. Aborting..."
		UpdateSummary "UtilsInit returned an unknown error. Aborting..."
		SetTestStateAborted
		exit 6 
		;;
esac

if [ "${TC_COVERED:-UNDEFINED}" = "UNDEFINED" ]; then
	msg="The test parameter TC_COVERED is not defined in constants file"
	LogMsg "$msg"
else
	LogMsg "Testing testcase $TC_COVERED"
fi

# check lsmod
lsmod | grep -qi hv_balloon

if [ 0 -ne $? ]; then
	msg="The kernel module hv_balloon is not present in lsmod's output."
	LogMsg "$msg"
	UpdateSummary "$msg"
	SetTestStateFailed
	exit 10
fi

# check modinfo
modinfo hv_balloon >/dev/null 2>&1

if [ 0 -ne $? ]; then
	msg="The kernel module hv_balloon is not found by modinfo"
	LosgMsg "$msg"
	UpdateSummary "$msg"
	SetTestStateFailed
	exit 10
fi

# all good
UpdateSummary "Test successful"
LogMsg "Updating test case state to completed"
SetTestStateCompleted
exit 0