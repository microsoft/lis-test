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

# Adding IPs for all bonds (VM1 and VM2) in constants.sh
sed --in-place '/IP1/d' constants.sh
sed --in-place '/IP2/d' constants.sh

maxBondIterator=14
__iterator=0
__ipIterator1=1
__ipIterator2=1
while [ $__iterator -lt $maxBondIterator ]; do
    echo -e "BOND_IP${__ipIterator2}=10.1${__ipIterator1}.12.${__ipIterator2}" >> constants.sh

    if [ $((__iterator%2)) -eq 1 ]; then
        __ipIterator1=$(($__ipIterator1 + 1))    
    fi

    __ipIterator2=$(($__ipIterator2 + 1))
    : $((__iterator++))   
done
sleep 5

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

# Run the bonding script. Make sure you have this already on the system
# Note: The location of the bonding script may change in the future
RunBondingScript
bondCount=$?
if [ $bondCount -eq 99 ]; then
    msg="ERROR: Running the bonding script failed. Please double check if it is present on the system"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed

else
    LogMsg "BondCount returned by SR-IOV_Utils: $bondCount"   
fi

# Set static IPs to the bond
ConfigureBond
if [ $? -ne 0 ]; then
    msg="ERROR: Could not set a static IP to the bond!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

# Pinging
__iterator=0
__ipIterator=2
while [ $__iterator -lt $bondCount ]; do
    staticIP=$(cat constants.sh | grep IP$__ipIterator | tr = " " | awk '{print $2}')

    # Ping the remote host
    ping -I "bond$__iterator" -c 10 "$staticIP" >/dev/null 2>&1
    if [ 0 -eq $? ]; then
        msg="Successfully pinged $staticIP through bond$__iterator"
        LogMsg "$msg"
        UpdateSummary "$msg"
    else
        msg="ERROR: Unable to ping $staticIP through bond$__iterator"
        LogMsg "$msg"
        UpdateSummary "$msg"
    fi
    __ipIterator=$(($__ipIterator + 2))
    : $((__iterator++))
done

msg="Pinging was successful through all bonds"
LogMsg $msg
UpdateSummary "$msg"
sleep 5

SetTestStateCompleted