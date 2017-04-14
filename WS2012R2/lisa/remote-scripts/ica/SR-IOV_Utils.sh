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

########################################################################
#
# Description:
#
# This script contains all SR-IOV related functions that are often used
# in the SR-IOV test suite.
#
########################################################################

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Source constants file and initialize most common variables
UtilsInit

# In case of error
case $? in
    0)
        # Do nothing
        ;;
    1)
        LogMsg "ERROR: Unable to cd to $LIS_HOME. Aborting..."
        UpdateSummary "ERROR: Unable to cd to $LIS_HOME. Aborting..."
        SetTestStateAborted
        exit 3
        ;;
    2)
        LogMsg "ERROR: Unable to use test state file. Aborting..."
        UpdateSummary "ERROR: Unable to use test state file. Aborting..."
        # Need to wait for test timeout to kick in
        sleep 60
        echo "TestAborted" > state.txt
        exit 4
        ;;
    3)
        LogMsg "ERROR: unable to source constants file. Aborting..."
        UpdateSummary "ERROR: unable to source constants file"
        SetTestStateAborted
        exit 5
        ;;
    *)
        # Should not happen
        LogMsg "ERROR: UtilsInit returned an unknown error. Aborting..."
        UpdateSummary "ERROR: UtilsInit returned an unknown error. Aborting..."
        SetTestStateAborted
        exit 6
        ;;
esac

# Declare global variables
declare -i bondCount

#
# VerifyVF - check if the VF driver is use
#
VerifyVF()
{
	# Check for pciutils. If it's not on the system, install it
	lspci --version
	if [ $? -ne 0 ]; then
	    msg="INFO: pciutils not found. Trying to install it"
	    LogMsg "$msg"

	    GetDistro
	    case "$DISTRO" in
	        suse*)
	            zypper --non-interactive in pciutils
	            if [ $? -ne 0 ]; then
	                msg="ERROR: Failed to install pciutils"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            fi
	            ;;
	        ubuntu*)
	            apt-get install pciutils -y
	            if [ $? -ne 0 ]; then
	                msg="ERROR: Failed to install pciutils"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            fi
	            ;;
	        redhat*|centos*)
	            yum install pciutils -y
	            if [ $? -ne 0 ]; then
	                msg="ERROR: Failed to install pciutils"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            fi
	            ;;
	            *)
	                msg="ERROR: OS Version not supported"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            ;;
	    esac
	fi

	# Using lsmod command, verify if driver is loaded
	lsmod | grep ixgbevf
	if [ $? -ne 0 ]; then
	    lsmod | grep mlx4_core
	    if [ $? -ne 0 ]; then
	  		msg="ERROR: Neither mlx4_core or ixgbevf drivers are in use!"
	  		LogMsg "$msg"
		    UpdateSummary "$msg"
		    SetTestStateFailed
		    exit 1
		fi
	fi

	# Using the lspci command, verify if NIC has SR-IOV support
	lspci -vvv | grep ixgbevf
	if [ $? -ne 0 ]; then
		lspci -vvv | grep mlx4_core
		if [ $? -ne 0 ]; then
		    msg="No NIC with SR-IOV support found!"
		    LogMsg "$msg"                                                             
		    UpdateSummary "$msg"
		    SetTestStateFailed
		    exit 1
		fi
	fi

	interface=$(ls /sys/class/net/ | grep -v 'eth0\|eth1\|bond*\|lo')
	if [[ is_fedora || is_ubuntu ]]; then
        ifconfig -a | grep $interface
   		if [ $? -ne 0 ]; then
		    msg="ERROR: VF device, $interface , was not found!"
		    LogMsg "$msg"                                                             
		    UpdateSummary "$msg"
		    SetTestStateFailed
		    exit 1
		fi
    fi

	return 0
}

#
# Check_SRIOV_Parameters - check if the needed parameters for SR-IOV 
# testing are present in constants.sh
#
Check_SRIOV_Parameters()
{
	# Parameter provided in constants file
	declare -a STATIC_IPS=()

	if [ "${BOND_IP1:-UNDEFINED}" = "UNDEFINED" ]; then
	    msg="ERROR: The test parameter BOND_IP1 is not defined in constants file. Will try to set addresses via dhcp"
	    LogMsg "$msg"
	    UpdateSummary "$msg"
	    SetTestStateAborted
	    exit 1
	fi

	if [ "${BOND_IP2:-UNDEFINED}" = "UNDEFINED" ]; then
	    msg="ERROR: The test parameter BOND_IP2 is not defined in constants file. No network connectivity test will be performed."
	    LogMsg "$msg"
	    UpdateSummary "$msg"
        SetTestStateAborted
        exit 1
	fi

	IFS=',' read -a networkType <<< "$NIC"
	if [ "${NETMASK:-UNDEFINED}" = "UNDEFINED" ]; then
	    msg="ERROR: The test parameter NETMASK is not defined in constants file . Defaulting to 255.255.255.0"
	    LogMsg "$msg"
	    UpdateSummary "$msg"
        SetTestStateAborted
        exit 1
	fi

	if [ "${sshKey:-UNDEFINED}" = "UNDEFINED" ]; then
	    msg="ERROR: The test parameter sshKey is not defined in ${LIS_CONSTANTS_FILE}"
	    LogMsg "$msg"
	    UpdateSummary "$msg"
        SetTestStateAborted
        exit 1
	fi

	if [ "${REMOTE_USER:-UNDEFINED}" = "UNDEFINED" ]; then
	    msg="ERROR: The test parameter REMOTE_USER is not defined in ${LIS_CONSTANTS_FILE}"
	    LogMsg "$msg"
	    UpdateSummary "$msg"
        SetTestStateAborted
        exit 1
	fi
	
    return 0
}

