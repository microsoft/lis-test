#!/bin/bash -

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
#
# This script contains all distro-specific functions, as well as other common functions
# used in the LIS test scripts.
# Private variables used in scripts should use the __VAR_NAME notation. Using the bash built-in 
# `declare' statement also restricts the variable's scope. Same for "private" functions.
# 
###########################################################################################

# Set IFS to space\t\n
IFS=$' \t\n'

# Include guard
[ -n "$__LIS_UTILS_SH_INCLUDE_GUARD" ] && exit 200 || readonly __LIS_UTILS_SH_INCLUDE_GUARD=1

##################################### Global variables #####################################

# Because functions can only return a status code, global vars will be used for communicating with the caller
# All vars are first defined here

# Directory containing all files pushed by LIS framework
declare LIS_HOME="$HOME"

# LIS state file used by powershell to get the test's state 
declare __LIS_STATE_FILE="$LIS_HOME/state.txt"

# LIS possible states recorded in state file
declare __LIS_TESTRUNNING="TestRunning"      # The test is running
declare __LIS_TESTCOMPLETED="TestCompleted"  # The test completed successfully
declare __LIS_TESTABORTED="TestAborted"      # Error during setup of test
declare __LIS_TESTFAILED="TestFailed"        # Error during execution of test

# LIS constants file which contains the paramaters passed to the test
declare __LIS_CONSTANTS_FILE="$LIS_HOME/constants.sh"

# LIS summary file. Should be less verbose than the separate log file
declare __LIS_SUMMARY_FILE="$LIS_HOME/summary.log"

# DISTRO used for setting the distro used to run the script
declare DISTRO=''

# SYNTH_NET_INTERFACES is an array containing all synthetic network interfaces found
declare -a SYNTH_NET_INTERFACES

# LEGACY_NET_INTERFACES is an array containing all legacy network interfaces found
declare -a LEGACY_NET_INTERFACES





######################################## Functions ########################################

# Convenience function used to set-up most common variables
UtilsInit()
{
	if [ -d "$LIS_HOME" ]; then
		cd "$LIS_HOME" 
	else
		LogMsg "Warning: LIS_HOME $LIS_HOME directory missing. Unable to initialize testscript"
		return 1
	fi
	
	# clean-up any remaining files
	if [ -e "$__LIS_STATE_FILE" ]; then
		if [ -d "$__LIS_STATE_FILE" ]; then
			rm -rf "$__LIS_STATE_FILE"
			LogMsg "Warning: Found $__LIS_STATE_FILE directory"
		else
			rm -f "$__LIS_STATE_FILE"
		fi
	fi
	
	if [ -e "$__LIS_SUMMARY_FILE" ]; then
		if [ -d "$__LIS_SUMMARY_FILE" ]; then
			rm -rf "$__LIS_SUMMARY_FILE"
			LogMsg "Warning: Found $__LIS_SUMMARY_FILE directory"
		else
			rm -f "$__LIS_SUMMARY_FILE"
		fi
	fi
	
	# Set standard umask for root
	umask 022
	# Create state file and update test state
	touch "$__LIS_STATE_FILE"
	SetTestStateRunning || {
		LogMsg "Warning: unable to update test state-file. Cannot continue initializing testscript"
		return 2
	}
	
	touch "$__LIS_SUMMARY_FILE"
	
	if [ -f "$__LIS_CONSTANTS_FILE" ]; then
		. "$__LIS_CONSTANTS_FILE"
	else
		LogMsg "Error: constants file $__LIS_CONSTANTS_FILE missing or not a regular file. Cannot source it!"
		SetTestStateAborted
		UpdateSummary "Error: constants file $__LIS_CONSTANTS_FILE missing or not a regular file. Cannot source it!"
		return 3
	fi
	
	[ -n "$TC_COVERED" ] && UpdateSummary "Test covers $TC_COVERED" || UpdateSummary "Starting unknown test due to missing TC_COVERED variable"

	GetDistro && LogMsg "Testscript running on $DISTRO" || LogMsg "Warning: test running on unknown distro!"
	
	LogMsg "Successfully initialized testscript!"
	return 0
	
}

# Functions used to update the current test state

# Should not be used directly. $1 should be one of __LIS_TESTRUNNING __LIS_TESTCOMPLETE __LIS_TESTABORTED __LIS_TESTFAILED
__SetTestState()
{
	if [ -f "$__LIS_STATE_FILE" ]; then
		if [ -w "$__LIS_STATE_FILE" ]; then
			echo "$1" > "$__LIS_STATE_FILE"
		else
			LogMsg "Warning: state file $__LIS_STATE_FILE exists and is a normal file, but is not writable"
			chmod u+w "$__LIS_STATE_FILE" && { echo "$1" > "$__LIS_STATE_FILE" && return 0 ; } || LogMsg "Warning: unable to make $__LIS_STATE_FILE writeable"
			return 1
		fi
	else
		LogMsg "Warning: state file $__LIS_STATE_FILE either does not exist or is not a regular file. Trying to create it..."
		echo "$1" > "$__LIS_STATE_FILE" || return 2
	fi
	
	return 0
}

SetTestStateFailed()
{
	__SetTestState "$__LIS_TESTFAILED"
	return $?
}

SetTestStateAborted()
{
	__SetTestState "$__LIS_TESTABORTED"
	return $?
}

SetTestStateCompleted()
{
	__SetTestState "$__LIS_TESTCOMPLETED"
	return $?
}

SetTestStateRunning()
{
	__SetTestState "$__LIS_TESTRUNNING"
	return $?
}

# Logging function. The way LIS currently runs scripts and collects log files, just echo the message
# $1 == Message
LogMsg()
{
	echo $(date "+%a %b %d %T %Y") : "${1}"
}

# Update summary file with message $1
# Summary should contain only a few lines
UpdateSummary()
{
	if [ -f "$__LIS_SUMMARY_FILE" ]; then
		if [ -w "$__LIS_SUMMARY_FILE" ]; then
			echo "$1" >> "$__LIS_SUMMARY_FILE"
		else
			LogMsg "Warning: summary file $__LIS_SUMMARY_FILE exists and is a normal file, but is not writable"
			chmod u+w "$__LIS_SUMMARY_FILE" && echo "$1" >> "$__LIS_SUMMARY_FILE" || LogMsg "Warning: unable to make $__LIS_SUMMARY_FILE writeable"
			return 1
		fi
	else
		LogMsg "Warning: summary file $__LIS_SUMMARY_FILE either does not exist or is not a regular file. Trying to create it..."
		echo "$1" >> "$__LIS_SUMMARY_FILE" || return 2
	fi
	
	return 0
}


