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

NetInterface="eth1"
REMOTE_SERVER="8.8.4.4"
TestCount=0
LoopCount=10

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

CreateIfupConfigFile "$NetInterface" "dhcp"
if [ 0 -ne $? ]; then
    msg="Unable to get address for $NetInterface through DHCP"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi
LogMsg "$(ip -o addr show $NetInterface | grep -vi inet6)"

PingCheck() {
	ping -I eth0 $REMOTE_SERVER -c 4
	if [ 0 -ne $? ]; then
		msg="Ping on eth0 could not be performed. Test Failed."
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 1
	else
		msg="Succesful ping on eth0 after ifdown/ifup"
		LogMsg "$msg"
		UpdateSummary "$msg"
	fi
}

RestartNetwork() {
GetDistro
case $DISTRO in
	redhat_7|redhat_8|centos_7|centos_8|fedora*)
	ifup eth0
	if [ 0 -ne $? ]; then
		msg="Could not bring up eth0. Attempting to restart network."
		LogMsg "$msg"
		UpdateSummary "$msg"
		systemctl restart network
		if [ 0 -ne $? ]; then
			msg="Restart network could not be performed. Test Failed."
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			exit 1
		fi
		PingCheck
	else
		ping -I eth0 $REMOTE_SERVER -c 4
		if [ 0 -ne $? ]; then
			msg="First ping could not be performed. Attempting to restart network."
			systemctl restart network
			if [ 0 -ne $? ]; then
				msg="Restart network could not be performed. Test Failed."
				LogMsg "$msg"
				UpdateSummary "$msg"
				SetTestStateFailed
				exit 1
			fi
			PingCheck
		else
			msg="Succesful first ping on eth0"
			LogMsg "$msg"
			UpdateSummary "$msg"
		fi
	fi
	;;

	centos_6*|redhat_6*)
	ifup eth0
	ping -I eth0 $REMOTE_SERVER -c 4
	if [ 0 -ne $? ]; then
		msg="The first ping did not work. Attempting to restart network."
		LogMsg "$msg"
		UpdateSummary "$msg"
		service network restart
		if [ 0 -ne $? ]; then
			msg="Restarting the network could not be performed. Test Failed."
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			exit 1
		fi
		ifup eth0
		ping -I eth0 $REMOTE_SERVER -c 4
		if [ 0 -ne $? ]; then
			modprobe -r hv_netvsc
			if [ 0 -ne $? ]; then
				msg="Unloading module hv_netvsc could not be performed. Test Failed."
				LogMsg "$msg"
				UpdateSummary "$msg"
				SetTestStateFailed
				exit 1
			fi
			modprobe hv_netvsc
			if [ 0 -ne $? ]; then
				msg="Unloading module hv_netvsc could not be performed. Test Failed."
				LogMsg "$msg"
				UpdateSummary "$msg"
				SetTestStateFailed
				exit 1
			fi
			ifup eth0
			PingCheck
		else
			LogMsg "Succesful ping on eth0 after ifdown/ifup"
		fi
	else
		LogMsg "Succesful ping on eth0 after ifdown/ifup"
	fi
	;;

	ubuntu*)
	ping -I eth0 $REMOTE_SERVER -c 4
	if [ 0 -ne $? ]; then
		msg="The first ping did not work. Attempting to restart network."
		LogMsg "$msg"
		UpdateSummary "$msg"
		systemctl restart networking
		if [ 0 -ne $? ]; then
			msg="Restart network could not be performed. Test Failed."
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			exit 1
		fi
		PingCheck
	else
		LogMsg "Succesful ping on eth0 after ifdown/ifup"
	fi
	;;

	debian*)
	ping -I eth0 $REMOTE_SERVER -c 4
	if [ 0 -ne $? ]; then
		msg="The first ping did not work. Attempting to reload module hv_netvsc."
		LogMsg "$msg"
		UpdateSummary "$msg"
		modprobe -r hv_netvsc
		if [ 0 -ne $? ]; then
			msg="Unloading module hv_netvsc could not be performed. Test Failed."
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			exit 1
		fi
		modprobe hv_netvsc
		if [ 0 -ne $? ]; then
			msg="Loading module hv_netvsc could not be performed. Test Failed."
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			exit 1
		fi
		ping -I eth0 $REMOTE_SERVER -c 4
		if [ 0 -ne $? ]; then
			LogMsg "Attempting to bring up eth0"
			ifup eth0
			if [ 0 -ne $? ]; then
				msg="Second ping did not work and bringing up eth0 could not be performed. Test Failed."
				LogMsg "$msg"
				UpdateSummary "$msg"
				SetTestStateFailed
				exit 1
			fi
			PingCheck
		else
			LogMsg "Second ping eth0 : Passed"
		fi
	else
		LogMsg "Succesful first ping on eth0"
	fi
	;;

	*suse*)
	ifup eth0
	if [ 0 -ne $? ]; then
		msg="Could not bring up eth0. Attempting to reload hv_netvsc."
		LogMsg "$msg"
		UpdateSummary "$msg"
		modprobe -r hv_netvsc
		if [ 0 -ne $? ]; then
			msg="Unloading the module hv_netvsc could not be performed. Test Failed."
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			exit 1
		fi
		modprobe hv_netvsc
		if [ 0 -ne $? ]; then
			msg="Loading the module hv_netvsc could not be performed. Test Failed."
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			exit 1
		fi
		ifup eth0
		if [ 0 -ne $? ]; then
			msg="Bringing up eth0 after module loading could not be performed. Test Failed."
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			exit 1
		fi
		PingCheck
	else
		ping -I eth0 $REMOTE_SERVER -c 4
		if [ 0 -ne $? ]; then
			msg="First ping could not be performed. Attempting to reload hv_netvsc."
			modprobe -r hv_netvsc
			if [ 0 -ne $? ]; then
				msg="Unloading module hv_netvsc could not be performed. Test Failed."
				LogMsg "$msg"
				UpdateSummary "$msg"
				SetTestStateFailed
				exit 1
			fi
			modprobe hv_netvsc 
				if [ 0 -ne $? ]; then
				msg="Loading module hv_netvsc could not be performed. Test Failed."
				LogMsg "$msg"
				UpdateSummary "$msg"
				SetTestStateFailed
				exit 1
			fi
			ifup eth0
			if [ 0 -ne $? ]; then
				msg="Bringing up eth0 after module loading could not be performed. Test Failed."
				LogMsg "$msg"
				UpdateSummary "$msg"
				SetTestStateFailed
				exit 1
			fi
			PingCheck
		else
			LogMsg "Succesful first ping on eth0"
		fi
	fi
	;;
