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
#	This script verifies that all synthetic interfaces can ping an IP Address and cannot ping at least one IP Address.
#	Usually there is one ping-able address specified, that is on the same network as the interface(s) and two for
#	the other two network adapter types, which should not be ping-able.
#
#	Steps:
#	1. Verify configuration file constants.sh
#	2. Determine synthetic network interfaces
#	3. Set static IPs on interfaces
#		3a. If static IP is not configured, get address(es) via dhcp
#	4. Ping IPs
#
#	The test is successful if all available synthetic interfaces are able to ping the $PING_SUCC IP address
#	and fail to ping the $PING_FAIL IP address(es). One common test-scenario is to have an external network adapter
#	be able to ping an IP on the same external network, but fails to ping the internal network and the guest-only network.
#
#	Parameters required:
#		PING_SUCC
#		PING_FAIL
#
#
#	Optional parameters:
#		STATIC_IP
#		TC_COVERED
#		NETMASK
#		PING_FAIL2
#		DISABLE_NM
#		TC_COVERED
#
#	Parameter explanation:
#	STATIC_IP is the address that will be assigned to the VM's synthetic network adapter. Multiple Addresses can be specified
#	separated by , (comma) and they will be assigned in order to each interface found.
#	NETMASK of this VM's subnet. Defaults to /24 if not set.
#	PING_SUCC is an IP address of a ping-able machine, which should succeed
#	PING_FAIL is an IP address of a non-ping-able machine
#	PING_FAIL2 is an IP address of a non-ping-able machine
#	DISABLE_NM can be set to 'yes' to disable the NetworkManager.
#	TC_COVERED is the LIS testcase number
#
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

# Parameter provided in constants file
declare -a STATIC_IPS=()

if [ "${STATIC_IP:-UNDEFINED}" = "UNDEFINED" ]; then
	msg="The test parameter STATIC_IP is not defined in constants file. Will try to set addresses via dhcp"
	LogMsg "$msg"
else

	# Split (if necessary) IP Adddresses based on , (comma)
	IFS=',' read -a STATIC_IPS <<< "$STATIC_IP"

	declare -i __iterator
	# Validate that $STATIC_IP is the correct format
	for __iterator in ${!STATIC_IPS[@]}; do

		CheckIP "${STATIC_IPS[$__iterator]}"

		if [ 0 -ne $? ]; then
			msg="Variable STATIC_IP: ${STATIC_IPS[$__iterator]} does not contain a valid IPv4 address "
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateAborted
			exit 30
		fi
		
	done
	
	unset __iterator
	
fi

