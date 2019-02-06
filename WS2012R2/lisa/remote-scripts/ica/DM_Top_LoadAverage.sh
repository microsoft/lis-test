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
#	This script verifies that with the Dynamic Memory enabled,
#	load average is lower than 1.
#	This is a regression test based on upstream commit
#	"Drivers: hv: Ballon: Make pressure posting thread sleep interruptibly"
#
#####################################################################

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
	echo "Error: unable to source utils.sh!"
	echo "TestAborted" > state.txt
	exit 2
}

# Source constants file and initialize most common variables
UtilsInit

# sleep 8 minutes then check result
sleep 480

# Check load aveage value of top command
load_average=(`top|head -n 1 | awk -F 'load average:' '{print $2}' | awk -F ',' '{print $1,$2,$3}'`)

threshold=1
for value in "${load_average[@]}"; do
	# use awk to compare the value and 1, if value < 1, return 0, else return 1
	echo "value is $value, threshold=$threshold"
	st=`echo "$value $threshold" | awk '{if ($1 < $2) print 0; else print 1}'`
    if [ $st -eq 1 ]; then
		msg="The load avearage value of top is too high: $value"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 1
	fi
done

UpdateSummary "Test successful"
LogMsg "Updating test case state to completed"
SetTestStateCompleted
exit 0
