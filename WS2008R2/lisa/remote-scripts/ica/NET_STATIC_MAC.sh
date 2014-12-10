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
#	This script verifies that the static MAC assigned to a network adapter in Hyper-v is mirrored inside the VM.
#	After finding the corresponding interface for each (passed) MAC address, it will try to ping REMOTE_SERVER 
#	through it, if so configured. Both synthetic, as well as legacy network adapters are searched.
#
#	Steps:
#	1. Verify configuration file constants.sh
#	2. Determine interface(s) for static MAC address(es) passed
#	3. Set static IPs on these interfaces
#		3a. If static IP is not configured, get address(es) via dhcp
#	4. Ping REMOTE_SERVER
#
#	The test is successful if all MAC addresses passed to the script are assigned to a (different) interface and that 
#	each of these interfaces is able to ping the REMOTE_SERVER, if that parameter is specified.
#
#	Parameters required:
#		MAC
#
#	Optional parameters:
#		REMOTE_SERVER
#		STATIC_IP
#		TC_COVERED
#		NETMASK
#		IP_IGNORE
#		LO_IGNORE
#		GATEWAY
#
#	Parameter explanation:
#	MAC is the assigned MAC addresses in hyper-v, which must be found inside the VM. Multiple addresses can be specified, separated by , (comma)
#	and they will be searched in the order they are given. All need to be found inside the VM.
#	STATIC_IP is the address that will be assigned to the interface(s) corresponding to the given MAC. Multiple Addresses can be specified
#	separated by , (comma) and they will be assigned in order to each interface found.
#	NETMASK of this VM's subnet. Defaults to /24 if not set.
#	REMOTE_SERVER is an IP address of a ping-able machine. All interfaces found above will have to be able to ping this REMOTE_SERVER
#	IP_IGNORE is the IP Address of an interface that is not touched during this test (no dhcp or static ip assigned to it)
#			- it can be used to specify the connection used to communicate with the VM, which needs to remain unchanged
#	LO_IGNORE is an optional argument used to indicate that the loopback interface lo is not to be used during the test (it is usually detected as a legacy interface)
#	GATEWAY is the IP Address of the default gateway
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
declare -a MACS=()

if [ "${MAC:-UNDEFINED}" = "UNDEFINED" ]; then
	msg="The test parameter MAC is not defined in constants file"
	LogMsg "$msg"
	UpdateSummary "$msg"
	SetTestStateAborted
	exit 30
else

	# Split (if necessary) MAC Adddresses based on , (comma)
	IFS=',' read -a MACS <<< "$MAC"

	declare -i __iterator
	# Validate that $MAC is the correct format
	for __iterator in ${!MACS[@]}; do

		CheckMAC "${MACS[$__iterator]}"

		if [ 0 -ne $? ]; then
			msg="Variable MAC: ${MACS[$__iterator]} does not contain a valid MAC address "
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateAborted
			exit 30
		fi
		
	done
	
	unset __iterator
	
fi

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