# Function to get current distro
# Sets the $DISTRO variable to one of the following: suse, centos_{5, 6, 7}, redhat_{5, 6, 7}, fedora, ubuntu
# The naming scheme will be distroname_version
# Takes no arguments

GetDistro()
{
	# Make sure we don't inherit anything
	declare __DISTRO
	#Get distro (snipper take from alsa-info.sh)
	__DISTRO=$(grep -ihs "Ubuntu\|SUSE\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux" /etc/{issue,*release,*version})
	case $__DISTRO in
		*Ubuntu*12*)
			DISTRO=ubuntu_12
			;;
		*Ubuntu*13*)
			DISTRO=ubuntu_13
			;;
		*Ubuntu*14*)
			DISTRO=ubuntu_14
			;;
		# ubuntu 14 in current beta state does not use the number 14 in its description
		*Ubuntu*Trusty*)
			DISTRO=ubuntu_14
			;;
		*Ubuntu*)
			DISTRO=ubuntu_x
			;;
		*Debian*7*)
			DISTRO=debian_7
			;;
		*Debian*)
			DISTRO=debian_x
			;;
		*SUSE*12*)
			DISTRO=suse_12
			;;
		*SUSE*11*)
			DISTRO=suse_11
			;;
		*SUSE*)
			DISTRO=suse_x
			;;
		*CentOS*5*)
			DISTRO=centos_5
			;; 
		*CentOS*6*)
			DISTRO=centos_6
			;;
		*CentOS*7*)
			DISTRO=centos_7
			;;
		*CentOS*)
			DISTRO=centos_x
			;;
		*Fedora*18*)
			DISTRO=fedora_18
			;;
		*Fedora*19*)
			DISTRO=fedora_19
			;;
		*Fedora*20*)
			DISTRO=fedora_20
			;;
		*Fedora*)
			DISTRO=fedora_x
			;;
		*Red*5*)
			DISTRO=redhat_5
			;;
		*Red*6*)
			DISTRO=redhat_6
			;;
		*Red*7*)
			DISTRO=redhat_7
			;;
		*Red*)
			DISTRO=redhat_x
			;;
		*)
			DISTRO=unknown
			return 1
			;;
	esac
	
	return 0
}

