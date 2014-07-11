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
#	This script checks that a legacy and a synthetic network adapter work together, without causing network issues to the VM.
#	If there are more than one synthetic/legacy interfaces, it is enough for just one (of each type) to successfully ping the remote server.
#	If the IP_IGNORE Parameter is given, the interface which owns that given address will not be able to take part in the test and will only be used to communicate with LIS
#	
#	Steps:
#	1. Get legacy and synthetic network interfaces
#	2. Try to get DHCP addresses for each of them
#		2a. If no DHCP, try to set static IP
#	3. Try to ping REMOTE_SERVER from each interface
#
#
#	Parameters required:
#		REMOTE_SERVER
#
#	Optional parameters:
#		TC_COVERED
#		SYNTH_STATIC_IP
#		LEGACY_STATIC_IP
#		SYNTH_NETMASK
#		LEGACY_NETMASK
#		IP_IGNORE
#		LO_IGNORE
#		GATEWAY
#
#	Parameter explanation:
#		REMOTE_SERVER is the IP address of the remote server, pinged in the last step of the script
#		SYNTH_STATIC_IP is an optional IP address assigned to the synthetic netadapter interface in case none was received via DHCP
#		LEGACY_STATIC_IP is an optional IP address assigned to the legacy netadapter interface in case none was received via DHCP
#		SYNTH_NETMASK is an optional netmask used in case no address was assigned to the synthetic netadapter via DHCP
#		LEGACY_NETMASK is an optional netmask used in case no address was assigned to the legacy netadapter via DHCP
#		IP_IGNORE is the IP Address of an interface that is not touched during this test (no dhcp or static ip assigned to it)
#			- it can be used to specify the connection used to communicate with the VM, which needs to remain unchanged
#		LO_IGNORE is an optional argument used to indicate that the loopback interface lo is not to be used during the test (it is usually detected as a legacy interface)
#		GATEWAY is the IP Address of the default gateway
#		TC_COVERED is the testcase number
#
#
############################################################################

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
		# do nothing
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
if [ "${SYNTH_STATIC_IP:-UNDEFINED}" = "UNDEFINED" ]; then
	msg="The test parameter SYNTH_STATIC_IP is not defined in constants file"
	LogMsg "$msg"
else
	# Validate that $SYNTH_STATIC_IP is the correct format
	CheckIP "$SYNTH_STATIC_IP"
	if [ 0 -ne $? ]; then
		msg="Variable SYNTH_STATIC_IP: $SYNTH_STATIC_IP does not contain a valid IPv4 address "
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateAborted
		exit 30
	fi
fi

# Parameter provided in constants file
if [ "${LEGACY_STATIC_IP:-UNDEFINED}" = "UNDEFINED" ]; then
	msg="The test parameter LEGACY_STATIC_IP is not defined in constants file"
	LogMsg "$msg"
else
	# Validate that $LEGACY_STATIC_IP is the correct format
	CheckIP "$LEGACY_STATIC_IP"
	if [ 0 -ne $? ]; then
		msg="Variable LEGACY_STATIC_IP: $LEGACY_STATIC_IP does not contain a valid IPv4 address "
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateAborted
		exit 30
	fi
fi

# Parameter provided in constants file
if [ "${SYNTH_NETMASK:-UNDEFINED}" = "UNDEFINED" ]; then
	msg="The test parameter SYNTH_NETMASK is not defined in constants file . Defaulting to 255.255.255.0"
	LogMsg "$msg"
	SYNTH_NETMASK=255.255.255.0
fi

# Parameter provided in constants file
if [ "${LEGACY_NETMASK:-UNDEFINED}" = "UNDEFINED" ]; then
	msg="The test parameter LEGACY_NETMASK is not defined in constants file . Defaulting to 255.255.255.0"
	LogMsg "$msg"
	LEGACY_NETMASK=255.255.255.0
fi

# Parameter provided in constants file
if [ "${REMOTE_SERVER:-UNDEFINED}" = "UNDEFINED" ]; then
	msg="The mandatory test parameter REMOTE_SERVER is not defined in constants file! Aborting..."
	LogMsg "$msg"
	UpdateSummary "$msg"
	SetTestStateAborted
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
	
	# Get the interface associated with the given IP_IGNORE
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