if [ "${NETMASK:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter NETMASK is not defined in constants file . Defaulting to 255.255.255.0"
    LogMsg "$msg"
	NETMASK=255.255.255.0
fi

if [ "${PING_SUCC:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter PING_SUCC is not defined in constants file"
    LogMsg "$msg"
	UpdateSummary "$msg"
	SetTestStateAborted
	exit 30
fi


if [ "${PING_FAIL:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter PING_FAIL is not defined in constants file"
    LogMsg "$msg"
	UpdateSummary "$msg"
	SetTestStateAborted
	exit 30
fi

if [ "${PING_FAIL2:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter PING_FAIL2 is not defined in constants file."
    LogMsg "$msg"
fi

declare __iface_ignore

# Parameter provided in constants file
#	ipv4 is the IP Address of the interface used to communicate with the VM, which needs to remain unchanged
#	it is not touched during this test (no dhcp or static ip assigned to it)

if [ "${ipv4:-UNDEFINED}" = "UNDEFINED" ]; then
	msg="The test parameter ipv4 is not defined in constants file! Make sure you are using the latest LIS code."
	LogMsg "$msg"
	UpdateSummary "$msg"
	SetTestStateAborted
	exit 30
else

	CheckIP "$ipv4"

	if [ 0 -ne $? ]; then
		msg="Test parameter ipv4 = $ipv4 is not a valid IP Address"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateAborted
		exit 10
	fi
	
	# Get the interface associated with the given ipv4
	__iface_ignore=$(ifconfig -a | grep -B1 "$ipv4" | head -n 1 | cut -d ' ' -f1)
fi

if [ "${DISABLE_NM:-UNDEFINED}" = "UNDEFINED" ]; then
	msg="The test parameter DISABLE_NM is not defined in constants file. If the NetworkManager is running it could interfere with the test."
	LogMsg "$msg"
else
	if [[ "$DISABLE_NM" =~ [Yy][Ee][Ss] ]]; then
		
		# work-around for suse where the network gets restarted in order to shutdown networkmanager.
		declare __orig_netmask
		GetDistro
		case "$DISTRO" in
			suse*)
				__orig_netmask=$(ifconfig "$__iface_ignore" | awk '/Mask:/{ print $4;} ' | cut -c6-)
				;;
		esac
		DisableNetworkManager
		case "$DISTRO" in
			suse*)
				ifconfig "$__iface_ignore" down
				ifconfig "$__iface_ignore" "$ipv4" netmask "$__orig_netmask"
				ifconfig "$__iface_ignore" up
				;;
		esac
	fi
fi

# Retrieve synthetic network interfaces
GetSynthNetInterfaces

if [ 0 -ne $? ]; then
    msg="No synthetic network interfaces found"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

# Remove interface if present
SYNTH_NET_INTERFACES=(${SYNTH_NET_INTERFACES[@]/$__iface_ignore/})

if [ ${#SYNTH_NET_INTERFACES[@]} -eq 0 ]; then
	msg="The only synthetic interface is the one which LIS uses to send files/commands to the VM."
	LogMsg "$msg"
	UpdateSummary "$msg"
	SetTestStateAborted
	exit 10
fi


LogMsg "Found ${#SYNTH_NET_INTERFACES[@]} synthetic interface(s): ${SYNTH_NET_INTERFACES[*]} in VM"

# Test interfaces
declare -i __iterator
for __iterator in "${!SYNTH_NET_INTERFACES[@]}"; do
	ifconfig "${SYNTH_NET_INTERFACES[$__iterator]}" >/dev/null 2>&1
	if [ 0 -ne $? ]; then
		msg="Invalid synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 20
	fi
done

if [ ${#SYNTH_NET_INTERFACES[@]} -gt ${#STATIC_IPS[@]} ]; then
	LogMsg "No. of synthetic interfaces is greater than number of static IPs specified in constants file. Will use dhcp for ${SYNTH_NET_INTERFACES[@]:${#STATIC_IPS[@]}}"
fi

declare -i __iterator=0

# set static ips
for __iterator in ${!STATIC_IPS[@]} ; do

	# if number of static ips is greater than number of interfaces, just break.
	if [ "$__iterator" -ge "${#SYNTH_NET_INTERFACES[@]}" ]; then
		LogMsg "Number of static IP addresses in constants.sh is greater than number of concerned interfaces. All extra IP addresses are ignored."
		break
	fi
	SetIPstatic "${STATIC_IPS[$__iterator]}" "${SYNTH_NET_INTERFACES[$__iterator]}" "$NETMASK"
	# if failed to assigned address
	if [ 0 -ne $? ]; then
		msg="Failed to assign static ip ${STATIC_IPS[$__iterator]} netmask $NETMASK on interface ${SYNTH_NET_INTERFACES[$__iterator]}"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 20
	fi	
done

# set the iterator to point to the next element in the SYNTH_NET_INTERFACES array
__iterator=${#STATIC_IPS[@]}

# set dhcp ips for remaining interfaces
while [ $__iterator -lt ${#SYNTH_NET_INTERFACES[@]} ]; do

	SetIPfromDHCP "${SYNTH_NET_INTERFACES[$__iterator]}"
	
	if [ 0 -ne $? ]; then
		msg="Unable to get address for ${SYNTH_NET_INTERFACES[$__iterator]} through DHCP"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi
	
	: $((__iterator++))
	
done

# reset iterator
__iterator=0

for __iterator in ${!SYNTH_NET_INTERFACES[@]}; do

	# ping the right address
	ping -I ${SYNTH_NET_INTERFACES[$__iterator]} -c 10 "$PING_SUCC"

	if [ 0 -ne $? ]; then
		msg="Failed to ping $PING_SUCC on synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi
	
	# ping the wrong address. should not succeed
	ping -I ${SYNTH_NET_INTERFACES[$__iterator]} -c 10 "$PING_FAIL"
	if [ 0 -eq $? ]; then
		msg="Succeeded to ping $PING_FAIL on synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]} . Make sure you have the right PING_FAIL constant set"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi
	
	# ping the second wrong address, fi specified. should also not succeed
	if [ "${PING_FAIL2:-UNDEFINED}" != "UNDEFINED" ]; then
		ping -I ${SYNTH_NET_INTERFACES[$__iterator]} -c 10 "$PING_FAIL2"
		if [ 0 -eq $? ]; then
			msg="Succeeded to ping $PING_FAIL2 on synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]} . Make sure you have the right PING_FAIL2 constant set"
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			exit 10
		fi
	fi
	
done

# everything ok
UpdateSummary "Test successful"
LogMsg "Updating test case state to completed"
SetTestStateCompleted
exit 0