# Function to get all synthetic network interfaces
# Sets the $SYNTH_NET_INTERFACES array elements to an interface name suitable for ifconfig etc.
# Takes no arguments
GetSynthNetInterfaces()
{
	
	# declare array
	declare -a __SYNTH_NET_ADAPTERS_PATHS
	# Add synthetic netadapter paths into __SYNTH_NET_ADAPTERS_PATHS array
	if [ -d '/sys/devices' ]; then
		while IFS= read -d $'\0' -r path ; do
			__SYNTH_NET_ADAPTERS_PATHS=("${__SYNTH_NET_ADAPTERS_PATHS[@]}" "$path")
		done < <(find /sys/devices -name net -a -path '*vmbus*' -print0)
	else
		LogMsg "Cannot find Synthetic network interfaces. No /sys/devices directory."
		return 1
	fi
	
	# Check if we found anything
	if [ 0 -eq ${#__SYNTH_NET_ADAPTERS_PATHS[@]} ]; then
		LogMsg "No synthetic network adapters found."
		return 2
	fi
	
	# Loop __SYNTH_NET_ADAPTERS_PATHS and get interfaces
	declare -i __index
	for __index in "${!__SYNTH_NET_ADAPTERS_PATHS[@]}"; do
		if [ ! -d "${__SYNTH_NET_ADAPTERS_PATHS[$__index]}" ]; then
			LogMsg "Synthetic netadapter dir ${__SYNTH_NET_ADAPTERS_PATHS[$__index]} disappeared during processing!"
			return 3
		fi
		# ls should not yield more than one interface, but doesn't hurt to be sure
		SYNTH_NET_INTERFACES[$__index]=$(ls "${__SYNTH_NET_ADAPTERS_PATHS[$__index]}" | head -n 1)
		if [ -z "${SYNTH_NET_INTERFACES[$__index]}" ]; then
			LogMsg "No network interface found in ${__SYNTH_NET_ADAPTERS_PATHS[$__index]}"
			return 4
		fi
	done
	
	unset __SYNTH_NET_ADAPTERS_PATHS
	# Everything OK
	return 0
}



# Function to get all legacy network interfaces
# Sets the $LEGACY_NET_INTERFACES array elements to an interface name suitable for ifconfig/ip commands.
# Takes no arguments
GetLegacyNetInterfaces()
{
	
	# declare array
	declare -a __LEGACY_NET_ADAPTERS_PATHS
	# Add legacy netadapter paths into __LEGACY_NET_ADAPTERS_PATHS array
	if [ -d '/sys/devices' ]; then
		while IFS= read -d $'\0' -r path ; do
			__LEGACY_NET_ADAPTERS_PATHS=("${__LEGACY_NET_ADAPTERS_PATHS[@]}" "$path")
		done < <(find /sys/devices -name net -a ! -path '*vmbus*' -print0)
	else
		LogMsg "Cannot find Legacy network interfaces. No /sys/devices directory."
		return 1
	fi
	
	# Check if we found anything
	if [ 0 -eq ${#__LEGACY_NET_ADAPTERS_PATHS[@]} ]; then
		LogMsg "No synthetic network adapters found."
		return 2
	fi
	
	# Loop __LEGACY_NET_ADAPTERS_PATHS and get interfaces
	declare -i __index
	for __index in "${!__LEGACY_NET_ADAPTERS_PATHS[@]}"; do
		if [ ! -d "${__LEGACY_NET_ADAPTERS_PATHS[$__index]}" ]; then
			LogMsg "Legacy netadapter dir ${__LEGACY_NET_ADAPTERS_PATHS[$__index]} disappeared during processing!"
			return 3
		fi
		# ls should not yield more than one interface, but doesn't hurt to be sure
		LEGACY_NET_INTERFACES[$__index]=$(ls ${__LEGACY_NET_ADAPTERS_PATHS[$__index]} | head -n 1)
		if [ -z "${LEGACY_NET_INTERFACES[$__index]}" ]; then
			LogMsg "No network interface found in ${__LEGACY_NET_ADAPTERS_PATHS[$__index]}"
			return 4
		fi
	done
	
	# Everything OK
	return 0
}


# Validate that $1 is an IPv4 address

CheckIP()
{
	if [ 1 -ne $# ]; then
		LogMsg "CheckIP accepts 1 arguments: IP address"
		return 100
	fi
	
	declare ip
	declare stat
	ip=$1
	stat=1
	
	if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS="$IFS"
        IFS='.'
        ip=($ip)
        IFS="$OIFS"
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
	
	return $stat
	
}

# Check that $1 is a MAC address

CheckMAC()
{

	if [ 1 -ne $# ]; then
		LogMsg "CheckIP accepts 1 arguments: IP address"
		return 100
	fi
	
	# allow lower and upper-case, as well as : (colon) or - (hyphen) as separators
	echo "$1" | grep -E '^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$' >/dev/null 2>&1
	
	return $?

}

# Function to set interface $1 to whatever the dhcp server assigns
SetIPfromDHCP()
{
	if [ 1 -ne $# ]; then
		LogMsg "SetIPfromDHCP accepts 1 argument: network interface to assign the ip to"
		return 100
	fi
	
	# Check first argument
	ip link show "$1" >/dev/null 2>&1
	if [ 0 -ne $? ]; then
		LogMsg "Network adapter $1 is not working."
		return 1
	fi
	
	ip addr flush "$1"
	
	GetDistro
	case $DISTRO in
		redhat*)
			dhclient -r "$1" ; dhclient "$1"
			if [ 0 -ne $? ]; then
				LogMsg "Unable to get dhcpd address for interface $1"
				return 2
			fi
			;;
		centos*)
			dhclient -r "$1" ; dhclient "$1"
			if [ 0 -ne $? ]; then
				LogMsg "Unable to get dhcpd address for interface $1"
				return 2
			fi
			;;
		debian*)
			dhclient -r "$1" ; dhclient "$1"
			if [ 0 -ne $? ]; then
				LogMsg "Unable to get dhcpd address for interface $1"
				return 2
			fi
			;;
		suse*)
			dhcpcd -k "$1" ; dhcpcd "$1"
			if [ 0 -ne $? ]; then
				LogMsg "Unable to get dhcpd address for interface $1"
				return 2
			fi
			;;
		ubuntu*)
			dhclient -r "$1" ; dhclient "$1"
			if [ 0 -ne $? ]; then
				LogMsg "Unable to get dhcpd address for interface $1"
				return 2
			fi
			;;
		*)
			LogMsg "Platform not supported yet!"
			return 3
			;;
	esac
	
	declare __IP_ADDRESS
	# Get IP-Address
	__IP_ADDRESS=$(ip -o addr show "$1" | grep -vi inet6 | cut -d '/' -f1 | awk '{print $NF}')

	if [ -z "$__IP_ADDRESS" ]; then
		LogMsg "IP address did not get assigned to $1"
		return 3
	fi
	# OK
	return 0

}

# Set static IP $1 on interface $2
# It's up to the caller to make sure the interface is shut down in case this function fails
# Parameters:
# $1 == static ip
# $2 == interface
# $3 == netmask optional
SetIPstatic()
{
	if [ 2 -gt $# ]; then
		LogMsg "SetIPstatic accepts 3 arguments: 1. static IP, 2. network interface, 3. (optional) netmask"
		return 100
	fi
	
	CheckIP "$1"
	if [ 0 -ne $? ]; then
		LogMsg "Parameter $1 is not a valid IPv4 Address"
		return 1
	fi
	
	ip link show "$2" > /dev/null 2>&1
	if [ 0 -ne $? ]; then
		LogMsg "Network adapter $2 is not working."
		return 2
	fi
	
	declare __netmask
	declare __interface
	declare __ip
	
	__netmask=${3:-255.255.255.0}
	__interface="$2"
	__ip="$1"
	
	echo "$__netmask" | grep '.' >/dev/null 2>&1
	if [  0 -eq $? ]; then
		__netmask=$(NetmaskToCidr "$__netmask")
		if [ 0 -ne $? ]; then
			LogMsg "SetIPstatic: $__netmask is not a valid netmask"
			return 3
		fi
	fi
	
	if [ "$__netmask" -ge 32 -o "$__netmask" -le 0 ]; then
		LogMsg "SetIPstatic: $__netmask is not a valid cidr netmask"
		return 4
	fi
	
	ip link set "$__interface" down
	ip addr flush "$__interface"
	ip addr add "$__ip"/"$__netmask" dev "$__interface"
	ip link set "$__interface" up
	
	if [ 0 -ne $? ]; then
		LogMsg "Unable to assign address $__ip/$__netmask to $__interface."
		return 5
	fi
	
	# Get IP-Address
	declare __IP_ADDRESS
	__IP_ADDRESS=$(ip -o addr show "${SYNTH_NET_INTERFACES[$__iterator]}" | grep -vi inet6 | cut -d '/' -f1 | awk '{print $NF}' | grep -vi '[a-z]')

	if [ -z "$__IP_ADDRESS" ]; then
		LogMsg "IP address $__ip did not get assigned to $__interface"
		return 3
	fi

	# Check that addresses match
	if [ "$__IP_ADDRESS" != "$__ip" ]; then
		LogMsg "New address $__IP_ADDRESS differs from static ip $__ip on interface $__interface"
		return 6
	fi

	# OK
	return 0
}

# translate network mask to CIDR notation
# Parameters:
# $1 == valid network mask
NetmaskToCidr()
{
	if [ 1 -ne $# ]; then
		LogMsg "NetmaskToCidr accepts 1 argument: a valid network mask"
		return 100
	fi
	
	declare -i netbits=0
	oldifs="$IFS"
	IFS=.
	
	for dec in $1; do
		case $dec in
			255)
				netbits=$((netbits+8))
				;;
			254)
				netbits=$((netbits+7))
				;;
			252)
				netbits=$((netbits+6))
				;;
			248)
				netbits=$((netbits+5))
				;;
			240)
				netbits=$((netbits+4))
				;;
			224)
				netbits=$((netbits+3))
				;;
			192)
				netbits=$((netbits+2))
				;;
			128)
				netbits=$((netbits+1))
				;;
			0)	#nothing to add
				;;
			*)
				LogMsg "NetmaskToCidr: $1 is not a valid netmask"
				return 1
				;;
		esac
	done
	
	echo $netbits
	
	return 0
}

