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
#   Run ping tests and confirm RTT is reduced from synthetic NIC cases
#
#   Steps:
#   1. Ping a VM from a NIC without SRIOV
#   2. Ping a VM from a NIC with SR-IOV enabled
#   3. Compare the results
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

#
# Set static IPs for each bond created
#
__iterator=0
while [ $__iterator -lt $__bondCount ]; do
    LogMsg "VF config will start"

    if is_ubuntu ; then
        __file_path="/etc/network/interfaces"
        # Change /etc/network/interfaces 
        sed -i "s/bond$__iterator inet dhcp/bond$__iterator inet static/g" $__file_path
        sed -i "/bond$__iterator inet static/a address $BOND_IP1" $__file_path
        sed -i "/address $BOND_IP/a netmask $NETMASK" $__file_path

    elif is_suse ; then
        __file_path="/etc/sysconfig/network/ifcfg-bond$__iterator"
        # Replace the BOOTPROTO, IPADDR and NETMASK values found in ifcfg file 
        sed -i "/\b\(BOOTPROTO\|IPADDR\|\NETMASK\)\b/d" $__file_path
        cat <<-EOF >> $__file_path
        BOOTPROTO=static
        IPADDR=$BOND_IP1
        NETMASK=$NETMASK
EOF

    elif is_fedora ; then
        __file_path="/etc/sysconfig/network-scripts/ifcfg-bond$__iterator"
        # Replace the BOOTPROTO, IPADDR and NETMASK values found in ifcfg file 
        sed -i "/\b\(BOOTPROTO\|IPADDR\|\NETMASK\)\b/d" $__file_path
        cat <<-EOF >> $__file_path
        BOOTPROTO=static
        IPADDR=$BOND_IP1
        NETMASK=$NETMASK
EOF
    fi
    LogMsg "Network config file path: $__file_path"
	
    : $((__iterator++))
done

#
# Set static IP for the Internal NIC
#
LogMsg "Internal NIC config will start"

if is_ubuntu ; then
    __file_path="/etc/network/interfaces"

    # Write configuration data into file
    cat <<-EOF >> $__file_path

    auto eth2
    iface eth2 inet static
    address $STATIC_IP1
    netmask $NETMASK
EOF

elif is_suse ; then
    __file_path="/etc/sysconfig/network/ifcfg-eth2"

    # Write configuration data into file
    cat <<-EOF >> $__file_path
    DEVICE=eth2
    BOOTPROTO=static
    IPADDR=$STATIC_IP1
    NETMASK=$NETMASK
EOF

elif is_fedora ; then
    __file_path="/etc/sysconfig/network-scripts/ifcfg-eth2"

    # Write configuration data into file
    cat <<-EOF >> $__file_path
    DEVICE=eth2
    BOOTPROTO=static
    IPADDR=$STATIC_IP1
    NETMASK=$NETMASK
EOF
fi

# Restart network
if is_ubuntu ; then
    service networking restart

elif is_suse ; then
    service network restart

elif is_fedora ; then
    service network restart
fi
ifup eth2
#
# Ping through Internal and VF adapter and compare RTT results
#
# Make additional configuration changes
internalNIC=eth2
sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w net.ipv4.conf.default.rp_filter=0
sysctl -w net.ipv4.conf.eth0.rp_filter=0
sysctl -w net.ipv4.conf.eth2.rp_filter=0
sleep 5

# Ping using Internal adapter and store results
LogMsg "Ping syntethic"
rttEth=$(ping -I $internalNIC $STATIC_IP2 -c 60 | grep rtt | awk '{print $4}' | tr / " ")
if [ 0 -eq $? ]; then
    msg="Successfully pinged $STATIC_IP2 through $internalNIC"
    LogMsg "$msg"
else
    msg="ERROR: Unable to ping $STATIC_IP2 through $internalNIC"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi
minEth=$(echo $rttEth | awk '{print $1}')
avgEth=$(echo $rttEth | awk '{print $2}')
maxEth=$(echo $rttEth | awk '{print $3}')
mdevEth=$(echo $rttEth | awk '{print $4}')

# Ping using sriov adapter and store results
sleep 5
LogMsg "Ping SR-IOV"
rttBond=$(ping -I bond0 $BOND_IP2 -c 60 | grep rtt | awk '{print $4}' | tr / " ")
if [ 0 -eq $? ]; then
    msg="Successfully pinged $BOND_IP2 through bond0"
    LogMsg "$msg"
else
    msg="ERROR: Unable to ping $BOND_IP2 through bond0"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi
minBond=$(echo $rttBond | awk '{print $1}')
avgBond=$(echo $rttBond | awk '{print $2}')
maxBond=$(echo $rttBond | awk '{print $3}')
mdevBond=$(echo $rttBond | awk '{print $4}')

# Compare results
isGreater=$(echo $avgBond'>'$avgEth | bc -l)

if [ $isGreater -ne 0 ]; then
	msg="ERROR: Ping was not improved with SR-IOV"
	LogMsg "$msg"
	UpdateSummary "$msg"
	LogMsg "SR-IOV RTT Results: MIN=$minBond :: AVG=$avgBond :: MAX=$maxBond :: MDEV=$mdevBond"
	LogMsg "Internal NIC RTT Results: MIN=$minEth :: AVG=$avgEth :: MAX=$maxEth :: MDEV=$mdevEth"
	SetTestStateFailed
    exit 10
else
	msg="Success: SR-IOV ping results are better than Internal NIC ping results"
	LogMsg "$msg"
	UpdateSummary "$msg"
	LogMsg "SR-IOV RTT Results: MIN=$minBond :: AVG=$avgBond :: MAX=$maxBond :: MDEV=$mdevBond"
	LogMsg "Internal NIC RTT Results: MIN=$minEth :: AVG=$avgEth :: MAX=$maxEth :: MDEV=$mdevEth"
fi

LogMsg "Updating test case state to completed"
SetTestStateCompleted
exit 0