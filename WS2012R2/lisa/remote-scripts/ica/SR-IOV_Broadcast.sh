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
#   Basic SR-IOV test that checks if VF can send and receive broadcast packets
# Steps:
#    Use ping for testing & tcpdump to check if the packets were received
#    On the 2nd VM – tcpdump -i eth1 -c 10 ip proto \\icmp > out.client
#    On the TEST VM – ping -b $broadcastAddress -c 13 &
#    On the 2nd VM – cat out.client | grep $broadcastAddress
#    If $?=0 test passed!
##############################################################################

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
fi

# Check if the SR-IOV driver is in use
VerifyVF
if [ $? -ne 0 ]; then
    msg="ERROR: VF is not loaded! Make sure you are using compatible hardware"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

# Set static IP to eth1
ConfigureVF
if [ $? -ne 0 ]; then
    msg="ERROR: Could not set a static IP to the eth1!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

# Install dependencies needed for testing
InstallDependencies
if [ $? -ne 0 ]; then
    msg="ERROR: Could not install dependencies!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed

else
    LogMsg "INFO: All configuration completed successfully. Will proceed with the testing"   
fi

# Broadcast testing
broadcastAddress=$(ip a s dev eth1 | awk '/inet / {print $4}')
ping -b $broadcastAddress -c 13 &
if [ $? -ne 0 ]; then
    msg="ERROR: Could not ping to broadcast address on VM1 (VF_IP: ${VF_IP1})"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$VF_IP2" 'tcpdump -i eth1 -c 10 ip proto \\icmp > out.client'
if [ $? -ne 0 ]; then
    msg="ERROR: Could not start tcpdump on VM2 (VF_IP: ${VF_IP2})"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
else
    LogMsg "INFO: Ping on VM1 and tcpdump on VM2 were successfully started"
    sleep 20
fi

ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$VF_IP2" cat out.client | grep $broadcastAddress
if [ $? -ne 0 ]; then
    msg="ERROR: VM2 didn't receive any packets from the broadcast address"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed

else
    sleep 10
    msg="VM2 successfully received the packets sent to the broadcast address"
    LogMsg $msg
    UpdateSummary "$msg"
    SetTestStateCompleted   
fi