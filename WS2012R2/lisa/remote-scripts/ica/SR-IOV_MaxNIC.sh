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
#   Limit test – one VM with max NICs, max SR-IOV devices - 7
#
# Steps:
#   Create a Linux VM and configure it with the MAX number of synthetic NICs (7 NICs).
#   Configure SR-IOV on each NIC.
#   Verify network connectivity over each SR-IOV device.
# Acceptance Criteria:
#   The max number of SR-IOV devices can be created.
#   Each SR-IOV device has network connectivity.
################################################################################

# Convert eol
dos2unix SR-IOV_Utils.sh

# Adding IPs for all VFs (VM1 and VM2) in constants.sh
sed --in-place '/IP1/d' constants.sh
sed --in-place '/IP2/d' constants.sh

maxVFIterator=14
__iterator=0
__ipIterator1=1
__ipIterator2=1
while [ $__iterator -lt $maxVFIterator ]; do
    echo -e "VF_IP${__ipIterator2}=10.1${__ipIterator1}.12.${__ipIterator2}" >> constants.sh

    if [ $((__iterator%2)) -eq 1 ]; then
        __ipIterator1=$(($__ipIterator1 + 1))    
    fi

    __ipIterator2=$(($__ipIterator2 + 1))
    : $((__iterator++))   
done
sleep 5

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

# Set static IPs to the VFs
ConfigureVF
if [ $? -ne 0 ]; then
    msg="ERROR: Could not set static IPs to the VFs!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

# Pinging
vfCount=$(find /sys/devices -name net -a -ipath '*vmbus*' | grep pci | wc -l)
__iterator=1
__ipIterator=2
while [ $__iterator -le $vfCount ]; do
    staticIP=$(cat constants.sh | grep IP$__ipIterator | tr = " " | awk '{print $2}')

    # Ping the remote host
    ping -I "eth$__iterator" -c 10 "$staticIP" >/dev/null 2>&1
    if [ 0 -eq $? ]; then
        msg="Successfully pinged $staticIP through eth$__iterator"
        LogMsg "$msg"
        UpdateSummary "$msg"
    else
        msg="ERROR: Unable to ping $staticIP through eth$__iterator"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 10
    fi
    __ipIterator=$(($__ipIterator + 2))
    : $((__iterator++))
done

msg="Pinging was successful through all interfaces"
LogMsg $msg
UpdateSummary "$msg"
sleep 5

SetTestStateCompleted