# Remove all default gateways
RemoveDefaultGateway()
{
	while ip route del default >/dev/null 2>&1
	do : #nothing
	done
	
	return 0
}

# Create default gateway
# Parameters:
# $1 == gateway ip
# $2 == interface
CreateDefaultGateway()
{
	if [ 2 -ne $# ]; then
		LogMsg "CreateDefaultGateway expects 2 argument"
		return 100
	fi
	
	# check that $1 is an IP address
	CheckIP "$1"
	
	if [ 0 -ne $? ]; then
		LogMsg "CreateDefaultGateway: $1 is not a valid IP Address"
		return 1
	fi
	
	# check interface exists
	ip link show "$2" >/dev/null 2>&1
	if [ 0 -ne $? ]; then
		LogMsg "CreateDefaultGateway: no interface $2 found."
		return 2
	fi
	
	
	declare __interface
	declare __ipv4
	
	__ipv4="$1"
	__interface="$2"
	
	# before creating the new default route, delete any old route
	RemoveDefaultGateway
	
	# create new default gateway
	ip route add default via "$__ipv4" dev "$__interface"
	
	if [ 0 -ne $? ]; then
		LogMsg "CreateDefaultGateway: unable to set $__ipv4 as a default gateway for interface $__interface"
		return 3
	fi
	
	# check to make sure default gateway actually was created
	ip route show | grep -i "default via $__ipv4 dev $__interface" >/dev/null 2>&1
	
	if [ 0 -ne $? ]; then
		LogMsg "CreateDefaultGateway: Route command succeded, but gateway does not appear to have been set."
		return 4
	fi
	
	return 0
}

# Create Vlan Config
# Parameters:
# $1 == interface for which to create the vlan config file
# $2 == static IP to set for vlan interface
# $3 == netmask for that interface
# $4 == vlan ID
CreateVlanConfig()
{
	if [ 4 -ne $# ]; then
		LogMsg "CreateVlanConfig expects 4 argument"
		return 100
	fi
	
	# check interface exists
	ip link show "$1" >/dev/null 2>&1
	if [ 0 -ne $? ]; then
		LogMsg "CreateVlanConfig: no interface $1 found."
		return 1
	fi
	
	# check that $2 is an IP address
	CheckIP "$2"
	
	if [ 0 -ne $? ]; then
		LogMsg "CreateVlanConfig: $2 is not a valid IP Address"
		return 2
	fi
	
	declare __noreg='^[0-4096]+'
	# check $4 for valid vlan range
	if ! [[ $4 =~ $__noreg ]] ; then
		LogMsg "CreateVlanConfig: invalid vlan ID $4 received."
		return 3
	fi
	
	# check that vlan driver is loaded
	
	lsmod | grep 8021q
	
	if [ 0 -ne $? ]; then
		modprobe 8021q
	fi
	
	declare __interface
	declare __ip
	declare __netmask
	declare __vlanID
	declare __file_path
	declare __vlan_file_path
	
	__interface="$1"
	__ip="$2"
	__netmask="$3"
	__vlanID="$4"
	
	GetDistro
	case $DISTRO in
		redhat*)
			__file_path="/etc/sysconfig/network-scripts/ifcfg-$__interface"
			if [ -e "$__file_path" ]; then
				LogMsg "CreateVlanConfig: warning, $__file_path already exists."
				if [ -d "$__file_path" ]; then
					rm -rf "$__file_path"
				else
					rm -f "$__file_path"
				fi
			fi
			
			__vlan_file_path="/etc/sysconfig/network-scripts/ifcfg-$__interface.$__vlanID"
			if [ -e "$__vlan_file_path" ]; then
				LogMsg "CreateVlanConfig: warning, $__vlan_file_path already exists."
				if [ -d "$__vlan_file_path" ]; then
					rm -rf "$__vlan_file_path"
				else
					rm -f "$__vlan_file_path"
				fi
			fi
			
			cat <<-EOF > "$__file_path"
				DEVICE=$__interface
				TYPE=Ethernet
				BOOTPROTO=none
				ONBOOT=yes
			EOF
			
			cat <<-EOF > "$__vlan_file_path"
				DEVICE=$__interface.$__vlanID
				BOOTPROTO=none
				IPADDR=$__ip
				NETMASK=$__netmask
				ONBOOT=yes
				VLAN=yes
			EOF
			
			ifdown "$__interface"
			ifup "$__interface"
			ifup "$__interface.$__vlanID"
			
			;;
		suse_12*)
			__file_path="/etc/sysconfig/network/ifcfg-$__interface"
			if [ -e "$__file_path" ]; then
				LogMsg "CreateVlanConfig: warning, $__file_path already exists."
				if [ -d "$__file_path" ]; then
					rm -rf "$__file_path"
				else
					rm -f "$__file_path"
				fi
			fi
			
			__vlan_file_path="/etc/sysconfig/network/ifcfg-$__interface.$__vlanID"
			if [ -e "$__vlan_file_path" ]; then
				LogMsg "CreateVlanConfig: warning, $__vlan_file_path already exists."
				if [ -d "$__vlan_file_path" ]; then
					rm -rf "$__vlan_file_path"
				else
					rm -f "$__vlan_file_path"
				fi
			fi
			
			cat <<-EOF > "$__file_path"
				TYPE=Ethernet
				BOOTPROTO=none
				STARTMODE=auto
			EOF
			
			cat <<-EOF > "$__vlan_file_path"
				ETHERDEVICE=$__interface
				BOOTPROTO=static
				IPADDR=$__ip
				NETMASK=$__netmask
				STARTMODE=auto
				VLAN=yes
			EOF
			
			# bring real interface down and up again
			wicked ifdown "$__interface"
			wicked ifup "$__interface"
			# bring also vlan interface up
			wicked ifup "$__interface.$__vlanID"
			;;
		suse*)
			__file_path="/etc/sysconfig/network/ifcfg-$__interface"
			if [ -e "$__file_path" ]; then
				LogMsg "CreateVlanConfig: warning, $__file_path already exists."
				if [ -d "$__file_path" ]; then
					rm -rf "$__file_path"
				else
					rm -f "$__file_path"
				fi
			fi
			
			__vlan_file_path="/etc/sysconfig/network/ifcfg-$__interface.$__vlanID"
			if [ -e "$__vlan_file_path" ]; then
				LogMsg "CreateVlanConfig: warning, $__vlan_file_path already exists."
				if [ -d "$__vlan_file_path" ]; then
					rm -rf "$__vlan_file_path"
				else
					rm -f "$__vlan_file_path"
				fi
			fi
			
			cat <<-EOF > "$__file_path"
				BOOTPROTO=static
				IPADDR=0.0.0.0
				STARTMODE=auto
			EOF
			
			cat <<-EOF > "$__vlan_file_path"
				BOOTPROTO=static
				IPADDR=$__ip
				NETMASK=$__netmask
				STARTMODE=auto
				VLAN=yes
				ETHERDEVICE=$__interface
			EOF
			
			ifdown "$__interface"
			ifup "$__interface"
			ifup "$__interface.$__vlanID"
			;;
		debian*|ubuntu*)
			__file_path="/etc/network/interfaces"
			if [ ! -e "$__file_path" ]; then
				LogMsg "CreateVlanConfig: warning, $__file_path does not exist. Creating it..."
				if [ -d "$(dirname $__file_path)" ]; then
					touch "$__file_path"
				else
					rm -f "$(dirname $__file_path)"
					LogMsg "CreateVlanConfig: Warning $(dirname $__file_path) is not a directory"
					mkdir -p "$(dirname $__file_path)"
					touch "$__file_path"
				fi
			fi

			declare __first_iface
			declare __last_line
			declare __second_iface
			# delete any previously existing lines containing the desired vlan interface
			# get first line number containing our interested interface
			__first_iface=$(awk "/iface $__interface/ { print NR; exit }" "$__file_path")
			# if there was any such line found, delete it and any related config lines
			if [ -n "$__first_iface" ]; then
				# get the last line of the file
				__last_line=$(wc -l $__file_path | cut -d ' ' -f 1)
				# sanity check
				if [ "$__first_iface" -gt "$__last_line" ]; then
					LogMsg "CreateVlanConfig: error while parsing $__file_path . First iface line is gt last line in file"
					return 100
				fi

				# get the last x lines after __first_iface
				__second_iface=$((__last_line-__first_iface))

				# if the first_iface was also the last line in the file
				if [ "$__second_iface" -eq 0 ]; then
					__second_iface=$__last_line
				else
					# get the line number of the seconf iface line
					__second_iface=$(tail -n $__second_iface $__file_path | awk "/iface/ { print NR; exit }")

					if [ -z $__second_iface ]; then
						__second_iface="$__last_line"
					else
						__second_iface=$((__first_iface+__second_iface-1))
					fi
					

					if [ "$__second_iface" -gt "$__last_line" ]; then
						LogMsg "CreateVlanConfig: error while parsing $__file_path . Second iface line is gt last line in file"
						return 100
					fi

					if [ "$__second_iface" -le "$__first_iface" ]; then
						LogMsg "CreateVlanConfig: error while parsing $__file_path . Second iface line is gt last line in file"
						return 100
					fi
				fi
				# now delete all lines between the first iface and the second iface
				sed -i "$__first_iface,${__second_iface}d" "$__file_path"
			fi

			sed -i "/auto $__interface/d" "$__file_path"
			# now append our config to the end of the file
			cat << EOF >> "$__file_path"
