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
#   Basic networking test that checks if VMs can send and receive multicast packets
#
# Steps:
#   Use ping to test multicast
#   On the 2nd VM: ping -I eth1 224.0.0.1 -c 299 > out.client &
#   On the TEST VM: ping -I eth1 224.0.0.1 -c 299 > out.client
#   Check results:
#   On the TEST VM: cat out.client | grep 0%
#   On the 2nd VM: cat out.client | grep 0%
#   If both have 0% packet loss, test is passed
#
########################################################################

# Convert eol
dos2unix utils.sh

# Source SR-IOV_Utils.sh. This is the script that contains all the 
# SR-IOV basic functions (checking drivers, making de bonds, assigning IPs)
. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

UtilsInit

# Set remote user
if [ "${REMOTE_USER:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter REMOTE_USER is not defined in ${LIS_CONSTANTS_FILE} . Using root instead"
    LogMsg "$msg"
    REMOTE_USER=root
fi

ListInterfaces

CreateIfupConfigFile ${SYNTH_NET_INTERFACES[*]} static $STATIC_IP $NETMASK
if [ $? -ne 0 ];then
    msg="ERROR: Could not set static IP on VM1!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
fi

# Configure VM1
#ifconfig eth1 allmulti
ip link set dev eth1 allmulticast on
if [ $? -ne 0 ]; then
    msg="ERROR: Could not enable ALLMULTI on VM1"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
    exit 1
fi

# Configure VM2
ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "ip link set dev eth1 allmulticast on"
if [ $? -ne 0 ]; then
    msg="ERROR: Could not enable ALLMULTI on VM2"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
    exit 1
fi

ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "echo '1' > /proc/sys/net/ipv4/ip_forward"
if [ $? -ne 0 ]; then
    msg="ERROR: Could not enable IP Forwarding on VM2!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "ip route add 224.0.0.0/4 dev eth1"
if [ $? -ne 0 ]; then
    msg="ERROR: Could not add new route to Routing Table on VM2!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "echo '0' > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts"
if [ $? -ne 0 ]; then
    msg="ERROR: Could not enable broadcast listening on VM2!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

# Multicast testing
ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "ping -I eth1 224.0.0.1 -c 299 > out.client &"
if [ $? -ne 0 ]; then
    msg="ERROR: Could not start ping on VM2 (STATIC_IP: ${STATIC_IP2})"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

ping -I eth1 224.0.0.1 -c 299 > out.client
if [ $? -ne 0 ]; then
    msg="ERROR: Could not start ping on VM1 (STATIC_IP: ${STATIC_IP})"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

LogMsg "Info: ping was started on both VMs. Results will be checked in a few seconds"
sleep 5
 
# Check results - Summary must show a 0% loss of packets
multicastSummary=$(cat out.client | grep 0%)
if [ $? -ne 0 ]; then
    msg="ERROR: VM1 shows that packets were lost!"
    LogMsg "$msg"
    LogMsg "${multicastSummary}"
    UpdateSummary "$msg"
    UpdateSummary "${multicastSummary}"
    SetTestStateFailed
    exit 1
fi

# Turn off dependency VM
ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "init 0"

LogMsg "Multicast summary"
LogMsg "${multicastSummary}"

msg="Info: Multicast packets were successfully sent, 0% loss"
LogMsg $msg
UpdateSummary "$msg"
SetTestStateCompleted
