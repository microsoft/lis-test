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
#   Basic SR-IOV test that checks if VF has loaded. 
#   Also checks the bonding script & network capability for the VF
#
#   Steps:
#   1. Verify/install pciutils package
#   2. Using the lspci command, examine the NIC with SR-IOV support
#   3. Run bondvf.sh
#   4. Check network capability
#   5. Send a 1GB file from VM1 to VM2
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
# Ping from VM1 to VM2
#
__iterator=0
# Set static IPs for each bond created
while [ $__iterator -lt $bondCount ]; do
    # Ping the remote host
    ping -I "bond$__iterator" -c 10 "$BOND_IP2" >/dev/null 2>&1
    if [ 0 -eq $? ]; then
        msg="Successfully pinged $BOND_IP2 through bond$__iterator"
        LogMsg "$msg"
        UpdateSummary "$msg"
    else
        msg="ERROR: Unable to ping $BOND_IP2 through bond$__iterator"
        LogMsg "$msg"
        UpdateSummary "$msg"
    fi

    #
    # Send 1GB file from VM1 to VM2 via bond0
    #
    scp -i "$HOME"/.ssh/"$sshKey" -o BindAddress=$BOND_IP1 -o StrictHostKeyChecking=no "$output_file" "$REMOTE_USER"@"$BOND_IP2":/tmp/"$output_file"
    if [ 0 -ne $? ]; then
        msg="ERROR: Unable to send the file from VM1 to VM2 using bond$__iterator"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 10
    else
        msg="Successfully sent $output_file to $BOND_IP2"
        LogMsg "$msg"
    fi

    # Verify both bond0 on VM1 and VM2 to see if file was sent between them
	ifconfig bond$__iterator | grep bytes

    txValue=$(ifconfig bond$__iterator | grep "TX packets" | sed 's/:/ /' | awk '{print $3}')
    LogMsg "TX value after sending the file: $txValue"
    if [ $txValue -lt 700000 ]; then
        msg="ERROR: TX packets insufficient"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 10
    fi

    rxValue=$(ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$BOND_IP2" ifconfig bond$__iterator | grep "RX packets" | sed 's/:/ /' | awk '{print $3}')
    LogMsg "RX value after sending the file: $rxValue"
    if [ $rxValue -lt 700000 ]; then
        msg="ERROR: RX packets insufficient"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 10
    fi

    msg="Successfully sent file from VM1 to VM2 through bond0"
    LogMsg "$msg"
    UpdateSummary "$msg"

    : $((__iterator++))
done

LogMsg "Updating test case state to completed"
SetTestStateCompleted
exit 0