auto $__interface
iface $__interface inet static
	address 0.0.0.0

auto $__interface.$__vlanID
iface $__interface.$__vlanID inet static
	address $__ip
	netmask $__netmask
EOF

			ifdown "$__interface"
			ifup $__interface
			ifup $__interface.$__vlanID
			;;
		*)
			LogMsg "Platform not supported yet!"
			return 4
			;;
	esac
	
	# verify change took place
	cat /proc/net/vlan/config | grep " $__vlanID "
	
	if [ 0 -ne $? ]; then
		LogMsg "/proc/net/vlan/config has no vlanID of $__vlanID"
		return 5
	fi
	
	return 0
}

# Remove Vlan Config
# Parameters:
# $1 == interface from which to remove the vlan config file
# $2 == vlan ID
RemoveVlanConfig()
{
	if [ 2 -ne $# ]; then
		LogMsg "RemoveVlanConfig expects 2 argument"
		return 100
	fi
	
	# check interface exists
	ip link show "$1" >/dev/null 2>&1
	if [ 0 -ne $? ]; then
		LogMsg "RemoveVlanConfig: no interface $1 found."
		return 1
	fi
	
	declare __noreg='^[0-4096]+'
	# check $2 for valid vlan range
	if ! [[ $2 =~ $__noreg ]] ; then
		LogMsg "RemoveVlanConfig: invalid vlan ID $2 received."
		return 2
	fi
	
	declare __interface
	declare __ip
	declare __netmask
	declare __vlanID
	declare __file_path
	
	__interface="$1"
	__vlanID="$2"
	
	GetDistro
	case $DISTRO in
		redhat*)
			__file_path="/etc/sysconfig/network-scripts/ifcfg-$__interface.$__vlanID"
			if [ -e "$__file_path" ]; then
				LogMsg "RemoveVlanConfig: found $__file_path ."
				if [ -d "$__file_path" ]; then
					rm -rf "$__file_path"
				else
					rm -f "$__file_path"
				fi
			fi
			service network restart 2>&1
			
			# make sure the interface is down
			ip link set "$__interface.$__vlanID" down
			;;
		suse_12*)
			__file_path="/etc/sysconfig/network/ifcfg-$__interface.$__vlanID"
			if [ -e "$__file_path" ]; then
				LogMsg "RemoveVlanConfig: found $__file_path ."
				if [ -d "$__file_path" ]; then
					rm -rf "$__file_path"
				else
					rm -f "$__file_path"
				fi
			fi
			wicked ifdown "$__interface.$__vlanID"
			# make sure the interface is down
			ip link set "$__interface.$__vlanID" down
			;;
		suse*)
			__file_path="/etc/sysconfig/network/ifcfg-$__interface.$__vlanID"
			if [ -e "$__file_path" ]; then
				LogMsg "RemoveVlanConfig: found $__file_path ."
				if [ -d "$__file_path" ]; then
					rm -rf "$__file_path"
				else
					rm -f "$__file_path"
				fi
			fi

			ifdown $__interface.$__vlanID
			ifdown $__interface
			ifup $__interface

			# make sure the interface is down
			ip link set "$__interface.$__vlanID" down
			;;
		debian*|ubuntu*)
			__file_path="/etc/network/interfaces"
			if [ ! -e "$__file_path" ]; then
				LogMsg "RemoveVlanConfig: warning, $__file_path does not exist."
				return 0
			fi
			if [ ! -d "$(dirname $__file_path)" ]; then
				LogMsg "RemoveVlanConfig: warning, $(dirname $__file_path) does not exist."
				return 0
			else
				rm -f "$(dirname $__file_path)"
				LogMsg "CreateVlanConfig: Warning $(dirname $__file_path) is not a directory"
				mkdir -p "$(dirname $__file_path)"
				touch "$__file_path"
			fi

			declare __first_iface
			declare __last_line
			declare __second_iface
			# delete any previously existing lines containing the desired vlan interface
			# get first line number containing our interested interface
			__first_iface=$(awk "/iface $__interface.$__vlanID/ { print NR; exit }" "$__file_path")
			# if there was any such line found, delete it and any related config lines
			if [ -n "$__first_iface" ]; then
				# get the last line of the file
				__last_line=$(wc -l $__file_path | cut -d ' ' -f 1)
				# sanity check
				if [ "$__first_iface" -gt "$__last_line" ]; then
					LogMsg "CreateVlanConfig: error while parsing $__file_path . First iface line is gt last line in file"
					return 100
				fi

				# get the last x lines after __first_iface
				__second_iface=$((__last_line-__first_iface))

				# if the first_iface was also the last line in the file
				if [ "$__second_iface" -eq 0 ]; then
					__second_iface=$__last_line
				else
					# get the line number of the seconf iface line
					__second_iface=$(tail -n $__second_iface $__file_path | awk "/iface/ { print NR; exit }")

					if [ -z $__second_iface ]; then
						__second_iface="$__last_line"
					else
						__second_iface=$((__first_iface+__second_iface-1))
					fi
					

					if [ "$__second_iface" -gt "$__last_line" ]; then
						LogMsg "CreateVlanConfig: error while parsing $__file_path . Second iface line is gt last line in file"
						return 100
					fi

					if [ "$__second_iface" -le "$__first_iface" ]; then
						LogMsg "CreateVlanConfig: error while parsing $__file_path . Second iface line is gt last line in file"
						return 100
					fi
				fi
				# now delete all lines between the first iface and the second iface
				sed -i "$__first_iface,${__second_iface}d" "$__file_path"
			fi

			sed -i "/auto $__interface.$__vlanID/d" "$__file_path"

			;;
		*)
			LogMsg "Platform not supported yet!"
			return 3
			;;
	esac
	
	return 0
	
}

