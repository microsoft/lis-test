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

# Description:
#   File copy using VM with multiple NICs bound to SR-IOV
#
#   Steps:
#   1. Boot VMs with 2 or more SR-IOV NICs
#   2. Verify/install pciutils package
#   3. Using the lspci command, examine the NIC with SR-IOV support
#   4. Run bondvf.sh
#   5. Check network capability for all bonds
#   6. Send a 1GB file from VM1 to VM2 through all bonds
#
#############################################################################################################

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

# Check for pciutils. If it's not on the system, install it
lspci --version
if [ $? -ne 0 ]; then
    msg="pciutils not found. Trying to install it"
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
                exit 10
            fi
            ;;
        ubuntu*)
            apt-get install pciutils -y
            if [ $? -ne 0 ]; then
                msg="ERROR: Failed to install pciutils"
                LogMsg "$msg"
                UpdateSummary "$msg"
                SetTestStateFailed
                exit 10
            fi
            ;;
        redhat*|centos*)
            yum install pciutils -y
            if [ $? -ne 0 ]; then
                msg="ERROR: Failed to install pciutils"
                LogMsg "$msg"
                UpdateSummary "$msg"
                SetTestStateFailed
                exit 10
            fi
            ;;
            *)
                msg="ERROR: OS Version not supported"
                LogMsg "$msg"
                UpdateSummary "$msg"
                SetTestStateFailed
                exit 10
            ;;
    esac
fi

# Using lsmod command, verify if driver is loaded
lsmod | grep ixgbevf
if [ $? -ne 0 ]; then
    msg="ERROR: ixgbevf driver not loaded!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

# Using the lspci command, verify if NIC has SR-IOV support
lspci -vvv | grep ixgbevf
if [ $? -ne 0 ]; then
    msg="ERROR: No NIC with SR-IOV support found!"
    LogMsg "$msg"                                                             
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

UpdateSummary "VF is present on VM!"

# Parameter provided in constants file
declare -a STATIC_IPS=()

