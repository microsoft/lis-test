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
#	This script verifies that the network doesn't 
#	loose connection by copying a large file(~10GB)file 
#	between two VM's with IC installed. 
#
#	Steps:
#	1. Verify configuration file constants.sh
#	2. Verify ssh private key file for remote VM was given
#	3. Ping the remote server through the Synthetic Adapter card
#	4. Verify there is enough local disk space for 10GB file
#	5. Verify there is enough remote disk space for 10GB file
#	6. Create 10GB file from /dev/urandom. Save md5sum of it and copy it from local VM to remote VM using scp
#	7. Erase local file after copy finished
#	8. Copy data back from repository server to the local VM using scp
#	9. Erase remote file after copy finished
#	9. Make new md5sum of received file and compare to the one calculated earlier
#
#	Parameters required:
#		REMOTE_VM
#		SSH_PRIVATE_KEY
#
#	Optional parameters:
#		TC_COVERED
#		NO_DELETE
#		REMOTE_USER
#		ZERO_FILE
#		FILE_SIZE_GB
#		STATIC_IP
#		NETMASK
#		GATEWAY
#
#	Parameter explanation:
#	REMOTE_VM is the address of the second vm.
#	The script assumes that the SSH_PRIVATE_KEY is located in $HOME/.ssh/$SSH_PRIVATE_KEY
#	TC_COVERED is the test id from LIS testing
#	NO_DELETE stops the script from deleting the 10GB files locally and remotely
#	REMOTE_USER is the user used to ssh into the remote VM. Default is root
#	ZERO_FILE creates a file filled with 0. Is created much faster than the one from /dev/urandom
#	FILE_SIZE_GB override the 10GB size. File size specified in GB
#	STATIC_IP is the address that will be assigned to the VM's synthetic network adapter
#	NETMASK of this VM's subnet. Defaults to /24 if not set.
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
		#do nothing
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

# Parameters to check in constants file

