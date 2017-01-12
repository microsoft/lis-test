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

# Set static IP to the bond
ConfigureBond
if [ $? -ne 0 ]; then
    msg="ERROR: Could not set a static IP to the bond!"
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


#
# Run file copy tests for each bond interface 
#
__iterator=0
__ipIterator1=1
__ipIterator2=2
while [ $__iterator -lt $bondCount ]; do
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
    if [ $txValue -lt 70000 ]; then
        msg="ERROR: TX packets insufficient"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 10
    fi

    rxValue=$(ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$BOND_IP2" ifconfig bond$__iterator | grep "RX packets" | sed 's/:/ /' | awk '{print $3}')
    LogMsg "RX Value: $rxValue"
    if [ $rxValue -lt 70000 ]; then
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