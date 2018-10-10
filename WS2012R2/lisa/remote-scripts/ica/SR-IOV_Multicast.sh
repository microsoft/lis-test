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
#   Basic SR-IOV test that checks if VF can send and receive multicast packets
#
# Steps:
#   Use Ping
#   On the 2nd VM: ping -I eth1 224.0.0.1 -c 11 > out.client &
#   On the TEST VM: ping -I eth1 224.0.0.1 -c 11 > out.client
#   Check results:
#   On the TEST VM: cat out.client | grep 0%
#   On the 2nd VM: cat out.client | grep 0%
#   If both have 0% packet loss, test passed
################################################################################

# Convert eol
dos2unix SR-IOV_Utils.sh

# Source SR-IOV_Utils.sh. This is the script that contains all the 
# SR-IOV basic functions (checking drivers, checking VFs, assigning IPs)
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
    exit 1
fi

# Check if the SR-IOV driver is in use
VerifyVF
if [ $? -ne 0 ]; then
    msg="ERROR: VF is not loaded! Make sure you are using compatible hardware"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi
UpdateSummary "VF is present on VM!"

# Set static IP to the VF
ConfigureVF
if [ $? -ne 0 ]; then
    msg="ERROR: Could not set a static IP to eth1!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

LogMsg "INFO: All configuration completed successfully. Will proceed with the testing"
# Configure VM1
#ifconfig eth1 allmulti
ip link set dev eth1 allmulticast on
if [ $? -ne 0 ]; then
    msg="ERROR: Could not enable ALLMULTI option on VM1!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
    exit 1
fi

# Configure VM2
ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$VF_IP2" "ip link set dev eth1 allmulticast on"
if [ $? -ne 0 ]; then
    msg="ERROR: Could not enable ALLMULTI option on VM2!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
    exit 1
fi

ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$VF_IP2" "echo '1' > /proc/sys/net/ipv4/ip_forward"
if [ $? -ne 0 ]; then
    msg="ERROR: Could not enable IP Forwarding on VM2!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$VF_IP2" "ip route add 224.0.0.0/4 dev eth1"
if [ $? -ne 0 ]; then
    msg="ERROR: Could not add new route to Routing Table on VM2!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$VF_IP2" "echo '0' > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts"
if [ $? -ne 0 ]; then
    msg="ERROR: Could not enable broadcast listening on VM2!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

# Multicast testing
ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$VF_IP2" "ping -I eth1 224.0.0.1 -c 11 > out.client &"
if [ $? -ne 0 ]; then
    msg="ERROR: Could not start ping on VM2 (VF_IP: ${VF_IP2})"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

ping -I eth1 224.0.0.1 -c 11 > out.client
if [ $? -ne 0 ]; then
    msg="ERROR: Could not start ping on VM1 (VF_IP: ${VF_IP1})"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

LogMsg "INFO: Ping was started on both VMs. Results will be checked in a few seconds"
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
fi
LogMsg "Multicast summary"
LogMsg "${multicastSummary}"

msg="Multicast packets were successfully sent, 0% loss"
LogMsg $msg
UpdateSummary "$msg"
SetTestStateCompleted