declare __lo_ignore

if [ "${LO_IGNORE:-UNDEFINED}" = "UNDEFINED" ]; then
	msg="The test parameter LO_IGNORE is not defined in constants file! The loopback interface may be used during the test."
	LogMsg "$msg"
	__lo_ignore=''
else

	ip link show lo >/dev/null 2>&1

	if [ 0 -ne $? ]; then
		msg="The loopback interface is not working"
		LogMsg "$msg"
	else
		__lo_ignore=lo
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

# Test interface
declare -i __synth_iterator
declare -ai __invalid_positions
for __synth_iterator in "${!SYNTH_NET_INTERFACES[@]}"; do
	ip link show "${SYNTH_NET_INTERFACES[$__synth_iterator]}" >/dev/null 2>&1
	if [ 0 -ne $? ]; then
		__invalid_positions=("${__invalid_positions[@]}" "$__synth_iterator")
		LogMsg "Warning synthetic interface ${SYNTH_NET_INTERFACES[$__synth_iterator]} is unusable"
	fi
done

if [ ${#SYNTH_NET_INTERFACES[@]} -eq  ${#__invalid_positions[@]} ]; then
	msg="No usable synthetic interface remains. "
	LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

# reset iterator and remove invalid positions from array
__synth_iterator=0
while [ $__synth_iterator -lt ${#__invalid_positions[@]} ]; do
	# eliminate from SYNTH_NET_INTERFACES array the interface located on position ${__invalid_positions[$__synth_iterator]}
	SYNTH_NET_INTERFACES=("${SYNTH_NET_INTERFACES[@]:0:${__invalid_positions[$__synth_iterator]}}" "${SYNTH_NET_INTERFACES[@]:$((${__invalid_positions[$__synth_iterator]}+1))}")
	: $((__synth_iterator++))
done

# delete array
unset __invalid_positions

if [ 0 -eq ${#SYNTH_NET_INTERFACES[@]} ]; then
	# array is empty... but we checked for this case above
	msg="This should not have happened. Probable internal error above line $LINENO"
	LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 100
fi

# Get the legacy netadapter interface
GetLegacyNetInterfaces

if [ 0 -ne $? ]; then
	msg="No legacy network interfaces found"
	LogMsg "$msg"
	UpdateSummary "$msg"
	SetTestStateFailed
	exit 10
fi


# Remove loopback interface if LO_IGNORE is set

LEGACY_NET_INTERFACES=(${LEGACY_NET_INTERFACES[@]/$__lo_ignore/})

if [ ${#LEGACY_NET_INTERFACES[@]} -eq 0 ]; then
	msg="The only legacy interface is the loopback interface lo, which was set to be ignored."
	LogMsg "$msg"
	UpdateSummary "$msg"
	SetTestStateAborted
	exit 10
fi


# Remove interface if present
LEGACY_NET_INTERFACES=(${LEGACY_NET_INTERFACES[@]/$__iface_ignore/})

if [ ${#LEGACY_NET_INTERFACES[@]} -eq 0 ]; then
	msg="The only legacy interface is the one which LIS uses to send files/commands to the VM."
	LogMsg "$msg"
	UpdateSummary "$msg"
	SetTestStateAborted
	exit 10
fi

LogMsg "Found ${#LEGACY_NET_INTERFACES[@]} legacy interface(s): ${LEGACY_NET_INTERFACES[*]} in VM"

# Test interface
declare -i __legacy_iterator
declare -ai __invalid_positions
for __legacy_iterator in "${!LEGACY_NET_INTERFACES[@]}"; do
	ip link show "${LEGACY_NET_INTERFACES[$__legacy_iterator]}" >/dev/null 2>&1
	if [ 0 -ne $? ]; then
		# add current position to __invalid_positions array
		__invalid_positions=("${__invalid_positions[@]}" "$__legacy_iterator")
		LogMsg "Warning legacy interface ${LEGACY_NET_INTERFACES[$__legacy_iterator]} is unusable"
	fi
done

if [ ${#LEGACY_NET_INTERFACES[@]} -eq  ${#__invalid_positions[@]} ]; then
	msg="No usable legacy interface remains"
	LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

# reset iterator and remove invalid positions from array
__legacy_iterator=0
while [ $__legacy_iterator -lt ${#__invalid_positions[@]} ]; do
	LEGACY_NET_INTERFACES=("${LEGACY_NET_INTERFACES[@]:0:${__invalid_positions[$__legacy_iterator]}}" "${LEGACY_NET_INTERFACES[@]:$((${__invalid_positions[$__legacy_iterator]}+1))}")
	: $((__legacy_iterator++))
done

# delete array
unset __invalid_positions

if [ 0 -eq ${#LEGACY_NET_INTERFACES[@]} ]; then
	# array is empty... but we checked for this case above
	msg="This should not have happened. Probable internal error above line $LINENO"
	LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 100
fi

__synth_iterator=0
# Try to get DHCP address for synthetic adaptor and ping if configured
while [ $__synth_iterator -lt ${#SYNTH_NET_INTERFACES[@]} ]; do

	LogMsg "Trying to get an IP Address via DHCP on synthetic interface ${SYNTH_NET_INTERFACES[$__synth_iterator]}"
	SetIPfromDHCP "${SYNTH_NET_INTERFACES[$__synth_iterator]}"
	
	if [ 0 -eq $? ]; then		
	
		if [ -n "$GATEWAY" ]; then
			LogMsg "Setting $GATEWAY as default gateway on dev ${SYNTH_NET_INTERFACES[$__synth_iterator]}"
			CreateDefaultGateway "$GATEWAY" "${SYNTH_NET_INTERFACES[$__synth_iterator]}"
			if [ 0 -ne $? ]; then
				LogMsg "Warning! Failed to set default gateway!"
			fi
		fi
		
		LogMsg "Trying to ping $REMOTE_SERVER from synthetic interface ${SYNTH_NET_INTERFACES[$__synth_iterator]}"
		UpdateSummary "Trying to ping $REMOTE_SERVER from synthetic interface ${SYNTH_NET_INTERFACES[$__synth_iterator]}"
		
		# ping the remote host using an easily distinguishable pattern 0xcafed00d`null`syn`null`dhcp`null`
		ping -I "${SYNTH_NET_INTERFACES[$__synth_iterator]}" -c 10 -p "cafed00d0073796e006468637000" "$REMOTE_SERVER" >/dev/null 2>&1
		if [ 0 -eq $? ]; then
			# ping worked! Do not test any other interface
			LogMsg "Successfully pinged $REMOTE_SERVER through synthetic ${SYNTH_NET_INTERFACES[$__synth_iterator]} (dhcp)."
			UpdateSummary "Successfully pinged $REMOTE_SERVER through synthetic ${SYNTH_NET_INTERFACES[$__synth_iterator]} (dhcp)."
			break
		else
			LogMsg "Unable to ping $REMOTE_SERVER through synthetic ${SYNTH_NET_INTERFACES[$__synth_iterator]}"
			UpdateSummary "Unable to ping $REMOTE_SERVER through synthetic ${SYNTH_NET_INTERFACES[$__synth_iterator]}"
		fi
	fi
	# shut interface down
	ip link set ${SYNTH_NET_INTERFACES[$__synth_iterator]} down
	LogMsg "Unable to get address from dhcp server on synthetic interface ${SYNTH_NET_INTERFACES[$__synth_iterator]}"
	: $((__synth_iterator++))
done

# If all dhcp requests or ping failed, try to set static ip. 
if [ ${#SYNTH_NET_INTERFACES[@]} -eq $__synth_iterator ]; then
    if [ -z "$SYNTH_STATIC_IP" ]; then
		msg="No static IP Address provided for synthetic interfaces. DHCP failed. Unable to continue..."
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	else
		# reset iterator
		__synth_iterator=0
		while [ $__synth_iterator -lt ${#SYNTH_NET_INTERFACES[@]} ]; do
		
			SetIPstatic "$SYNTH_STATIC_IP" "${SYNTH_NET_INTERFACES[$__synth_iterator]}" "$SYNTH_NETMASK"
			LogMsg "$(ip -o addr show ${SYNTH_NET_INTERFACES[$__synth_iterator]} | grep -vi inet6)"
			
			if [ -n "$GATEWAY" ]; then
				LogMsg "Setting $GATEWAY as default gateway on dev ${SYNTH_NET_INTERFACES[$__synth_iterator]}"
				CreateDefaultGateway "$GATEWAY" "${SYNTH_NET_INTERFACES[$__synth_iterator]}"
				if [ 0 -ne $? ]; then
					LogMsg "Warning! Failed to set default gateway!"
				fi
			fi
			
			LogMsg "Trying to ping $REMOTE_SERVER"
			UpdateSummary "Trying to ping $REMOTE_SERVER"
			# ping the remote host using an easily distinguishable pattern 0xcafed00d`null`syn`null`static`null`
			ping -I "${SYNTH_NET_INTERFACES[$__synth_iterator]}" -c 10 -p "cafed00d0073796e0073746174696300" "$REMOTE_SERVER" >/dev/null 2>&1
			if [ 0 -eq $? ]; then
				# ping worked! Remove working element from __invalid_positions list
				LogMsg "Successfully pinged $REMOTE_SERVER through synthetic ${SYNTH_NET_INTERFACES[$__synth_iterator]} (static)."
				UpdateSummary "Successfully pinged $REMOTE_SERVER through synthetic ${SYNTH_NET_INTERFACES[$__synth_iterator]} (static)."
				break
			else
				LogMsg "Unable to ping $REMOTE_SERVER through synthetic ${SYNTH_NET_INTERFACES[$__synth_iterator]}"
				UpdateSummary "Unable to ping $REMOTE_SERVER through synthetic ${SYNTH_NET_INTERFACES[$__synth_iterator]}"
			fi
			: $((__synth_iterator++))
		done
		
		if [ ${#SYNTH_NET_INTERFACES[@]} -eq $__synth_iterator ]; then
			msg="Unable to set neither static address for synthetic interface(s) ${SYNTH_NET_INTERFACES[@]}"
			LogMsg "msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			exit 10
		fi
	fi
fi

# Try to get DHCP address for legacy adaptor

__legacy_iterator=0

while [ $__legacy_iterator -lt ${#LEGACY_NET_INTERFACES[@]} ]; do
	LogMsg "Trying to get an IP Address via DHCP on legacy interface ${LEGACY_NET_INTERFACES[$__legacy_iterator]}"
	SetIPfromDHCP "${LEGACY_NET_INTERFACES[$__legacy_iterator]}"
	
	if [ 0 -eq $? ]; then
		if [ -n "$GATEWAY" ]; then
			LogMsg "Setting $GATEWAY as default gateway on dev ${LEGACY_NET_INTERFACES[$__legacy_iterator]}"
			CreateDefaultGateway "$GATEWAY" "${LEGACY_NET_INTERFACES[$__legacy_iterator]}"
			if [ 0 -ne $? ]; then
				LogMsg "Warning! Failed to set default gateway!"
			fi
		fi
		
		LogMsg "Trying to ping $REMOTE_SERVER from legacy interface ${LEGACY_NET_INTERFACES[$__legacy_iterator]}"
		UpdateSummary "Trying to ping $REMOTE_SERVER from legacy interface ${LEGACY_NET_INTERFACES[$__legacy_iterator]}"
		
		# ping the remote host using an easily distinguishable pattern 0xcafed00d`null`leg`null`dhcp`null`
		ping -I "${LEGACY_NET_INTERFACES[$__legacy_iterator]}" -c 10 -p "cafed00d006c6567006468637000" "$REMOTE_SERVER" >/dev/null 2>&1
		if [ 0 -eq $? ]; then
			# ping worked!
			LogMsg "Successfully pinged $REMOTE_SERVER through legacy ${LEGACY_NET_INTERFACES[$__legacy_iterator]} (dhcp)."
			UpdateSummary "Successfully pinged $REMOTE_SERVER through legacy ${LEGACY_NET_INTERFACES[$__legacy_iterator]} (dhcp)."
			break
		else
			LogMsg "Unable to ping $REMOTE_SERVER through legacy ${LEGACY_NET_INTERFACES[$__legacy_iterator]}"
			UpdateSummary "Unable to ping $REMOTE_SERVER through legacy ${LEGACY_NET_INTERFACES[$__legacy_iterator]}"
		fi
	fi
	# shut interface down
	ip link set ${LEGACY_NET_INTERFACES[$__legacy_iterator]} down
	LogMsg "Unable to get address from dhcp server on legacy interface ${LEGACY_NET_INTERFACES[$__legacy_iterator]}"
	: $((__legacy_iterator++))
done


# If dhcp failed, try to set static ip
if [ ${#LEGACY_NET_INTERFACES[@]} -eq $__legacy_iterator ]; then
	msg="Unable to get address for legacy interface(s) ${LEGACY_NET_INTERFACES[@]} through DHCP"
	LogMsg "$msg"
    if [ -z "$LEGACY_STATIC_IP" ]; then
		msg="No static IP Address provided for legacy interfaces. DHCP failed. Unable to continue..."
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	else
		# reset iterator
		__legacy_iterator=0
		while [ $__legacy_iterator -lt ${#LEGACY_NET_INTERFACES[@]} ]; do
		
			SetIPstatic "$LEGACY_STATIC_IP" "${LEGACY_NET_INTERFACES[$__legacy_iterator]}" "$LEGACY_NETMASK"
			LogMsg "$(ip -o addr show ${LEGACY_NET_INTERFACES[$__legacy_iterator]} | grep -vi inet6)"
			
			if [ -n "$GATEWAY" ]; then
				LogMsg "Setting $GATEWAY as default gateway on dev ${LEGACY_NET_INTERFACES[$__legacy_iterator]}"
				CreateDefaultGateway "$GATEWAY" "${LEGACY_NET_INTERFACES[$__legacy_iterator]}"
				if [ 0 -ne $? ]; then
					LogMsg "Warning! Failed to set default gateway!"
				fi
			fi
			
			LogMsg "Trying to ping $REMOTE_SERVER through legacy ${LEGACY_NET_INTERFACES[$__legacy_iterator]}"
			UpdateSummary "Trying to ping $REMOTE_SERVER through legacy ${LEGACY_NET_INTERFACES[$__legacy_iterator]}"
			# ping the remote host using an easily distinguishable pattern 0xcafed00d`null`leg`null`static`null`
			ping -I "${LEGACY_NET_INTERFACES[$__legacy_iterator]}" -c 10 -p "cafed00d006c65670073746174696300" "$REMOTE_SERVER" >/dev/null 2>&1
			if [ 0 -eq $? ]; then
				LogMsg "Successfully pinged $REMOTE_SERVER through legacy ${LEGACY_NET_INTERFACES[$__legacy_iterator]} (static)."
				UpdateSummary "Successfully pinged $REMOTE_SERVER through legacy ${LEGACY_NET_INTERFACES[$__legacy_iterator]} (static)."
				break
			else
				LogMsg "Unable to ping $REMOTE_SERVER through legacy ${LEGACY_NET_INTERFACES[$__legacy_iterator]}"
				UpdateSummary "Unable to ping $REMOTE_SERVER through legacy ${LEGACY_NET_INTERFACES[$__legacy_iterator]}"
			fi
			: $((__legacy_iterator++))
		done
		
		if [ ${#LEGACY_NET_INTERFACES[@]} -eq $__legacy_iterator ]; then
			msg="Unable to set neither static address for legacy interface(s) ${LEGACY_NET_INTERFACES[@]}"
			LogMsg "msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			exit 10
		fi
	fi
fi

UpdateSummary "Test successful"
LogMsg "Updating test case state to completed"
SetTestStateCompleted

exit 0