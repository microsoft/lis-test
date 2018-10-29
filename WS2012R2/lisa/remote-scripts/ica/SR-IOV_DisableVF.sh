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
#   Disable VF, verify SR-IOV Failover is working.
#
#   Steps:
#   1. Verify/install pciutils package
#   2. Using the lspci command, examine the NIC with SR-IOV support
#   3. Configure VF
#   4. Check network capability
#   5. Disable VF
#   6. Check network capability (ping & send file to Dependency VM)
#   5. Enable VF
#   6. Check network capability (ping)
#
#############################################################################################################

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
UpdateSummary "VF is present on VM!"

# Set static IP to the VF
ConfigureVF
if [ $? -ne 0 ]; then
    msg="ERROR: Could not set a static IP to the VF!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

# Create an 1gb file to be sent from VM1 to VM2
Create1Gfile
if [ $? -ne 0 ]; then
    msg="ERROR: Could not create the 1gb file on VM1!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

# Set static IPs for each VF
vfCount=$(find /sys/devices -name net -a -ipath '*vmbus*' | grep pci | wc -l)
UpdateSummary "VF count: $vfCount"

# Extract VF name
syntheticInterface=$(ip addr | grep $VF_IP1 | awk '{print $NF}')
LogMsg  "Synthetic interface found: $syntheticInterface"
vfInterface=$(find /sys/devices/* -name "*${syntheticInterface}*" | grep "pci" | sed 's/\// /g' | awk '{print $12}')
LogMsg "Virtual function found: $vfInterface"

# Put VF down
ip link set dev $vfInterface down
ping -c 11 "$VF_IP2" >/dev/null 2>&1
if [ 0 -eq $? ]; then
    LogMsg "Successfully pinged $VF_IP2 with VF down"
    UpdateSummary "Successfully pinged $VF_IP2 with VF down"
else
    LogMsg "Unable to ping $VF_IP2 with VF down"
    UpdateSummary "Unable to ping $VF_IP2 with VF down"
    SetTestStateFailed
    exit 1
fi
# Send 1GB file from VM1 to VM2 via synthetic interface
scp -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$output_file" "$REMOTE_USER"@"$VF_IP2":/tmp/"$output_file"
if [ 0 -ne $? ]; then
    LogMsg "Unable to send the file from VM1 to VM2 ($VF_IP2)"
    UpdateSummary "Unable to send the file from VM1 to VM2 ($VF_IP2)"
    SetTestStateFailed
    exit 1
else
    LogMsg "Successfully sent $output_file to $VF_IP2"
fi
# Get TX value for synthetic interface after sending the file
txValue=$(cat /sys/class/net/${syntheticInterface}/statistics/tx_packets)
LogMsg "TX value after sending the file: $txValue"
if [ $txValue -lt 10000 ]; then
    LogMsg "Insufficient TX packets sent on ${syntheticInterface}"
    UpdateSummary "Insufficient TX packets sent on ${syntheticInterface}"
    SetTestStateFailed
    exit 1
fi

# Put VF up
ip link set dev $vfInterface up
ping -c 11 "$VF_IP2" >/dev/null 2>&1
if [ 0 -ne $? ]; then
    LogMsg "Unable to ping $VF_IP2 with VF down"
    UpdateSummary "Unable to ping $VF_IP2 with VF down"
    SetTestStateFailed
    exit 1
fi
# Send 1GB file from VM1 to VM2 via VF
scp -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$output_file" "$REMOTE_USER"@"$VF_IP2":/tmp/"$output_file"
if [ 0 -ne $? ]; then
    LogMsg "Unable to send the file from VM1 to VM2 ($VF_IP2)"
    UpdateSummary "Unable to send the file from VM1 to VM2 ($VF_IP2)"
    SetTestStateFailed
    exit 1
else
    LogMsg "Successfully sent $output_file to $VF_IP2"
fi
# Get TX value for VF after sending the file
txValue=$(cat /sys/class/net/${vfInterface}/statistics/tx_packets)
LogMsg "TX value after sending the file: $txValue"
if [ $txValue -lt 10000 ]; then
    LogMsg "Insufficient TX packets sent on ${vfInterface}"
    UpdateSummary "Insufficient TX packets sent on ${vfInterface}"
    SetTestStateFailed
    exit 1
fi

# Check for Call traces
CheckCallTracesWithDelay 120

UpdateSummary "Successfully disabled and enabled VF"
SetTestStateCompleted
exit 0