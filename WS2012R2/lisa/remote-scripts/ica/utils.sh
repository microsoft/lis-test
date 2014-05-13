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
# Sets the $LEGACY_NET_INTERFACES array elements to an interface name suitable for ifconfig etc.
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
	ifconfig "$1" >/dev/null 2>&1
	if [ 0 -ne $? ]; then
		LogMsg "Network adapter $1 is not working."
		return 1
	fi
	
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
	__IP_ADDRESS=$(ifconfig "$1" | grep "inet addr" | awk -F: '{print $2}' | awk '{print $1}')

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
	
	ifconfig "$2" > /dev/null 2>&1
	if [ 0 -ne $? ]; then
		LogMsg "Network adapter $2 is not working."
		return 2
	fi
	
	declare __NETMASK
	
	__NETMASK=${3:-255.255.255.0}
	
	ifconfig "$2" down && ifconfig "$2" "$1" && ifconfig "$2" netmask "$__NETMASK" && ifconfig "$2" up
	
	if [ 0 -ne $? ]; then
		LogMsg "Unable to assign address $1 (netmask $__NETMASK) to $2."
		return 3
	fi
	
	# Get IP-Address
	declare __IP_ADDRESS
	__IP_ADDRESS=$(ifconfig "$2" | grep "inet addr" | awk -F: '{print $2}' | awk '{print $1}')

	if [ -z "$__IP_ADDRESS" ]; then
		LogMsg "IP address $1 did not get assigned to $2"
		return 3
	fi

	# Check that addresses match
	if [ "$__IP_ADDRESS" != "$1" ]; then
		LogMsg "New address $__IP_ADDRESS differs from static ip $1 on interface $2"
		return 4
	fi

	# OK
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