#
# Create1Gfile - it creates a 1GB file that will be sent between VMs as part of testing
#
Create1Gfile()
{
	output_file=large_file
	
	if [ "${ZERO_FILE:-UNDEFINED}" = "UNDEFINED" ]; then
	    file_source=/dev/urandom
	else
	    file_source=/dev/zero
	fi

	if [ -d "$HOME"/"$output_file" ]; then
	    rm -rf "$HOME"/"$output_file"
	fi

	if [ -e "$HOME"/"$output_file" ]; then
	    rm -f "$HOME"/"$output_file"
	fi

	dd if=$file_source of="$HOME"/"$output_file" bs=1 count=0 seek=1G
	if [ 0 -ne $? ]; then
	    msg="ERROR: Unable to create file $output_file in $HOME"
	    LogMsg "$msg"
	    UpdateSummary "$msg"
	    SetTestStateFailed
	    exit 1
	fi

	LogMsg "Successfully created $output_file"
	return 0
}

#
# RunBondingScript - it will run the bonding script. Acceptance criteria is the
# presence of the bond between VF and eth after the bonding script ran.
# NOTE: function returns the number of bonds present on VM, not "0"
#
RunBondingScript()
{
	if is_ubuntu ; then
	    bash /usr/src/linux-headers-*/tools/hv/bondvf.sh

	    # Verify if bond0 was created
	    bondCount=$(cat /etc/network/interfaces | grep "auto bond" | wc -l)
	    if [ 0 -eq $bondCount ]; then
	        msg="ERROR: Bonding script failed. No bond was created"
		    LogMsg "$msg"
		    UpdateSummary "$msg"
		    SetTestStateFailed
		    return 99
	    fi

	elif is_suse ; then
	    bash /usr/src/linux-*/tools/hv/bondvf.sh

	    # Verify if bond0 was created
	    bondCount=$(ls -d /etc/sysconfig/network/ifcfg-bond* | wc -l)
	    if [ 0 -eq $bondCount ]; then
	        msg="ERROR: Bonding script failed. No bond was created"
		    LogMsg "$msg"
		    UpdateSummary "$msg"
		    SetTestStateFailed
		    return 99
	    fi

	elif is_fedora ; then
	    ./bondvf.sh

	    # Verify if bond0 was created
	    bondCount=$(ls -d /etc/sysconfig/network-scripts/ifcfg-bond* | wc -l)
	    if [ 0 -eq $bondCount ]; then
	        msg="ERROR: Bonding script failed. No bond was created"
		    LogMsg "$msg"
		    UpdateSummary "$msg"
		    SetTestStateFailed
		    return 99
	    fi
	fi

	LogMsg "Successfully ran the bonding script"
	return $bondCount
}

#
# ConfigureBond - will set the given BOND_IP(s) (from constants file) 
# for each bond present 
#
ConfigureBond()
{
	__iterator=0
	__ipIterator=1
	LogMsg "Iterator: $__iterator"
	LogMsg "BondCount: $bondCount"

	# Set static IPs for each bond created
	while [ $__iterator -lt $bondCount ]; do
	    LogMsg "Network config will start"

        # Extract bondIP value from constants.sh
		staticIP=$(cat constants.sh | grep IP$__ipIterator | head -1 | tr = " " | awk '{print $2}')

	    if is_ubuntu ; then
	        __file_path="/etc/network/interfaces"
	        # Change /etc/network/interfaces 
	        sed -i "s/bond$__iterator inet dhcp/bond$__iterator inet static/g" $__file_path
	        sed -i "/bond$__iterator inet static/a address $staticIP" $__file_path
	        sed -i "/address ${staticIP}/a netmask $NETMASK" $__file_path

	    elif is_suse ; then
	        __file_path="/etc/sysconfig/network/ifcfg-bond$__iterator"
	        # Replace the BOOTPROTO, IPADDR and NETMASK values found in ifcfg file 
	        sed -i "/\b\(BOOTPROTO\|IPADDR\|\NETMASK\)\b/d" $__file_path
	        cat <<-EOF >> $__file_path
	        BOOTPROTO=static
	        IPADDR=$staticIP
	        NETMASK=$NETMASK
	EOF

	    elif is_fedora ; then
	        __file_path="/etc/sysconfig/network-scripts/ifcfg-bond$__iterator"
	        # Replace the BOOTPROTO, IPADDR and NETMASK values found in ifcfg file 
	        sed -i "/\b\(BOOTPROTO\|IPADDR\|\NETMASK\)\b/d" $__file_path
	        cat <<-EOF >> $__file_path
	        BOOTPROTO=static
	        IPADDR=$staticIP
	        NETMASK=$NETMASK
	EOF
	    fi
	    LogMsg "Network config file path: $__file_path"

	    # Add some interface output
	    LogMsg "$(ip -o addr show bond$__iterator | grep -vi inet6)"

		__ipIterator=$(($__ipIterator + 2))
	    : $((__iterator++))
	done

    # Get everything up & running
    if is_ubuntu ; then
        service networking restart

    elif is_suse ; then
        service network restart

    elif is_fedora ; then
        service network restart
    fi

	return 0
}