# Create ifup config file
# Parameters:
# $1 == interface name
# $2 == static | dhcp
# $3 == IP Address
# $4 == Subnet Mask
# if $2 is set to dhcp, $3 and $4 are ignored
CreateIfupConfigFile()
{
	if [ 2 -gt $# -o 4 -lt $# ]; then
		LogMsg "CreateIfupConfigFile accepts between 2 and 4 arguments"
		return 100
	fi
	
	# check interface exists
	ip link show "$1" >/dev/null 2>&1
	if [ 0 -ne $? ]; then
		LogMsg "CreateIfupConfigFile: no interface $1 found."
		return 1
	fi
	
	declare __interface_name="$1"
	declare __create_static=0
	declare __ip
	declare __netmask
	declare __file_path
	
	case "$2" in
		static)
			__create_static=1
			;;
		dhcp)
			__create_static=0
			;;
		*)
			LogMsg "CreateIfupConfigFile: \$2 needs to be either static or dhcp (received $2)"
			return 2
			;;
	esac
	
	if [ "$__create_static" -eq 0 ]; then
		# create config file for dhcp
		GetDistro
		case $DISTRO in
			suse_12*)
				__file_path="/etc/sysconfig/network/ifcfg-$__interface_name"
				if [ ! -d "$(dirname $__file_path)" ]; then
					LogMsg "CreateIfupConfigFile: $(dirname $__file_path) does not exist! Something is wrong with the network config!"
					return 3
				fi
				
				if [ -e "$__file_path" ]; then
					LogMsg "CreateIfupConfigFile: Warning will overwrite $__file_path ."
				fi
				
				cat <<-EOF > "$__file_path"
					STARTMODE=manual
					BOOTPROTO=dhcp
				EOF
				
				wicked ifdown "$__interface_name"
				wicked ifup "$__interface_name"
				
				;;
			suse*)
				__file_path="/etc/sysconfig/network/ifcfg-$__interface_name"
				if [ ! -d "$(dirname $__file_path)" ]; then
					LogMsg "CreateIfupConfigFile: $(dirname $__file_path) does not exist! Something is wrong with the network config!"
					return 3
				fi
				
				if [ -e "$__file_path" ]; then
					LogMsg "CreateIfupConfigFile: Warning will overwrite $__file_path ."
				fi
				
				cat <<-EOF > "$__file_path"
					STARTMODE=manual
					BOOTPROTO=dhcp
				EOF
				
				ifdown "$__interface_name"
				ifup "$__interface_name"
				
				;;
			redhat*)
				__file_path="/etc/sysconfig/network-scripts/ifcfg-$__interface_name"
				if [ ! -d "$(dirname $__file_path)" ]; then
					LogMsg "CreateIfupConfigFile: $(dirname $__file_path) does not exist! Something is wrong with the network config!"
					return 3
				fi
				
				if [ -e "$__file_path" ]; then
					LogMsg "CreateIfupConfigFile: Warning will overwrite $__file_path ."
				fi
				
				cat <<-EOF > "$__file_path"
					DEVICE="$__interface_name"
					BOOTPROTO=dhcp
				EOF
				
				ifdown "$__interface_name"
				ifup "$__interface_name"
				;;
			*)
				LogMsg "CreateIfupConfigFile: Platform not supported yet!"
				return 3
				;;
		esac
	else
		# create config file for static
		if [ $# -ne 4 ]; then
			LogMsg "CreateIfupConfigFile: if static config is selected, please provide 4 arguments"
			return 100
		fi
		
		CheckIP "$3"
		
		if [ 0 -ne $? ]; then
			LogMsg "CreateIfupConfigFile: $3 is not a valid IP Address"
			return 2
		fi
		
		__ip="$3"
		__netmask="$4"
		
		GetDistro
		
		case $DISTRO in
			suse_12*)
				__file_path="/etc/sysconfig/network/ifcfg-$__interface_name"
				if [ ! -d "$(dirname $__file_path)" ]; then
					LogMsg "CreateIfupConfigFile: $(dirname $__file_path) does not exist! Something is wrong with the network config!"
					return 3
				fi
				
				if [ -e "$__file_path" ]; then
					LogMsg "CreateIfupConfigFile: Warning will overwrite $__file_path ."
				fi
				
				cat <<-EOF > "$__file_path"
					STARTMODE=manual
					BOOTPROTO=static
					IPADDR="$__ip"
					NETMASK="$__netmask"
				EOF
				
				wicked ifdown "$__interface_name"
				wicked ifup "$__interface_name"
				;;
			suse*)
				__file_path="/etc/sysconfig/network/ifcfg-$__interface_name"
				if [ ! -d "$(dirname $__file_path)" ]; then
					LogMsg "CreateIfupConfigFile: $(dirname $__file_path) does not exist! Something is wrong with the network config!"
					return 3
				fi
				
				if [ -e "$__file_path" ]; then
					LogMsg "CreateIfupConfigFile: Warning will overwrite $__file_path ."
				fi
				
				cat <<-EOF > "$__file_path"
					STARTMODE=manual
					BOOTPROTO=static
					IPADDR="$__ip"
					NETMASK="$__netmask"
				EOF
				
				ifdown "$__interface_name"
				ifup "$__interface_name"
				;;
			redhat*)
				__file_path="/etc/sysconfig/network-scripts/ifcfg-$__interface_name"
				if [ ! -d "$(dirname $__file_path)" ]; then
					LogMsg "CreateIfupConfigFile: $(dirname $__file_path) does not exist! Something is wrong with the network config!"
					return 3
				fi
				
				if [ -e "$__file_path" ]; then
					LogMsg "CreateIfupConfigFile: Warning will overwrite $__file_path ."
				fi
				
				cat <<-EOF > "$__file_path"
					DEVICE="$__interface_name"
					BOOTPROTO=none
					IPADDR="$__ip"
					NETMASK="$__netmask"
					NM_CONTROLLED=no
				EOF
				
				ifdown "$__interface_name"
				ifup "$__interface_name"
				;;
			*)
				LogMsg "CreateIfupConfigFile: Platform not supported yet!"
				return 3
				;;
		esac
	fi
	
	return 0
}

