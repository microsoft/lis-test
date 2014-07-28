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
#	This script verifies that when a network adapter is added to a virtual machine and that its IP address can be manipulated, without loosing connectivity. 
#
#	Steps:
#	1. Verify configuration file constants.sh
#	2. Determine synthetic network interfaces
#	3. Set static IP
#		3a. If configured, try to ping remote server
#	4. Get IP through DHCP
#		4a. If configured, try to ping remote server
#
#	The test is successful if at least one synthetic network adapter is able to assign a static ip, 
#	as well as receive an IP address from a dhcp server (and ping the remote server, if configured)
#
#	Parameters required:
#		STATIC_IP
#
#	Optional parameters:
#		TC_COVERED
#		NETMASK
#		REMOTE_SERVER
#		DISABLE_NM
#		GATEWAY
#
#	Parameter explanation:
#	STATIC_IP is the address that will be assigned to the VM's synthetic network adapter
#	NETMASK of this VM's subnet. Defaults to /24 if not set.
#	REMOTE_SERVER is an IP address of a ping-able machine, to test network connectivity
#	DISABLE_NM can be set to 'yes' to disable the NetworkManager.
#	GATEWAY is the IP Address of the default gateway
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

# Parameter provided in constants file

if [ "${STATIC_IP:-UNDEFINED}" = "UNDEFINED" ]; then
	msg="The test parameter STATIC_IP is not defined in constants file"
	LogMsg "$msg"
	UpdateSummary "$msg"
	SetTestStateAborted
	exit 30
fi

# Validate that $STATIC_IP is the correct format
CheckIP "$STATIC_IP"

if [ 0 -ne $? ]; then
	msg="Variable STATIC_IP: $STATIC_IP does not contain a valid IPv4 address "
	LogMsg "$msg"
	UpdateSummary "$msg"
	SetTestStateAborted
	exit 30
fi