if [ "${REMOTE_VM:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter REMOTE_VM is not defined in ${LIS_CONSTANTS_FILE}"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
    exit 30
fi

if [ "${SSH_PRIVATE_KEY:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter SSH_PRIVATE_KEY is not defined in ${LIS_CONSTANTS_FILE}"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
    exit 30
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

# Set clean-up policy
if [ "${NO_DELETE:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter NO_DELETE is not defined in ${__LIS_CONSTANTS_FILE} . Generated file will be deleted"
    LogMsg "$msg"
	NO_DELETE=0
else
	msg="NO_DELETE is set. Generated file will not be deleted"
	NO_DELETE=1
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
	msg="This should not have happened. Probable internal error"
	LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 100
fi

declare -ai __invalid_positions
__iterator=0
# Try to get DHCP address for synthetic adaptor and ping if configured
while [ $__iterator -lt ${#SYNTH_NET_INTERFACES[@]} ]; do
	SetIPfromDHCP "${SYNTH_NET_INTERFACES[$__iterator]}"
	if [ 0 -eq $? ]; then		
		# add some interface output
		UpdateSummary "Successfully set ip from dhcp on interface ${SYNTH_NET_INTERFACES[$__iterator]}"
		LogMsg "$(ip -o addr show ${SYNTH_NET_INTERFACES[$__iterator]} | grep -vi inet6)"
		
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
		# ping the remote host using an easily distinguishable pattern 0xcafed00d`null`copy`null`dhcp`null`
		ping -I "${SYNTH_NET_INTERFACES[$__iterator]}" -c 10 -p "cafed00d00636f7079006468637000" "$REMOTE_VM" >/dev/null 2>&1
		if [ 0 -eq $? ]; then
			# ping worked!
			LogMsg "Successfully pinged $REMOTE_VM through synthetic ${SYNTH_NET_INTERFACES[$__iterator]} (dhcp)."
			UpdateSummary "Successfully pinged $REMOTE_VM through synthetic ${SYNTH_NET_INTERFACES[$__iterator]} (dhcp)."
			break
		else
			LogMsg "Unable to ping $REMOTE_VM through synthetic ${SYNTH_NET_INTERFACES[$__iterator]}"
		fi
	fi
	__invalid_positions=("${__invalid_positions[@]}" "$__iterator")
	LogMsg "Unable to get address from dhcp server on synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
	UpdateSummary "Unable to get address from dhcp server on synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
	: $((__iterator++))
done

# check if there is any interface capable of pinging remote_vm
if [ ${#SYNTH_NET_INTERFACES[@]} -eq  ${#__invalid_positions[@]} ]; then
	# delete array
	unset __invalid_positions
	# try using static IPs
	declare -ai __invalid_positions
	__iterator=0
	# set synthetic interface address to $STATIC_IP
	while [ $__iterator -lt ${#SYNTH_NET_INTERFACES[@]} ]; do
		SetIPstatic "$STATIC_IP" "${SYNTH_NET_INTERFACES[$__iterator]}" "$NETMASK"
		# if successfully assigned address
		if [ 0 -eq $? ]; then
			LogMsg "Successfully assigned $STATIC_IP ($NETMASK) to synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
			UpdateSummary "Successfully assigned $STATIC_IP ($NETMASK) to synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
			
			# set default gateway if specified
			if [ -n "$GATEWAY" ]; then
				LogMsg "Setting $GATEWAY as default gateway on dev ${SYNTH_NET_INTERFACES[$__iterator]}"
				CreateDefaultGateway "$GATEWAY" "${SYNTH_NET_INTERFACES[$__iterator]}"
				if [ 0 -ne $? ]; then
					LogMsg "Warning! Failed to set default gateway!"
				fi
			fi
			# ping the remote vm using an easily distinguishable pattern 0xcafed00d`null`cop`null`static`null`
			ping -I "${SYNTH_NET_INTERFACES[$__iterator]}" -c 10 -p "cafed00d00636f700073746174696300" "$REMOTE_VM" >/dev/null 2>&1
			
			if [ 0 -eq $? ]; then
				# ping worked!
				UpdateSummary "Successfully pinged $REMOTE_VM on synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
				break
			else
				LogMsg "Unable to ping $REMOTE_VM through ${SYNTH_NET_INTERFACES[$__iterator]}"
			fi
		else
			LogMsg "Unable to set static IP to interface ${SYNTH_NET_INTERFACES[$__iterator]}"
		fi
		# shut interface down
		ip link set ${SYNTH_NET_INTERFACES[$__iterator]} down
		__invalid_positions=("${__invalid_positions[@]}" "$__iterator")
		: $((__iterator++))
	done
	
	# if no interface was capable of pinging the REMOTE_VM by having its IP address statically assigned, give up
	if [ $__iterator -eq ${#SYNTH_NET_INTERFACES[@]} ]; then
		msg="Not even with static IPs was any interface capable of pinging $REMOTE_VM . Failed..."
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateFailed
		exit 40
	fi
else
	# reset iterator and remove invalid positions from array
	__iterator=0
	while [ $__iterator -lt ${#__invalid_positions[@]} ]; do
		# eliminate from SYNTH_NET_INTERFACES array the interface located on position ${__invalid_positions[$__iterator]}
		SYNTH_NET_INTERFACES=("${SYNTH_NET_INTERFACES[@]:0:${__invalid_positions[$__iterator]}}" "${SYNTH_NET_INTERFACES[@]:$((${__invalid_positions[$__iterator]}+1))}")
		: $((__iterator++))
	done
fi

# delete array
unset __invalid_positions

if [ 0 -eq ${#SYNTH_NET_INTERFACES[@]} ]; then
	msg="This should not have happened. Probable internal error above line $LINENO"
	LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 100
fi

LogMsg "Successfully pinged $REMOTE_VM on synthetic interface(s) ${SYNTH_NET_INTERFACES[@]}"

# get file size in bytes
declare -i __file_size

if [ "${FILE_SIZE_GB:-UNDEFINED}" = "UNDEFINED" ]; then
	__file_size=$((10*1024*1024*1024))						# 10 GB
else
	__file_size=$((FILE_SIZE_GB*1024*1024*1024))
fi

LogMsg "Checking for local disk space"

# Check disk size on local vm
IsFreeSpace "$HOME" "$__file_size"

if [ 0 -ne $? ]; then
	msg="Not enough free space on current partition to create the test file"
	LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

LogMsg "Enough free space locally to create the file"
UpdateSummary "Enough free space locally to create the file"

LogMsg "Checking for disk space on $REMOTE_VM"
# Check disk size on remote vm. Cannot use IsFreeSpace function directly. Need to export Utils.sh to the remote_vm, source it and then access the functions therein
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no Utils.sh "$REMOTE_USER"@"$REMOTE_VM":/tmp
if [ 0 -ne $? ]; then
	msg="Cannot copy Utils.sh to $REMOTE_VM:/tmp"
	LogMsg "$msg"
    UpdateSummary "$msg"
	SetTestStateFailed
    exit 10
fi

remote_home=$(ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$REMOTE_USER"@"$REMOTE_VM" "
	. /tmp/Utils.sh
	IsFreeSpace \"\$HOME\" $__file_size
	if [ 0 -ne \$? ]; then
		exit 1
	fi
	echo \"\$HOME\"
	exit 0
	")

# get ssh status
sts=$?

if [ 1 -eq $sts ]; then
	msg="Not enough free space on $REMOTE_VM to create the test file"
	LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

# if status is neither 1, nor 0 then ssh encountered an error
if [ 0 -ne $sts ]; then
	msg="Unable to connect through ssh to $REMOTE_VM"
	LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

LogMsg "Enough free space remotely to create the file"
UpdateSummary "Enough free space (both locally and remote) to create the file"

# get source to create the file

if [ "${ZERO_FILE:-UNDEFINED}" = "UNDEFINED" ]; then
	file_source=/dev/urandom
else
	file_source=/dev/zero
fi

# create file locally with PID appended
output_file=large_file_$$
if [ -d "$HOME"/"$output_file" ]; then
	rm -rf "$HOME"/"$output_file"
fi

if [ -e "$HOME"/"$output_file" ]; then
	rm -f "$HOME"/"$output_file"
fi

dd if=$file_source of="$HOME"/"$output_file" bs=1M count=$((__file_size/1024/1024))

if [ 0 -ne $? ]; then
	msg="Unable to create file $output_file in $HOME"
	LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

LogMsg "Successfully created $output_file"

#compute md5sum
local_md5sum=$(md5sum $output_file | cut -f 1 -d ' ')

#send file to remote_vm
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$output_file" "$REMOTE_USER"@"$REMOTE_VM":"$remote_home"/"$output_file"

if [ 0 -ne $? ]; then
	[ $NO_DELETE -eq 0 ] && rm -f "$HOME"/$output_file
	msg="Unable to copy file $output_file to $REMOTE_VM:$remote_home/$output_file"
	LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

LogMsg "Successfully sent $output_file to $REMOTE_VM:$remote_home/$output_file"
UpdateSummary "Successfully sent $output_file to $REMOTE_VM:$remote_home/$output_file"

# erase file locally, if set
[ $NO_DELETE -eq 0 ] && rm -f $output_file

# copy file back from remote vm
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$REMOTE_USER"@"$REMOTE_VM":"$remote_home"/"$output_file" "$HOME"/"$output_file"

if [ 0 -ne $? ]; then
	#try to erase file from remote vm
	[ $NO_DELETE -eq 0 ] && ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$REMOTE_USER"@"$REMOTE_VM" "rm -f \$HOME/$output_file"
	msg="Unable to copy from $REMOTE_VM:$remote_home/$output_file"
	LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

LogMsg "Received $outputfile from $REMOTE_VM"
UpdateSummary "Received $outputfile from $REMOTE_VM"

# delete remote file
[ $NO_DELETE -eq 0 ] && ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$REMOTE_USER"@"$REMOTE_VM" "rm -f $remote_home/$output_file"

# check md5sums
remote_md5sum=$(md5sum $output_file | cut -f 1 -d ' ')

if [ "$local_md5sum" != "$remote_md5sum" ]; then
	[ $NO_DELETE -eq 0 ] && rm -f "$HOME"/$output_file
	msg="md5sums differ. Files do not match"
	LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

# delete local file again
[ $NO_DELETE -eq 0 ] && rm -f "$HOME"/$output_file

UpdateSummary "Checksums of file match. Test successful"
LogMsg "Updating test case state to completed"
SetTestStateCompleted
exit 0