esac
}

# Check for call traces during test run
dos2unix check_traces.sh && chmod +x check_traces.sh
./check_traces.sh &

# Bring down eth0 before entering the loop
ifdown eth0
if [ 0 -ne $? ]; then
	ip link set dev eth0 down
	if [ 0 -ne $? ]; then
		msg="Ifdown eth0 : Failed"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 1
	else
		LogMsg "Ifdown eth0 : Passed"
	fi
else
	LogMsg "Ifdown eth0 : Passed"
fi

while [ $TestCount -lt $LoopCount ]
do
	TestCount=$((TestCount+1))
	LogMsg "Test Iteration : $TestCount"
	ifdown $NetInterface

	if [ 0 -ne $? ]; then
		ip link set dev $NetInterface down
		if [ 0 -ne $? ]; then
			msg="Ifdown $NetInterface : Failed"
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			exit 1
		else
			LogMsg "Ifdown $NetInterface  : Passed"
		fi
	else
		LogMsg "Ifdown $NetInterface  : Passed"
	fi
	sleep 3

	modprobe -r hv_netvsc
	if [ 0 -ne $? ]; then
		msg="modprobe -r hv_netvsc : Failed"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 1
	else
		LogMsg "modprobe -r hv_netvsc : Passed"
	fi
	modprobe hv_netvsc
	if [ 0 -ne $? ]; then
		msg="modprobe hv_netvsc : Failed"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 1
	else
		LogMsg "modprobe hv_netvsc : Passed"
	fi

	ifup $NetInterface
	if [ 0 -ne $? ]; then
		ip link set dev $NetInterface up
		if [ 0 -ne $? ]; then
			msg="Ifup $NetInterface : Failed"
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			exit 1
		else
			LogMsg "Ifup $NetInterface : Passed"
		fi
	else
		LogMsg "Ifup $NetInterface : Passed"
	fi
	sleep 3
done

ping -I $NetInterface $REMOTE_SERVER -c 4
	if [ 0 -ne $? ]; then
		msg="Ping  $NetInterface : Failed"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 1
	else
		LogMsg "Ping $NetInterface : Passed"
	fi
RestartNetwork

LogMsg "#########################################################"
LogMsg "Result : Test Completed Successfully"
SetTestStateCompleted
