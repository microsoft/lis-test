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
#   Use Omping (yum install omping -y)
#   On the 2nd VM: omping $BOND_IP1 $BOND_IP2 -m 239.255.254.24 -c 11 > out.client &
#   On the TEST VM: omping $BOND_IP1 $BOND_IP2 -m 239.255.254.24 -c 11 > out.client
#   Check results:
#   On the TEST VM: cat out.client | grep multicast | grep /0%
#   On the 2nd VM: cat out.client | grep multicast | grep /0%
#   If both have 0% packet loss, test passed
################################################################################

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

# Install dependencies needed for testing
if [ is_ubuntu ]; then
    tar -xzf omping-0.0.4.tar.gz
    if [ $? -ne 0 ]; then
        msg="ERROR: Failed to decompress omping archive"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        return 1
    fi

    cd omping-0.0.4/
    make
    make install
    if [ $? -ne 0 ]; then
        msg="ERROR: Failed to install omping"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        return 1
    fi
    cd ~

    # Install on dependency VM
    scp -i "$HOME"/.ssh/"$sshKey" -o BindAddress=$BOND_IP1 -o StrictHostKeyChecking=no omping-0.0.4.tar.gz "$REMOTE_USER"@"$BOND_IP2":/tmp/omping-0.0.4.tar.gz
    if [ $? -ne 0 ]; then
        msg="ERROR: Failed to send omping archive to VM2"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        return 1
    fi

    ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$BOND_IP2" "tar -xzf /tmp/omping-0.0.4.tar.gz && cd ~/omping-0.0.4/ && make && make install"
    if [ $? -ne 0 ]; then
        msg="ERROR: Failed to install omping on VM2 via ssh"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        return 1
    fi
else
    InstallDependencies
    if [ $? -ne 0 ]; then
        msg="ERROR: Could not install dependencies!"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi    
fi
LogMsg "INFO: All configuration completed successfully. Will proceed with the testing"

# Multicast testing
ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$BOND_IP2" "omping $BOND_IP1 $BOND_IP2 -m 239.255.254.24 -c 11 > out.client &"
if [ $? -ne 0 ]; then
    msg="ERROR: Could not start omping on VM2 (BOND_IP: ${BOND_IP2})"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

omping $BOND_IP1 $BOND_IP2 -m 239.255.254.24 -c 11 > out.client
if [ $? -ne 0 ]; then
    msg="ERROR: Could not start omping on VM1 (BOND_IP: ${BOND_IP1})"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

LogMsg "INFO: Omping was started on both VMs. Results will be checked in a few seconds"
sleep 5
 
# Check results - Summary must show a 0% loss of packets
multicastSummary=$(cat out.client | grep multicast | grep /0%)
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

ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$BOND_IP2" "cat out.client | grep multicast | grep /0%"
if [ $? -ne 0 ]; then
    msg="ERROR: VM2 shows that packets were lost!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

msg="Multicast packets were successfully sent, 0% loss"
LogMsg $msg
UpdateSummary "$msg"
SetTestStateCompleted