if [ "${REMOTE_SERVER:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter REMOTE_SERVER is not defined in constants file. No network connectivity test will be performed."
    LogMsg "$msg"
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
		__lo_ignore=''
	else
		__lo_ignore=lo
	fi
	
fi

# Retrieve synthetic network interfaces
GetSynthNetInterfaces

if [ 0 -ne $? ]; then
    msg="No synthetic network interfaces found"
    LogMsg "$msg"
else
	# Remove interface if present
	SYNTH_NET_INTERFACES=(${SYNTH_NET_INTERFACES[@]/$__iface_ignore/})

	if [ ${#SYNTH_NET_INTERFACES[@]} -eq 0 ]; then
		msg="The only synthetic interface is the one which LIS uses to send files/commands to the VM."
		LogMsg "$msg"
	fi

	LogMsg "Found ${#SYNTH_NET_INTERFACES[@]} synthetic interface(s): ${SYNTH_NET_INTERFACES[*]} in VM"
fi

# Get the legacy netadapter interface
GetLegacyNetInterfaces

if [ 0 -ne $? ]; then
	msg="No legacy network interfaces found"
	LogMsg "$msg"
else
	# Remove loopback interface if LO_IGNORE is set
	LEGACY_NET_INTERFACES=(${LEGACY_NET_INTERFACES[@]/$__lo_ignore/})

	if [ ${#LEGACY_NET_INTERFACES[@]} -eq 0 ]; then
		msg="The only legacy interface is the loopback interface lo, which was set to be ignored."
		LogMsg "$msg"
	else
		# Remove interface_ignore if present
		LEGACY_NET_INTERFACES=(${LEGACY_NET_INTERFACES[@]/$__iface_ignore/})

		if [ ${#LEGACY_NET_INTERFACES[@]} -eq 0 ]; then
			msg="The only legacy interface is the one which LIS uses to send files/commands to the VM."
			LogMsg "$msg"
		fi
	fi
	
	LogMsg "Found ${#LEGACY_NET_INTERFACES[@]} legacy interface(s): ${LEGACY_NET_INTERFACES[*]} in VM"
fi

# Check if enough interfaces were found
declare -i __total_interfaces=0

__total_interfaces=$((${#LEGACY_NET_INTERFACES[@]}+${#SYNTH_NET_INTERFACES[@]}))

if [ ${#MACS[@]} -gt "$__total_interfaces" ]; then
	msg="Received ${#MACS[@]}, but found only $__total_interfaces interfaces present (Possibly removed the loopback and another interface if configured)."
	LogMsg "$msg"
	UpdateSummary "$msg"
	SetTestStateFailed
	exit 10
fi


declare -a __MAC_NET_INTERFACES=()
declare -i __iterator
declare __sys_interface
declare __ip_interface

# find interfaces which have the given MAC address(es) in /sys
# and compare them with the output of ip link

for __iterator in ${!MACS[@]}; do

	# get path of given address
	__sys_interface=$(grep -il "${MACS[$__iterator]}" /sys/class/net/*/address)
	if [ 0 -ne $? ]; then
		msg="MAC Address ${MACS[$__iterator]} does not belong to any interface."
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi
	
	# get just the interface name from the path
	__sys_interface=$(basename "$(dirname "$__sys_interface")")

	# verify that ip link give us the same information
	
	__ip_interface=$(ip -o link | grep -i "${MACS[$__iterator]}" | awk -F': ' '{ NF == 2; print $2 }')
	
	if [ x"$__sys_interface" != x"$__ip_interface" ]; then
		msg="Interface $__sys_interface found from /sys is different than $__ip_interface found from ip link command."
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi
	
	# add interface to list of interfaces used to ping remote-vm
	__MAC_NET_INTERFACES=("${__MAC_NET_INTERFACES[@]}" "$__sys_interface")
	
done

unset __sys_interface
unset __ip_interface
unset __iterator

# this should always be false
if [ ${#__MAC_NET_INTERFACES[@]} -ne ${#MACS[@]} ]; then
	msg="Number of found interfaces - ${#__MAC_NET_INTERFACES[@]} differs from number of given MAC Addresses - ${#MACS[@]}"
	LogMsg "$msg"
	UpdateSummary "$msg"
	SetTestStateFailed
	exit 10
fi

declare -i __iterator=0

# set static ips
for __iterator in ${!STATIC_IPS[@]} ; do
	
	# if number of static ips is greater than number of interfaces, just break.
	if [ "$__iterator" -ge "${#__MAC_NET_INTERFACES[@]}" ]; then
		LogMsg "Number of static IP addresses in constants.sh is greater than number of concerned interfaces. All extra IP addresses are ignored."
		break
	fi
	
	SetIPstatic "${STATIC_IPS[$__iterator]}" "${__MAC_NET_INTERFACES[$__iterator]}" "$NETMASK"
	# if failed to assigned address
	if [ 0 -ne $? ]; then
		msg="Failed to assign static ip ${STATIC_IPS[$__iterator]} netmask $NETMASK on interface ${__MAC_NET_INTERFACES[$__iterator]}"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 20
	fi	
	LogMsg "$(ip -o addr show ${__MAC_NET_INTERFACES[$__iterator]} | grep -vi inet6)"
	UpdateSummary "Successfully assigned ${STATIC_IPS[$__iterator]} ($NETMASK) to synthetic interface ${__MAC_NET_INTERFACES[$__iterator]}"
done

# set the iterator to point to the next element in the MAC_NET_INTERFACES array
__iterator=${#STATIC_IPS[@]}

# set dhcp ips for remaining interfaces
while [ $__iterator -lt ${#__MAC_NET_INTERFACES[@]} ]; do

	LogMsg "Trying to get an IP Address via DHCP on interface ${__MAC_NET_INTERFACES[$__iterator]}"
	SetIPfromDHCP "${__MAC_NET_INTERFACES[$__iterator]}"
	
	if [ 0 -ne $? ]; then
		msg="Unable to get address for ${__MAC_NET_INTERFACES[$__iterator]} through DHCP"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi
	
	UpdateSummary "Successfully set ip from dhcp on interface ${__MAC_NET_INTERFACES[$__iterator]}"
	
	: $((__iterator++))
	
done



declare -i __iterator
# ping REMOTE_SERVER if set
if [ "${REMOTE_SERVER:-UNDEFINED}" != "UNDEFINED" ]; then
	for __iterator in ${!__MAC_NET_INTERFACES[@]}; do
	
		# set default gateway if specified
		if [ -n "$GATEWAY" ]; then
			LogMsg "Setting $GATEWAY as default gateway on dev ${SYNTH_NET_INTERFACES[$__iterator]}"
			CreateDefaultGateway "$GATEWAY" "${SYNTH_NET_INTERFACES[$__iterator]}"
			if [ 0 -ne $? ]; then
				LogMsg "Warning! Failed to set default gateway!"
			fi
		fi
		
		LogMsg "Trying to ping $REMOTE_SERVER"
		UpdateSummary "Trying to ping $REMOTE_SERVER"
		# ping the remote host using an easily distinguishable pattern 0xcafed00d`null`static`null`mac`null`
		ping -I ${__MAC_NET_INTERFACES[$__iterator]} -c 10 -p "cafed00d00737461746963006d616300" "$REMOTE_SERVER"
		if [ 0 -ne $? ]; then
			msg="Unable to ping $REMOTE_SERVER through interface ${__MAC_NET_INTERFACES[$__iterator]}"
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			exit 10
		fi
		UpdateSummary "Successfully pinged $REMOTE_SERVER through interface ${__MAC_NET_INTERFACES[$__iterator]}"
	done
fi

# everything ok
UpdateSummary "Test successful"
LogMsg "Updating test case state to completed"
SetTestStateCompleted
exit 0