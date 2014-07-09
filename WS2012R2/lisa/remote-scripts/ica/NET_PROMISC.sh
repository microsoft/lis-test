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
#	This script tries to set each synthetic network interface to promiscuous and then ping the REMOTE_SERVER. Afterwards, it disables 
#	the promiscuous mode again.
#
#	Steps:
#	1. Verify configuration file constants.sh
#	2. Determine synthetic interface(s)
#	3. Set static IPs on these interfaces
#		3a. If static IP is not configured, get address(es) via dhcp
#	4. Make sure synthetic interfaces are not in promiscuous mode and then set them to it
#	5. Ping REMOTE_SERVER
#	6. Disable promiscuous mode again
#
#	The test is successful if all synthetic interfaces were in normal mode at the beggining of the test and were able to be set in promisc mode afterwards.
#	Each interface must have an IP Address (static or via dhcp)
#
#	Parameters required:
#		REMOTE_SERVER
#		
#	Optional parameters:
#		STATIC_IP
#		TC_COVERED
#		NETMASK
#		GATEWAY
#
#	Parameter explanation:
#	REMOTE_SERVER is an IP address of a ping-able machine. All interfaces found will have to be able to ping this REMOTE_SERVER
#	STATIC_IP is the address that will be assigned to the interface(s) corresponding to the given MAC. Multiple Addresses can be specified
#	separated by , (comma) and they will be assigned in order to each interface found.
#	NETMASK of this VM's subnet. Defaults to /24 if not set.
#	TC_COVERED is the LIS testcase number
#	GATEWAY is the IP Address of the default gateway
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
	ip link show "${SYNTH_NET_INTERFACES[$__iterator]}" >/dev/null 2>&1
	if [ 0 -ne $? ]; then
		msg="Invalid synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 20
	fi
	
	# make sure interface is not in promiscuous mode already
	ip link show "${SYNTH_NET_INTERFACES[$__iterator]}" | grep -i promisc
	if [ 0 -eq $? ]; then
		msg="Synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]} is already in promiscuous mode"
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
	LogMsg "$(ip -o addr show ${SYNTH_NET_INTERFACES[$__iterator]} | grep -vi inet6)"
	
	UpdateSummary "Successfully assigned ${STATIC_IPS[$__iterator]} ($NETMASK) to synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
done

# set the iterator to point to the next element in the SYNTH_NET_INTERFACES array
__iterator=${#STATIC_IPS[@]}

# set dhcp ips for remaining interfaces
while [ $__iterator -lt ${#SYNTH_NET_INTERFACES[@]} ]; do

	LogMsg "Trying to get an IP Address via DHCP on interface ${SYNTH_NET_INTERFACES[$__iterator]}"
	SetIPfromDHCP "${SYNTH_NET_INTERFACES[$__iterator]}"
	
	if [ 0 -ne $? ]; then
		msg="Unable to get address for ${SYNTH_NET_INTERFACES[$__iterator]} through DHCP"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi
	LogMsg "$(ip -o addr show ${SYNTH_NET_INTERFACES[$__iterator]} | grep -vi inet6)"
	: $((__iterator++))
	
done

# reset iterator
__iterator=0

declare -i __message_count=0

for __iterator in ${!SYNTH_NET_INTERFACES[@]}; do

	LogMsg "Setting ${SYNTH_NET_INTERFACES[$__iterator]} to promisc mode"
	# set interfaces to promiscuous mode
	ip link set dev ${SYNTH_NET_INTERFACES[$__iterator]} promisc on
	
	# make sure it was set
	__message_count=$(dmesg | grep -i "device ${SYNTH_NET_INTERFACES[$__iterator]} entered promiscuous mode" | wc -l)
	if [ "$__message_count" -ne 1 ]; then
		msg="$__message_count messages were found in dmesg log concerning synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]} entering promiscuous mode"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi
	
	# now check ip for promisc
	ip link show ${SYNTH_NET_INTERFACES[$__iterator]} | grep -i promisc
	if [ 0 -ne $? ]; then
		msg="Interface ${SYNTH_NET_INTERFACES[$__iterator]} is not set to promiscuous mode according to ip. Dmesg however contained an entry stating that it did."
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi
	
	UpdateSummary "Successfully set ${SYNTH_NET_INTERFACES[$__iterator]} to promiscuous mode"
	
	if [ -n "$GATEWAY" ]; then
		LogMsg "Setting $GATEWAY as default gateway on dev ${SYNTH_NET_INTERFACES[$__iterator]}"
		CreateDefaultGateway "$GATEWAY" "${SYNTH_NET_INTERFACES[$__iterator]}"
		if [ 0 -ne $? ]; then
			LogMsg "Warning! Failed to set default gateway!"
		fi
	fi
	
	LogMsg "Trying to ping $REMOTE_SERVER"
	UpdateSummary "Trying to ping $REMOTE_SERVER"
	
	# ping the remote server
	ping -I ${SYNTH_NET_INTERFACES[$__iterator]} -c 10 "$REMOTE_SERVER"

	if [ 0 -ne $? ]; then
		msg="Failed to ping $REMOTE_SERVER on synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi
	
	UpdateSummary "Successfully pinged $REMOTE_SERVER on synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
	
	# disable promiscuous mode
	LogMsg "Disabling promisc mode on ${SYNTH_NET_INTERFACES[$__iterator]}"
	
	ip link set dev ${SYNTH_NET_INTERFACES[$__iterator]} promisc off
	
	# make sure it was disabled
	__message_count=$(dmesg | grep -i "device ${SYNTH_NET_INTERFACES[$__iterator]} left promiscuous mode" | wc -l)
	if [ "$__message_count" -ne 1 ]; then
		msg="$__message_count messages were found in dmesg log concerning synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]} leaving promiscuous mode"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi
	
	# now check ip for promisc
	ip link show ${SYNTH_NET_INTERFACES[$__iterator]} | grep -i promisc
	if [ 0 -eq $? ]; then
		msg="Interface ${SYNTH_NET_INTERFACES[$__iterator]} is set to promiscuous mode according to ip. Dmesg however contained an entry stating that it left that mode."
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi
	
	UpdateSummary "Successfully disabled promiscuous mode on ${SYNTH_NET_INTERFACES[$__iterator]}"
done


# everything ok
UpdateSummary "Test successful"
LogMsg "Updating test case state to completed"
SetTestStateCompleted
exit 0
