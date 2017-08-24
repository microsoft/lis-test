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
#   Ping using VM with multiple NICs bound to SR-IOV.
#
#   Steps:
#   1. Boot VMs with 2 or more SR-IOV NICs
#   2. Verify/install pciutils package
#   3. Using the lspci command, examine the NIC with SR-IOV support
#   4. Configure VF
#   5. Check network capability for all VFs
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

# Set static IP to eth1
ConfigureVF
if [ $? -ne 0 ]; then
    msg="ERROR: Could not set a static IP to eth1!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

#
# Run ping tests for each VF
#
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
    fi
    __ipIterator=$(($__ipIterator + 2))
    : $((__iterator++))
done

LogMsg "Updating test case state to completed"
SetTestStateCompleted
exit 0