if [ "${BOND_IP1:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter BOND_IP1 is not defined in constants file. Will try to set addresses via dhcp"
    LogMsg "$msg"
else

    # Split (if necessary) IP Adddresses based on , (comma)
    IFS=',' read -a STATIC_IPS <<< "$BOND_IP1"

    declare -i __iterator
    # Validate that $BOND_IP1 is the correct format
    for __iterator in ${!STATIC_IPS[@]}; do

        CheckIP "${STATIC_IPS[$__iterator]}"

        if [ 0 -ne $? ]; then
            msg="Variable BOND_IP1: ${STATIC_IPS[$__iterator]} does not contain a valid IPv4 address "
            LogMsg "$msg"
            UpdateSummary "$msg"
            SetTestStateAborted
            exit 30
        fi

    done

    unset __iterator

fi

IFS=',' read -a networkType <<< "$NIC"

if [ "${NETMASK:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter NETMASK is not defined in constants file . Defaulting to 255.255.255.0"
    LogMsg "$msg"
    NETMASK=255.255.255.0
fi

if [ "${BOND_IP2:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter BOND_IP2 is not defined in constants file. No network connectivity test will be performed."
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

# set gateway parameter
if [ "${GATEWAY:-UNDEFINED}" = "UNDEFINED" ]; then
    if [ "${networkType[2]}" = "External" ]; then
        msg="The test parameter GATEWAY is not defined in constants file . The default gateway will be set for all interfaces."
        LogMsg "$msg"
        GATEWAY=$(/sbin/ip route | awk '/default/ { print $3 }')
    else
        msg="The test parameter GATEWAY is not defined in constants file . No gateway will be set."
        LogMsg "$msg"
        GATEWAY=''
    fi
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

# Get source to create the file to be sent from VM1 to VM2
if [ "${ZERO_FILE:-UNDEFINED}" = "UNDEFINED" ]; then
    file_source=/dev/urandom
else
    file_source=/dev/zero
fi

# Create file locally with PID appended
output_file=large_file_$$
if [ -d "$HOME"/"$output_file" ]; then
    rm -rf "$HOME"/"$output_file"
fi

if [ -e "$HOME"/"$output_file" ]; then
    rm -f "$HOME"/"$output_file"
fi

dd if=$file_source of="$HOME"/"$output_file" bs=10 count=0 seek=1M
if [ 0 -ne $? ]; then
    msg="ERROR: Unable to create file $output_file in $HOME"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

LogMsg "Successfully created $output_file"

#
# Run bondvf.sh script and configure interfaces properly
#
# Run bonding script from default location - CAN BE CHANGED IN THE FUTURE
if is_ubuntu ; then
    bash /usr/src/linux-headers-*/tools/hv/bondvf.sh

    # Verify if bond0 was created
    __bondCount=$(cat /etc/network/interfaces | grep "auto bond" | wc -l)
    if [ 0 -eq $__bondCount ]; then
        exit 2
    fi


elif is_suse ; then
    bash /usr/src/linux-*/tools/hv/bondvf.sh

    # Verify if bond0 was created
    __bondCount=$(ls -d /etc/sysconfig/network/ifcfg-bond* | wc -l)
    if [ 0 -eq $__bondCount ]; then
        exit 2
    fi

elif is_fedora ; then
    ./bondvf.sh

    # Verify if bond0 was created
    __bondCount=$(ls -d /etc/sysconfig/network-scripts/ifcfg-bond* | wc -l)
    if [ 0 -eq $__bondCount ]; then
        exit 2
    fi
fi

__iterator=0
__ipIterator=1
# Set static IPs for each bond created
while [ $__iterator -lt $__bondCount ]; do
    LogMsg "Network config will start"

    # Extract bondIP value from constants.sh
    staticIP=$(cat constants.sh | grep IP$__ipIterator | tr = " " | awk '{print $2}')

    if is_ubuntu ; then
        __file_path="/etc/network/interfaces"
        # Change /etc/network/interfaces 
        sed -i "s/bond$__iterator inet dhcp/bond$__iterator inet static/g" $__file_path
        sed -i "/bond$__iterator inet static/a address $staticIP" $__file_path
        sed -i "/address $staticIP/a netmask $NETMASK" $__file_path

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

# Add some interface output
LogMsg "$(ip -o addr show bond$__iterator | grep -vi inet6)" 

#
# Run file copy tests for each bond interface 
#
__iterator=0
__ipIterator1=1
__ipIterator2=2
while [ $__iterator -lt $__bondCount ]; do
    # Extract bondIP value from constants.sh
    staticIP1=$(cat constants.sh | grep IP$__ipIterator1 | tr = " " | awk '{print $2}')
    staticIP2=$(cat constants.sh | grep IP$__ipIterator2 | tr = " " | awk '{print $2}')

    # Send 10MB file from VM1 to VM2 via bond0
    scp -i "$HOME"/.ssh/"$sshKey" -o BindAddress=$staticIP1 -o StrictHostKeyChecking=no "$output_file" "$REMOTE_USER"@"$staticIP2":/tmp/"$output_file"
    if [ 0 -ne $? ]; then
        msg="ERROR: Unable to send the file from VM1 to VM2 using bond$__iterator"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 10
    else
        msg="Successfully sent $output_file to $staticIP2"
        LogMsg "$msg"
    fi

    # Verify both bond0 on VM1 and VM2 to see if file was sent between them
    txValue=$(ifconfig bond$__iterator | grep "TX packets" | sed 's/:/ /' | awk '{print $3}')
    LogMsg "TX Value: $txValue"
    if [ $txValue -lt 7000 ]; then
        msg="ERROR: TX packets insufficient"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 10
    fi

    rxValue=$(ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$BOND_IP2" ifconfig bond$__iterator | grep "RX packets" | sed 's/:/ /' | awk '{print $3}')
    LogMsg "RX Value: $rxValue"
    if [ $rxValue -lt 7000 ]; then
        msg="ERROR: RX packets insufficient"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 10
    fi

    # Remove file from VM2
    ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$staticIP2" rm -f /tmp/"$output_file"

    msg="Successfully sent file from VM1 to VM2 through bond${__iterator}"
    LogMsg "$msg"
    UpdateSummary "$msg"
    __ipIterator1=$(($__ipIterator1 + 2))
    __ipIterator2=$(($__ipIterator2 + 2))
    : $((__iterator++))
done
LogMsg "Updating test case state to completed"
SetTestStateCompleted
exit 0