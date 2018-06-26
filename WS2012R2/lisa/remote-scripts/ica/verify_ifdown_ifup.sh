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
TestCount=""
REMOTE_SERVER="8.8.4.4"
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

	CreateIfupConfigFile "$NetInterface" "dhcp"

	if [ 0 -ne $? ]; then
		msg="Unable to get address for $NetInterface through DHCP"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi

	LogMsg "$(ip -o addr show $NetInterface | grep -vi inet6)"
	
PingCheck()
{
	ping -I eth0 $REMOTE_SERVER -c 4
	if [ 0 -ne $? ]; then
		msg="Ping eth0 could not be performed. Test Failed."
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 1
	else
		msg="Ping eth0 : Passed"
		LogMsg "$msg"
		UpdateSummary "$msg"
	fi
}
RestartNetwork()
{
GetDistro
case $DISTRO in
	centos_7*|redhat_7*|fedora*)
	ifup eth0
	if [ 0 -ne $? ]; then
		msg="Bringing up eth0 could not be performed. Attempting to restart network."
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
			msg="First ping eth0 : Passed"
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
			msg="Ping eth0 : Passed"
			LogMsg "$msg"
		fi
	else
		msg="Ping eth0 : Passed"
		LogMsg "$msg"
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
		msg="Ping eth0 : Passed"
		LogMsg "$msg"
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
			msg="Attempting to bring up eth0"
			LogMsg "$msg"
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
			msg="Second ping eth0 : Passed"
			LogMsg "$msg"
		fi
	else
		msg="First ping eth0 : Passed"
		LogMsg "$msg"
	fi
	;;
	*suse*)
	ifup eth0
	if [ 0 -ne $? ]; then
		msg="Bringing up eth0 could not be performed. Attempting to reload hv_netvsc."
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
			msg="First ping eth0 : Passed"
			LogMsg "$msg"
		fi
	fi
	;;
esac	
}

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
		msg="Ifdown eth0 : Passed"
		LogMsg "$msg"
	fi
else
	msg="Ifdown eth0 : Passed"
	LogMsg "$msg"  
fi

TestCount=0
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
			msg="Ifdown $NetInterface  : Passed"
			LogMsg "$msg"
		fi
	else
		msg="Ifdown $NetInterface  : Passed"
		LogMsg "$msg"  
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
		msg="modprobe -r hv_netvsc : Passed"
		LogMsg "$msg"
	fi
	modprobe hv_netvsc
	if [ 0 -ne $? ]; then
		msg="modprobe hv_netvsc : Failed"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 1
	else
		msg="modprobe hv_netvsc : Passed"
		LogMsg "$msg"
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
			msg="Ifup $NetInterface : Passed"
			LogMsg "$msg"
		fi
	else
		msg="Ifup $NetInterface : Passed"
		LogMsg "$msg"  
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
		msg="Ping $NetInterface : Passed"
		LogMsg "$msg"
	fi
RestartNetwork
LogMsg "#########################################################"
LogMsg "Result : Test Completed Successfully"
SetTestStateCompleted