# Control Network Manager
# Parameters:
# $1 == start | stop
ControlNetworkManager()
{
	if [ 1 -ne $# ]; then
		LogMsg "ControlNetworkManager accepts 1 argument: start | stop"
		return 100
	fi
	
	# Check first argument
	if [ x"$1" != xstop ]; then
		if [ x"$1" != xstart ]; then
			LogMsg "ControlNetworkManager accepts 1 argument: start | stop."
			return 100
		fi
	fi
	
	GetDistro
	case $DISTRO in
		redhat*)
			# check that we have a NetworkManager service running
			service NetworkManager status
			if [ 0 -ne $? ]; then
				LogMsg "NetworkManager does not appear to be running."
				return 0
			fi
			# now try to start|stop the service
			service NetworkManager $1
			if [ 0 -ne $? ]; then
				LogMsg "Unable to $1 NetworkManager."
				return 1
			else
				LogMsg "Successfully ${1}ed NetworkManager."
			fi
			;;
		centos*)
			# check that we have a NetworkManager service running
			service NetworkManager status
			if [ 0 -ne $? ]; then
				LogMsg "NetworkManager does not appear to be running."
				return 0
			fi
			# now try to start|stop the service
			service NetworkManager $1
			if [ 0 -ne $? ]; then
				LogMsg "Unable to $1 NetworkManager."
				return 1
			else
				LogMsg "Successfully ${1}ed NetworkManager."
			fi
			;;
		debian*)
			# check that we have a NetworkManager service running
			service network-manager status
			if [ 0 -ne $? ]; then
				LogMsg "NetworkManager does not appear to be running."
				return 0
			fi
			# now try to start|stop the service
			service network-manager $1
			if [ 0 -ne $? ]; then
				LogMsg "Unable to $1 NetworkManager."
				return 1
			else
				LogMsg "Successfully ${1}ed NetworkManager."
			fi
			;;
		suse*)
			# no service file
			# edit /etc/sysconfig/network/config and set NETWORKMANAGER=no
			declare __nm_activated
			if [ x"$1" = xstart ]; then
				__nm_activated=yes
			else
				__nm_activated=no
			fi
			
			if [ -f /etc/sysconfig/network/config ]; then
				grep '^NETWORKMANAGER=' /etc/sysconfig/network/config
				if [ 0 -eq $? ]; then
					sed -i "s/^NETWORKMANAGER=.*/NETWORKMANAGER=$__nm_activated/g" /etc/sysconfig/network/config
				else
					echo "NETWORKMANAGER=$__nm_activated" >> /etc/sysconfig/network/config
				fi
				
				# before restarting service, save the LIS network interface details and restore them after restarting. (or at least try)
				# this needs to be done in the caller, as this function cannot be expected to read the constants file and know which interface to reconfigure.
				service network restart
			else
				LogMsg "No network config file found at /etc/sysconfig/network/config"
				return 1
			fi
			
			LogMsg "Successfully ${1}ed NetworkManager."
			;;
		ubuntu*)
			# check that we have a NetworkManager service running
			service network-manager status
			if [ 0 -ne $? ]; then
				LogMsg "NetworkManager does not appear to be running."
				return 0
			fi
			# now try to start|stop the service
			service network-manager $1
			if [ 0 -ne $? ]; then
				LogMsg "Unable to $1 NetworkManager."
				return 1
			else
				LogMsg "Successfully ${1}ed NetworkManager."
			fi
			;;
		*)
			LogMsg "Platform not supported yet!"
			return 3
			;;
	esac
	
	return 0
}

# Convenience Function to disable NetworkManager
DisableNetworkManager()
{
	ControlNetworkManager stop
	# propagate return value from ControlNetworkManager
	return $?
}

# Convenience Function to enable NetworkManager
EnableNetworkManager()
{
	ControlNetworkManager start
	# propagate return value from ControlNetworkManager
	return $?
}