#
# InstallDependencies - will install iperf, omping, netcat, etc
#
InstallDependencies()
{
	# Enable broadcast listening
	echo 0 >/proc/sys/net/ipv4/icmp_echo_ignore_broadcasts

    GetDistro
    case "$DISTRO" in
        suse*)
			# Disable firewall
			rcSuSEfirewall2 stop

			# Check wget 
			wget -V > /dev/null 2>&1
			if [ $? -ne 0 ]; then
				zypper --non-interactive in wget
	            if [ $? -ne 0 ]; then
	                msg="ERROR: Failed to install wget"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            fi
			fi

			# Check iPerf3
			iperf3 -v > /dev/null 2>&1
			if [ $? -ne 0 ]; then
				wget -4 http://download.opensuse.org/repositories/home:/aeneas_jaissle:/sewikom/SLE_12/x86_64/libiperf0-3.1.3-50.1.x86_64.rpm
				if [ $? -ne 0 ]; then
	                msg="ERROR: Failed to download libiperf (this an iperf3 dependency)"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            fi

	            wget -4 http://download.opensuse.org/repositories/home:/aeneas_jaissle:/sewikom/SLE_12/x86_64/iperf-3.1.3-50.1.x86_64.rpm
				if [ $? -ne 0 ]; then
	                msg="ERROR: Failed to download iperf"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            fi

	            rpm -i libiperf*
	            rpm -i iperf*
	            if [ $? -ne 0 ]; then
	                msg="ERROR: Failed to install iperf"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            fi
			fi
            ;;

        ubuntu*)
			# Disable firewall
			ufw disable

			# Check wget 
			wget -V > /dev/null 2>&1
			if [ $? -ne 0 ]; then
				apt-get install wget -y
	            if [ $? -ne 0 ]; then
	                msg="ERROR: Failed to install wget"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            fi
			fi

			# Check iPerf3
			iperf3 -v > /dev/null 2>&1
			if [ $? -ne 0 ]; then
				wget -4 https://iperf.fr/download/ubuntu/libiperf0_3.1.3-1_amd64.deb
				if [ $? -ne 0 ]; then
	                msg="ERROR: Failed to download libiperf (this an iperf3 dependency)"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            fi

	            wget -4 https://iperf.fr/download/ubuntu/iperf3_3.1.3-1_amd64.deb
				if [ $? -ne 0 ]; then
	                msg="ERROR: Failed to download iperf"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            fi

	            dpkg -i libiperf*
	            dpkg -i iperf3*
	            if [ $? -ne 0 ]; then
	                msg="ERROR: Failed to install iperf"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            fi
			fi
            ;;

        redhat*|centos*)
			# Disable firewall
			service firewalld stop

			# Check wget 
			wget -V > /dev/null 2>&1
			if [ $? -ne 0 ]; then
				yum install wget -y
	            if [ $? -ne 0 ]; then
	                msg="ERROR: Failed to install wget"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            fi
			fi

			# Check iPerf3
			iperf3 -v > /dev/null 2>&1
			if [ $? -ne 0 ]; then
	            wget -4 https://iperf.fr/download/fedora/iperf3-3.1.3-1.fc24.x86_64.rpm
				if [ $? -ne 0 ]; then
	                msg="ERROR: Failed to download iperf"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            fi

	            rpm -i iperf3*
	            if [ $? -ne 0 ]; then
	                msg="ERROR: Failed to install iperf"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            fi
			fi
        ;;
        *)
            msg="ERROR: OS Version not supported"
            LogMsg "$msg"
            UpdateSummary "$msg"
            SetTestStateFailed
            exit 1
        ;;
    esac

    return 0
}