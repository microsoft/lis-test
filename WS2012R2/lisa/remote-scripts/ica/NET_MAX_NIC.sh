#!/bin/bash

########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################

function CheckGateway
{
	# Get interfaces that have default gateway set
	gw_interf=($(route -n | grep 'UG[ \t]' | awk '{print $8}'))

	for if_gw in ${gw_interf[@]}; do
		if [[ ${if_gw} == ${1} ]]; then
			return 0
		fi
	done

	return 1
}

function ConfigureInterfaces
{
	for IFACE in ${IFACES[@]}; do
		if [ $IFACE == "eth0" ]; then
			continue
		fi

		# Get the specific nic name as seen by the VM
		LogMsg "Info : Configuring interface ${IFACE}"
		UpdateSummary "Info : Configuring interface ${IFACE}"
		CreateIfupConfigFile $IFACE dhcp
		if [ $? -eq 0 ]; then
			ip_address=$(ip addr show $IFACE | grep "inet\b" | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1)
			msg="Info : Successfully set IP address - ${ip_address}"
			LogMsg "${msg}"
			UpdateSummary "${msg}"
		else
			LogMsg "Error: Unable to create ifcfg-file for $IFACE"
			UpdateSummary "Error: Unable to create ifcfg-file for $IFACE"
			SetTestStateAborted
			return 1
		fi

		ifdown $IFACE && ifup $IFACE
		#sleep a while after ifup
		sleep 10
		# Chech for gateway
		LogMsg "Info : Checking if default gateway is set for ${IFACE}"
		UpdateSummary "Info : Checking if default gateway is set for ${IFACE}"
		CheckGateway $IFACE
		if [ $? -ne 0 ];  then
			route add -net 0.0.0.0 gw ${DEFAULT_GATEWAY} netmask 0.0.0.0 dev ${IFACE}
			if [ $? -ne 0 ]; then
				LogMsg "Error: Unable to set ${DEFAULT_GATEWAY} as Default Gateway for $IFACE"
				UpdateSummary "Error: Unable to set ${DEFAULT_GATEWAY} as Default Gateway for $IFACE"
			fi
		fi
	done
	return 0
}

#######################################################################
#
# Main script body
#
#######################################################################
#
# Get data about Linux Distribution
#
# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
	echo "Error: unable to source utils.sh!"
	exit 2
}

UtilsInit

if [ "${TEST_TYPE:-UNDEFINED}" = "UNDEFINED" ]; then
	msg="Error : Parameter TEST_TYPE was not found"
	LogMsg "${msg}"
	UpdateSummary "${msg}"
	SetTestStateAborted
	exit 30
else
	IFS=',' read -a TYPE <<< "$TEST_TYPE"
fi

if [ "${SYNTHETIC_NICS:-UNDEFINED}" = "UNDEFINED" ] && [ "${LEGACY_NICS:-UNDEFINED}" = "UNDEFINED" ]; then
	msg="Error : Parameters SYNTHETIC_NICS or LEGACY_NICS were not found"
	LogMsg "${msg}"
	UpdateSummary "${msg}"
	SetTestStateAborted
	exit 30
fi

let EXPECTED_INTERFACES_NO=1
if [ -z "${SYNTHETIC_NICS+x}" ]; then
	LogMsg "Parameter SYNTHETIC_NICS was not found"
else
	let EXPECTED_INTERFACES_NO=$EXPECTED_INTERFACES_NO+$SYNTHETIC_NICS
fi

if [ -z "${LEGACY_NICS+x}" ]; then
	LogMsg "Parameter LEGACY_NICS was not found"
else
	let EXPECTED_INTERFACES_NO=$EXPECTED_INTERFACES_NO+$LEGACY_NICS
fi

GetOSVersion
DEFAULT_GATEWAY=($(route -n | grep 'UG[ \t]' | awk '{print $2}'))

#IFACES=($(ifconfig -s -a | awk '{print $1}'))
IFACES=($(ls /sys/class/net/))

# Check for interfaces with longer names - enp0s10f
# Delete other interfaces - lo, virbr
let COUNTER=0
for i in "${!IFACES[@]}"; do
	if echo "${IFACES[$i]}" | grep -q "lo\|virbr"; then
		unset IFACES[$i]
	fi
	if [[ ${IFACES[$i]} == "enp0s10f" ]]; then
		IFACES[$i]=${IFACES[$i]}${COUNTER}
		let COUNTER=COUNTER+1
	fi
done

UpdateSummary "Info : Array of NICs - ${IFACES}"
#
# Check how many interfaces are visible to the VM
#
if [ ${#IFACES[@]} -ne ${EXPECTED_INTERFACES_NO} ]; then
	msg="Error : Test expected ${EXPECTED_INTERFACES_NO} interfaces to be visible on VM. Found ${#IFACES[@]} interfaces"
	LogMsg "${msg}"
	UpdateSummary "${msg}"
	SetTestStateFailed
	exit 30
fi

#
# Bring interfaces up, using dhcp
#
UpdateSummary "Info : Bringing up interfaces using DHCP"
ConfigureInterfaces
if [ $? -ne 0 ]; then
	SetTestStateFailed
	exit 1
fi

#
# Check if all interfaces have a default gateway
#
GATEWAY_IF=($(route -n | grep 'UG[ \t]' | awk '{print $8}'))
UpdateSummary "Info : Gateway setup for each NIC - ${GATEWAY_IF}"
if [ ${#GATEWAY_IF[@]} -ne $EXPECTED_INTERFACES_NO ]; then
	UpdateSummary "Info : Checking interfaces with missing gateway address"
	LogMsg "Info : Checking interfaces with missing gateway address"
	for IFACE in ${IFACES[@]}; do
		CheckGateway $IFACE
		if [ $? -ne 0 ]; then
			LogMsg "WARNING : No gateway found for interface ${IFACE}. Adding gateway."
			UpdateSummary "WARNING : No gateway found for interface ${IFACE}. Adding gateway."
			route add -net 0.0.0.0 gw ${DEFAULT_GATEWAY} netmask 0.0.0.0 dev ${IFACE}
			if [ $? -ne 0 ]; then
				msg="Error : Unable to set default gateway - ${DEFAULT_GATEWAY} for ${IFACE}"
				LogMsg "${msg}"
				UpdateSummary "${msg}"
				SetTestStateFailed
				exit 2
			fi
		fi
	done
fi

LogMsg "Test run completed"
UpdateSummary "Test run completed"
SetTestStateCompleted
exit 0
