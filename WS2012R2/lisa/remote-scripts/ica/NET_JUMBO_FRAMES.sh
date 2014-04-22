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
#	This script tries to set the mtu of each synthetic network adapter to 65536 or whatever the maximum it accepts
#	and ping a second VM with large packet sizes. All synthetic interfaces need to have the same max MTU.
#	The REMOTE_VM also needs to have its interface set to the high MTU.
#
#	Steps:
#	1. Verify configuration file constants.sh
#	2. Determine synthetic interface(s)
#	3. Set static IPs on these interfaces
#		3a. If static IP is not configured, get address(es) via dhcp
#	4. Set MTU to 65536 or the maximum that the interface accepts
#	5. If SSH_PRIVATE_KEY was passed, ssh into the REMOTE_VM and set the MTU to the same value as above, on the interface
#		owning that IP Address
#	5. Ping REMOTE_VM
#
#	The test is successful if all synthetic interfaces were able to set the same maximum MTU and then
#	were able to ping the REMOTE_VM with all various packet-sizes.
#
#	Parameters required:
#		REMOTE_VM
#		
#	Optional parameters:
#		STATIC_IP
#		TC_COVERED
#		NETMASK
#		SSH_PRIVATE_KEY
#		REMOTE_USER
#
#	Parameter explanation:
#	REMOTE_VM is an IP address of a ping-able machine. All interfaces found will have to be able to ping this REMOTE_VM
#	The script assumes that the SSH_PRIVATE_KEY is located in $HOME/.ssh/$SSH_PRIVATE_KEY
#	REMOTE_USER is the user used to ssh into the remote VM. Default is root
#	STATIC_IP is the address that will be assigned to the interface(s) corresponding to the given MAC. Multiple Addresses can be specified
#	separated by , (comma) and they will be assigned in order to each interface found.
#	NETMASK of this VM's subnet. Defaults to /24 if not set.
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

if [ "${REMOTE_VM:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter REMOTE_VM is not defined in constants file. No network connectivity test will be performed."
    LogMsg "$msg"
	SetTestStateAborted
	exit 30
fi


if [ "${SSH_PRIVATE_KEY:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter SSH_PRIVATE_KEY is not defined in ${LIS_CONSTANTS_FILE}"
    LogMsg "$msg"
fi
# Set remote user
if [ "${REMOTE_USER:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter REMOTE_USER is not defined in ${LIS_CONSTANTS_FILE} . Using root instead"
    LogMsg "$msg"
	REMOTE_USER=root
else
	msg="REMOTE_USER set to $REMOTE_USER"
    LogMsg "$msg"
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
	__iface_ignore=$(ifconfig | grep -B1 "$ipv4" | head -n 1 | cut -d ' ' -f1)
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

# try to set mtu to 65536
# all synthetic interfaces need to have the same maximum mtu
# save the maximum capable mtu

declare -i __max_mtu=0
declare -i __current_mtu=0
declare -i __const_max_mtu=65536
declare -i __const_increment_size=4096
declare -i __max_set=0

for __iterator in ${!SYNTH_NET_INTERFACES[@]}; do

	while [ "$__current_mtu" -lt "$__const_max_mtu" ]; do
	
		__current_mtu=$((__current_mtu+__const_increment_size))
		
		ifconfig "${SYNTH_NET_INTERFACES[$__iterator]}" mtu "$__current_mtu"
		
		if [ 0 -ne $? ]; then
			# we reached the maximum mtu for this interface. break loop
			__current_mtu=$((__current_mtu-__const_increment_size))
			break
		fi
		
		# make sure mtu was set. otherwise, set test to failed
		__actual_mtu=$(ifconfig "${SYNTH_NET_INTERFACES[$__iterator]}" | grep -i mtu | cut -d ':' -f2 | cut -d ' ' -f1)
		
		if [ x"$__actual_mtu" != x"$__current_mtu" ]; then
			msg="Set mtu on interface ${SYNTH_NET_INTERFACES[$__iterator]} to $__current_mtu but ifconfig reports mtu to be $__actual_mtu"
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			exit 10
		fi

	done
	
	LogMsg "Successfully set mtu to $__current_mtu on interface ${SYNTH_NET_INTERFACES[$__iterator]}"
	
	# update max mtu to the maximum of the first interface
	if [ "$__max_set" -eq 0 ]; then
		__max_mtu="$__current_mtu"
		# all subsequent __current_mtu must be equal to the max of the first one
		__max_set=1
	fi
	
	if [ "$__max_mtu" -ne "$__current_mtu" ]; then
		msg="Maximum mtu for interface ${SYNTH_NET_INTERFACES[$__iterator]} is $__current_mtu but maximum mtu for previous interfaces is $__max_mtu"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi
	
	# reset __current_mtu for next interface
	__current_mtu=0

done

# reset iterator
__iterator=0

# if SSH_PRIVATE_KEY was specified, ssh into the REMOTE_VM and set the MTU of that interface to __max_mtu
# if not, assume that it was already set.

if [ "${SSH_PRIVATE_KEY:-UNDEFINED}" != "UNDEFINED" ]; then
	ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$REMOTE_USER"@"$REMOTE_VM" "
		__remote_interface=\$(ifconfig | grep -B1 \"$REMOTE_VM\" | head -n 1 | cut -d ' ' -f1)
		if [ x\"\$__remote_interface\" = x ]; then
			exit 1
		fi
		
		ifconfig \"\$__remote_interface\" mtu \"$__max_mtu\"
		
		if [ 0 -ne \$? ]; then
			exit 2
		fi
		
		__remote_actual_mtu=\$(ifconfig \"\$__remote_interface\" | grep -i mtu | cut -d ':' -f2 | cut -d ' ' -f1)
		
		if [ x\"\$__remote_actual_mtu\" !=  x\"$__max_mtu\" ]; then
			exit 3
		fi
		
		exit 0
		"
		
	if [ 0 -ne $? ]; then
		msg="Unable to set $REMOTE_VM mtu to $__max_mtu"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 10
	fi
fi

declare -ai __packet_size=(0 1 2 48 64 512 1440 1500 1505 4096 4192 25152 65500)
declare -i __packet_iterator
# 20 bytes IP header + 8 bytes ICMP header 
declare -i __const_ping_header=28

# for each interface, ping the REMOTE_VM with different-sized packets
for __iterator in ${!SYNTH_NET_INTERFACES[@]}; do

	for __packet_iterator in ${!__packet_size[@]}; do
		if [ ${__packet_size[$__packet_iterator]} -gt $((__max_mtu-__const_ping_header)) ]; then
			# reached the max packet size for our max mtu
			break
		fi
		
		ping -I "${SYNTH_NET_INTERFACES[$__iterator]}" "$REMOTE_VM" -c 10 -s "${__packet_size[$__packet_iterator]}"
		
		if [ 0 -ne $? ]; then
			msg="Failed to ping $REMOTE_VM through interface ${SYNTH_NET_INTERFACES[$__iterator]} with packet-size ${__packet_size[$__packet_iterator]}"
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			exit 10
		fi
	done

done

# everything ok
UpdateSummary "Test successful"
LogMsg "Updating test case state to completed"
SetTestStateCompleted
exit 0