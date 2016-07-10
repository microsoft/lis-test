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
#	This script verifies that the status of some values of with ethtool.
#
#	Steps:
#	1. Verify configuration file constants.sh
#	2. Determine interface(s) to check
#	3. Check TSO,  scatter-gather rx-checksumming and tx-checksumming
#
#	The test is successful if all interfaces are on.
#
#	No parameters required.
#
#	Optional parameters:
#		TC_COVERED
#
#	Parameter explanation:
#	TC_COVERED is the LIS testcase number
#
#
#############################################################################################################


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

GetDistro

case $DISTRO in
    "redhat_7")
       msg="Checking keys with ethtool ......"
       LogMsg "${msg}"
       UpdateSummary "${msg}"
    ;;
   "ubuntu_x")
       msg="Failed: No ubuntu specific code to test case"
       LogMsg "${msg}"
       UpdateSummary "${msg}"
       UpdateTestState $ICA_TESTABORTED
       exit 1
    ;;
    "suse_x")
       msg="Failed: No SUSE specific code to test case"
       LogMsg "${msg}"
       UpdateSummary "${msg}"
       UpdateTestState $ICA_TESTABORTED
       exit 1
     ;;
     *)
       LogMsg "WARNING: Distro '${distro}' not supported."
       UpdateSummary "WARNING: Distro '${distro}' not supported."
       UpdateTestState $ICA_TESTABORTED
       exit 1
    ;;
esac

declare __iface_ignore

# Parameter provided in constants file
if [ "${ipv4:-UNDEFINED}" = "UNDEFINED" ]; then
	msg="The test parameter ipv4 is not defined in constants file! Make sure you are using the latest LIS code."
	LogMsg "$msg"
	UpdateSummary "$msg"
	SetTestStateFailed
    exit 10
else

	CheckIP "$ipv4"

	if [ 0 -ne $? ]; then
		msg="Test parameter ipv4 = $ipv4 is not a valid IP Address"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi

	# Get the interface associated with the given ipv4
	__iface_ignore=$(ip -o addr show | grep "$ipv4" | cut -d ' ' -f2)
fi

# Retrieve synthetic network interfaces
GetSynthNetInterfaces

declare -a ETHTOOL_KEYS
ETHTOOL_KEYS=("tcp-segmentation-offload" "scatter-gather" "rx-checksumming" "tx-checksumming")

if [ 0 -ne $? ]; then
	msg="Warning, no synthetic network interfaces found"
	LogMsg "$msg"
else
	# Remove interface if present
	SYNTH_NET_INTERFACES=(${SYNTH_NET_INTERFACES[@]/$__iface_ignore/})

	if [ ${#SYNTH_NET_INTERFACES[@]} -eq 0 ]; then
		msg="The only synthetic interface is the one which LIS uses to send files/commands to the VM."
		LogMsg "$msg"
		UpdateSummary "$msg"
	fi

	LogMsg "Found ${#SYNTH_NET_INTERFACES[@]} synthetic interface(s): ${SYNTH_NET_INTERFACES[*]} in VM"

	declare __synth_iface

	for __synth_iface in ${SYNTH_NET_INTERFACES[@]}; do
        ethtool -k $__synth_iface
        if [ $? -ne 0 ]; then
            msg="Can't get the related value of synthetic network adapter with ethtool"
            LogMsg "${msg}"
			UpdateSummary "$msg"
			SetTestStateFailed
            exit 10
        fi

        for __key in ${ETHTOOL_KEYS[@]}; do
            value=$(ethtool -k $__synth_iface |grep $__key |awk -F " " '{print $2}')
            if [ $value != "on" ]; then
                msg="The ${__key} is not set as on"
                LogMsg "$msg"
                UpdateSummary "$msg"
			    SetTestStateFailed
                exit 10
            fi
        done    
		msg="The value of ${ETHTOOL_KEYS[@]} are set right"
		LogMsg "$msg"
		UpdateSummary "$msg"
	done
fi

# everything ok
UpdateSummary "Test successful"
LogMsg "Updating test case state to completed"
SetTestStateCompleted
exit 0
