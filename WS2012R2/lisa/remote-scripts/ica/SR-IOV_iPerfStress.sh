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
#   This SR-IOV test will run iPerf3 for 30 minutes and checks
# if network connectivity is lost at any point
#
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

# Set static IP to the bond
ConfigureBond
if [ $? -ne 0 ]; then
    msg="ERROR: Could not set a static IP to the bond!"
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

# iPerf3 Stress test
ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$BOND_IP2" "kill $(ps aux | grep iperf | head -1 | awk '{print $2}')"
ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$BOND_IP2" 'iperf3 -s > perfResults.log &'
if [ $? -ne 0 ]; then
    msg="ERROR: Could not start iPerf3 on VM2 (BOND_IP: ${BOND_IP2})"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

iperf3 -t 1800 -c ${BOND_IP2} --logfile PerfResults.log &
if [ $? -ne 0 ]; then
    msg="ERROR: Could not start iPerf3 on VM1 (BOND_IP: ${BOND_IP1})"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
else
    LogMsg "INFO: iPerf3 was started on both VM. Please wait for stress test to finish"
    sleep 1860
fi

cat perfResults.log | grep error 
if [ $? -eq 0 ]; then
    msg="ERROR: iPerf3 didn't run!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

sleep 10
bandwidth=$(cat perfResults.log | grep sender | awk '{print $7}')
LogMsg "The bandwidh reported by iPerf was ${bandwidth}"
UpdateSummary "The bandwidh reported by iPerf was ${bandwidth} gbps"

# Check the connection again
LogMsg "Last step: Ping again from VM1 to VM2 to make sure the connection is still up"

ping -I bond0 -c 5 ${BOND_IP2} > pingResults.log
if [ $? -ne 0 ]; then
    msg="ERROR: Could not ping from VM1 to VM2 after iPerf3 finished the run!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

sleep 5
cat pingResults.log | grep " 0%"
if [ $? -ne 0 ]; then
    msg="ERROR: Ping shows that packets were lost between VM1 and VM2"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed  
else
    sleep 3
    msg="Ping was succesful between VM1 and VM2 after iPerf finished the run"
    LogMsg $msg
    UpdateSummary "$msg"
    sleep 5
    SetTestStateCompleted   
fi