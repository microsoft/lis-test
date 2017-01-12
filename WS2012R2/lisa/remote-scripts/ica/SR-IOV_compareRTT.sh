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
dos2unix SR-IOV_Utils.sh

# Source SR-IOV_Utils.sh. This is the script that contains all the 
# SR-IOV basic functions (checking drivers, making de bonds, assigning IPs)
. SR-IOV_Utils.sh || {
    echo "ERROR: unable to source SR-IOV_Utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Check the parameters in constants.sh
Check_SRIOV_Parameters
if [ $? -ne 0 ]; then
    msg="ERROR: The necessary parameters are not present in constants.sh. Please check the xml test file"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

# Check if the SR-IOV driver is in use
VerifyVF
if [ $? -ne 0 ]; then
    msg="ERROR: VF is not loaded! Make sure you are using compatible hardware"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi
UpdateSummary "VF is present on VM!"

# Run the bonding script. Make sure you have this already on the system
# Note: The location of the bonding script may change in the future
RunBondingScript
bondCount=$?
if [ $bondCount -eq 99 ]; then
    msg="ERROR: Running the bonding script failed. Please double check if it is present on the system"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi
LogMsg "BondCount returned by SR-IOV_Utils: $bondCount"

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

# Set static IP to the bond
ConfigureBond
if [ $? -ne 0 ]; then
    msg="ERROR: Could not set a static IP to the bond!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
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