if [ "${NETMASK:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter NETMASK is not defined in constants file . Defaulting to 255.255.255.0"
    LogMsg "$msg"
	NETMASK=255.255.255.0
fi

if [ "${REMOTE_SERVER:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter REMOTE_SERVER is not defined in constants file . No network connectivity test will be performed"
    LogMsg "$msg"
	REMOTE_SERVER=''
fi

# set gateway parameter
if [ "${GATEWAY:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter GATEWAY is not defined in constants file . No default gateway will be set for any interface."
    LogMsg "$msg"
	GATEWAY=''
else
	CheckIP "$GATEWAY"
	
	if [ 0 -ne $? ]; then
		msg=""
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateAborted
		exit 10
	fi
fi

declare __iface_ignore

# Parameter provided in constants file
if [ "${ipv4:-UNDEFINED}" = "UNDEFINED" ]; then
	msg="The test parameter ipv4 is not defined in constants file! Make sure you are using the latest LIS code."
	LogMsg "$msg"
	UpdateSummary "$msg"
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
	__iface_ignore=$(ip -o addr show| grep "$ipv4" | cut -d ' ' -f2)
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
				__orig_netmask=$(ip -o addr show | grep "$ipv4" | cut -d '/' -f2 | cut -d ' ' -f1)
				;;
		esac
		DisableNetworkManager
		case "$DISTRO" in
			suse*)
				ip link set "$__iface_ignore" down
				ip addr flush dev "$__iface_ignore"
				ip addr add "$ipv4"/"$__orig_netmask" dev "$__iface_ignore"
				ip link set "$__iface_ignore" up
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
declare -ai __invalid_positions
for __iterator in "${!SYNTH_NET_INTERFACES[@]}"; do
	ip link show "${SYNTH_NET_INTERFACES[$__iterator]}" >/dev/null 2>&1
	if [ 0 -ne $? ]; then
		# mark invalid positions
		__invalid_positions=("${__invalid_positions[@]}" "$__iterator")
		LogMsg "Warning synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]} is unusable"
	fi
done

if [ ${#SYNTH_NET_INTERFACES[@]} -eq  ${#__invalid_positions[@]} ]; then
	msg="No usable synthetic interface remains"
	LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

# reset iterator and remove invalid positions from array
__iterator=0
while [ $__iterator -lt ${#__invalid_positions[@]} ]; do
	# eliminate from SYNTH_NET_INTERFACES array the interface located on position ${__invalid_positions[$__iterator]}
	SYNTH_NET_INTERFACES=("${SYNTH_NET_INTERFACES[@]:0:${__invalid_positions[$__iterator]}}" "${SYNTH_NET_INTERFACES[@]:$((${__invalid_positions[$__iterator]}+1))}")
	: $((__iterator++))
done

# delete array
unset __invalid_positions

if [ 0 -eq ${#SYNTH_NET_INTERFACES[@]} ]; then
	msg="This should not have happened. Probable internal error above line $LINENO"
	LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 100
fi


declare -ai __invalid_positions
__iterator=0

# set synthetic interface address to $STATIC_IP
while [ $__iterator -lt ${#SYNTH_NET_INTERFACES[@]} ]; do
	SetIPstatic "$STATIC_IP" "${SYNTH_NET_INTERFACES[$__iterator]}" "$NETMASK"
	# if successfully assigned address
	if [ 0 -eq $? ]; then
		UpdateSummary "Successfully assigned $STATIC_IP ($NETMASK) to synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
		# add some interface output
		LogMsg "$(ip -o addr show ${SYNTH_NET_INTERFACES[$__iterator]} | grep -vi inet6)"
		# if configured, try to ping $REMOTE_SERVER
		if [ -n "$REMOTE_SERVER" ]; then
			if [ -n "$GATEWAY" ]; then
				LogMsg "Setting $GATEWAY as default gateway on dev ${SYNTH_NET_INTERFACES[$__iterator]}"
				CreateDefaultGateway "$GATEWAY" "${SYNTH_NET_INTERFACES[$__iterator]}"
				if [ 0 -ne $? ]; then
					LogMsg "Warning! Failed to set default gateway!"
				fi
			fi
			
			LogMsg "Trying to ping $REMOTE_SERVER"
			UpdateSummary "Trying to ping $REMOTE_SERVER"
			# ping the remote host using an easily distinguishable pattern 0xcafed00d`null`con`null`static`null`
			ping -I "${SYNTH_NET_INTERFACES[$__iterator]}" -c 10 -p "cafed00d00636f6e0073746174696300" "$REMOTE_SERVER" >/dev/null 2>&1
			if [ 0 -eq $? ]; then
				# ping worked!
				UpdateSummary "Successfully pinged $REMOTE_SERVER on synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
				break
			else
				LogMsg "Unable to ping $REMOTE_SERVER through ${SYNTH_NET_INTERFACES[$__iterator]}"
				UpdateSummary "Unable to ping $REMOTE_SERVER through ${SYNTH_NET_INTERFACES[$__iterator]}"
			fi
		else #nothing more to do
			break
		fi
	else
		LogMsg "Unable to set static IP to interface ${SYNTH_NET_INTERFACES[$__iterator]}"
		UpdateSummary "Unable to set static IP to interface ${SYNTH_NET_INTERFACES[$__iterator]}"
	fi
	# shut interface down
	ip link set ${SYNTH_NET_INTERFACES[$__iterator]} down
	: $((__iterator++))
done

if [ ${#SYNTH_NET_INTERFACES[@]} -eq $__iterator ]; then
	msg="Unable to set static address (and ping if REMOTE_SERVER was given) to ${SYNTH_NET_INTERFACES[@]}"
	LogMsg "$msg"
	UpdateSummary "$msg"
	SetTestStateFailed
	exit 10
fi

LogMsg "Synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]} successfully set the static IP address (and pinged if the REMOTE_SERVER variable was given)"

# Try to get DHCP address
LogMsg "Trying to get an IP Address via DHCP on interface ${SYNTH_NET_INTERFACES[$__iterator]}"

SetIPfromDHCP "${SYNTH_NET_INTERFACES[$__iterator]}"

# If we fail, we do not try other (if any) synthetic netadapters
if [ 0 -ne $? ]; then
	msg="Unable to get address for ${SYNTH_NET_INTERFACES[$__iterator]} through DHCP"
	LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi
# add some interface output
LogMsg "$(ip -o addr show ${SYNTH_NET_INTERFACES[$__iterator]} | grep -vi inet6)"

# Get IP-Address and check it
IP_ADDRESS=$(ip -o addr show "${SYNTH_NET_INTERFACES[$__iterator]}" | grep -vi inet6 | cut -d '/' -f1 | awk '{print $NF}' | grep -vi '[a-z]')

CheckIP "$IP_ADDRESS"

if [ 0 -ne $? ]; then
	msg="Invalid ip address $IP_ADDRESS received on ${SYNTH_NET_INTERFACES[$__iterator]} through DHCP"
	LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

LogMsg "Successfully received $IP_ADDRESS through DHCP"

# If configured, try to ping $REMOTE_SERVER
if [ -n "$REMOTE_SERVER" ]; then
	if [ -n "$GATEWAY" ]; then
		LogMsg "Setting $GATEWAY as default gateway on dev ${SYNTH_NET_INTERFACES[$__iterator]}"
		CreateDefaultGateway "$GATEWAY" "${SYNTH_NET_INTERFACES[$__iterator]}"
		if [ 0 -ne $? ]; then
			LogMsg "Warning! Failed to set default gateway!"
		fi
	fi
	
	LogMsg "Trying to ping $REMOTE_SERVER"
	UpdateSummary "Trying to ping $REMOTE_SERVER"
	# ping the remote host using an easily distinguishable pattern 0xcafed00d`null`conf`null`dhcp`null`
	ping -I ${SYNTH_NET_INTERFACES[$__iterator]} -c 10 -p "cafed00d00636f6e66006468637000" $REMOTE_SERVER >/dev/null 2>&1
	if [ 0 -ne $? ]; then
		msg="Unable to ping $REMOTE_SERVER through ${SYNTH_NET_INTERFACES[$__iterator]}"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi
	LogMsg "Successfully pinged $REMOTE_SERVER with $IP_ADDRESS received through dhcp"
	UpdateSummary "Successfully pinged $REMOTE_SERVER with $IP_ADDRESS received through dhcp"
fi

UpdateSummary "Test successful"
LogMsg "Updating test case state to completed"
SetTestStateCompleted
exit 0