# Setup a bridge named br0
# $1 == Bridge IP Address
# $2 == Bridge netmask
# $3 - $# == Interfaces to attach to bridge
# if no parameter is given outside of IP and Netmask, all interfaces will be added (except lo)
SetupBridge()
{
	
	if [ $# -lt 2 ]; then
		LogMsg "SetupBridge needs at least 2 parameters"
		return 1
	fi
	
	declare -a __bridge_interfaces
	declare __bridge_ip
	declare __bridge_netmask
	
	CheckIP "$1"
	
	if [ 0 -ne $? ]; then
		LogMsg "SetupBridge: $1 is not a valid IP Address"
		return 2
	fi
	
	__bridge_ip="$1"
	__bridge_netmask="$2"

	echo "$__bridge_netmask" | grep '.' >/dev/null 2>&1
	if [  0 -eq $? ]; then
		__bridge_netmask=$(NetmaskToCidr "$__bridge_netmask")
		if [ 0 -ne $? ]; then
			LogMsg "SetupBridge: $__bridge_netmask is not a valid netmask"
			return 3
		fi
	fi
	
	if [ "$__bridge_netmask" -ge 32 -o "$__bridge_netmask" -le 0 ]; then
		LogMsg "SetupBridge: $__bridge_netmask is not a valid cidr netmask"
		return 4
	fi
	
	if [ 2 -eq $# ]; then
		LogMsg "SetupBridge received no interface argument. All network interfaces found will be attached to the bridge."
		# Get all synthetic interfaces
		GetSynthNetInterfaces
		# Remove the loopback interface
		SYNTH_NET_INTERFACES=(${SYNTH_NET_INTERFACES[@]/lo/})
		
		# Get the legacy interfaces
		GetLegacyNetInterfaces
		# Remove the loopback interface
		LEGACY_NET_INTERFACES=(${LEGACY_NET_INTERFACES[@]/lo/})
		# Remove the bridge itself
		LEGACY_NET_INTERFACES=(${LEGACY_NET_INTERFACES[@]/br0/})
		
		# concat both arrays and use this new variable from now on.
		__bridge_interfaces=("${SYNTH_NET_INTERFACES[@]}" "${LEGACY_NET_INTERFACES[@]}")
		
		if [ ${#__bridge_interfaces[@]} -eq 0 ]; then
			LogMsg "SetupBridge: No interfaces found"
			return 3
		fi
		
	else
		# get rid of the first two parameters
		shift
		shift
		# and loop through the remaining ones
		declare __iterator
		for __iterator in "$@"; do
			ip link show "$__iterator" >/dev/null 2>&1
			if [ 0 -ne $? ]; then
				LogMsg "SetupBridge: Interface $__iterator not working or not present"
				return 4
			fi
			__bridge_interfaces=("${__bridge_interfaces[@]}" "$__iterator")
		done
	fi
	
	# create bridge br0
	brctl addbr br0
	if [ 0 -ne $? ]; then
		LogMsg "SetupBridge: unable to create bridge br0"
		return 5
	fi
	
	# turn off stp
	brctl stp br0 off
	
	declare __iface
	# set all interfaces to 0.0.0.0 and then add them to the bridge
	for __iface in ${__bridge_interfaces[@]}; do
		ip link set "$__iface" down
		ip addr flush dev "$__iface"
		ip link set "$__iface" up
		ip link set dev "$__iface" promisc on
		#add interface to bridge
		brctl addif br0 "$__iface"
		if [ 0 -ne $? ]; then
			LogMsg "SetupBridge: unable to add interface $__iface to bridge br0"
			return 6
		fi
		LogMsg "SetupBridge: Added $__iface to bridge"
		echo "1" > /proc/sys/net/ipv4/conf/"$__iface"/proxy_arp
		echo "1" > /proc/sys/net/ipv4/conf/"$__iface"/forwarding
		
	done
	
	#setup forwarding on bridge
	echo "1" > /proc/sys/net/ipv4/conf/br0/forwarding
	echo "1" > /proc/sys/net/ipv4/conf/br0/proxy_arp
	echo "1" > /proc/sys/net/ipv4/ip_forward
	
	ip link set br0 down
	ip addr add "$__bridge_ip"/"$__bridge_netmask" dev br0 
	ip link set br0 up
	LogMsg "$(brctl show br0)"
	LogMsg "SetupBridge: Successfull"
	# done
	return 0
}

# TearDown Bridge br0
TearDownBridge()
{
	ip link show br0 >/dev/null 2>&1
	
	if [ 0 -ne $? ]; then
		LogMsg "TearDownBridge: No interface br0 found"
		return 1
	fi
	
	brctl show br0
	
	if [ 0 -ne $? ]; then
		LogMsg "TearDownBridge: No bridge br0 found"
		return 2
	fi
	
	# get Mac Addresses of interfaces attached to the bridge
	declare __bridge_macs
	__bridge_macs=$(brctl showmacs br0 | grep -i "yes" | cut -f 2)
	
	# get the interfaces associated with those macs
	declare __mac
	declare __bridge_interfaces
	
	for __mac in $__bridge_macs; do
		__bridge_interfaces=$(grep -il "$__mac" /sys/class/net/*/address)
		if [ 0 -ne $? ]; then
			msg="TearDownBridge: MAC Address $__mac does not belong to any interface."
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			return 3
		fi
	
		# get just the interface name from the path
		__bridge_interfaces=$(basename "$(dirname "$__sys_interface")")
		
		ip link show "$__bridge_interfaces" >/dev/null 2>&1
		
		if [ 0 -ne $? ]; then
			LogMsg "TearDownBridge: Could not find interface $__bridge_interfaces"
			return 4
		fi
		
		brctl delif br0 "$__bridge_interfaces"
	done
	
	# remove the bridge itself
	ip link set br0 down
	brctl delbr br0
	
	return 0
	
}

# Check free space
# $1 path to directory to check for free space
# $2 number of bytes to compare
# return == 0 if total free space is greater than $2
# return 1 otherwise

IsFreeSpace()
{
	if [ 2 -ne $# ]; then
		LogMsg "IsFreeSpace takes 2 arguments: path/to/dir to check for free space and number of bytes needed free"
		return 100
	fi
	
	declare -i __total_free_bytes=0
	__total_free_bytes=$(($(df "$1" | awk '/[0-9]%/{print $(NF-2)}')*1024))		#df returnes size in kb-blocks
	if [ "$2" -gt "$__total_free_bytes" ]; then
		return 1
	fi
	return 0
}
