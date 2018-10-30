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
#
#   Steps:
#   1. Verify/install pciutils package
#   2. Using the lspci command, examine the NIC with SR-IOV support
#   3. Configure VM
#   4. Check network capability
#   5. Send a 1GB file from VM1 to VM2
#
########################################################################
# Convert eol
dos2unix SR-IOV_Utils.sh
. constants.sh
if [ $MAX_NICS == "yes" ]; then
    # Adding IPs for all VFs (VM1 and VM2) in constants.sh
    sed --in-place '/IP/d' constants.sh

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
fi

# Source SR-IOV_Utils.sh. This is the script that contains all the 
# SR-IOV basic functions (checking drivers, checking VFs, assigning IPs)
. SR-IOV_Utils.sh || {
    echo "ERROR: unable to source SR-IOV_Utils.sh!"
    echo "TestAborted" > state.txt
    exit 1
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
    msg="ERROR: Could not set a static IP to the VF!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

# Create an 1gb file to be sent from VM1 to VM2
Create1Gfile
if [ $? -ne 0 ]; then
    msg="ERROR: Could not create the 1gb file on VM1!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

# Check if the VF count inside the VM is the same as the expected count
expected_vf_count=$(grep -c VF_IP constants.sh)
expected_vf_count=$(($expected_vf_count / 2))
vf_count=$(find /sys/devices -name net -a -ipath '*vmbus*' | grep -c pci)
if [ $vf_count -ne $expected_vf_count ]; then
    msg="ERROR: Expected VF count: $expected_vf_count. Actual VF count: $vf_count"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi
UpdateSummary "Expected VF count: $expected_vf_count. Actual VF count: $vf_count"
sleep 5
ip a

__iterator=1
__ip_iterator_1=1
__ip_iterator_2=2
# Ping and send file from VM1 to VM2
while [ $__iterator -le $vf_count ]; do
    # Extract VF_IP values
    ip_variable_name="VF_IP$__ip_iterator_1"
    static_IP_1="${!ip_variable_name}"
    ip_variable_name="VF_IP$__ip_iterator_2"
    static_IP_2="${!ip_variable_name}"

    synthetic_interface_vm_1=$(ip addr | grep $static_IP_1 | awk '{print $NF}')
    LogMsg  "Synthetic interface found: $synthetic_interface_vm_1"
    vf_interface_vm_1=$(find /sys/devices/* -name "*${synthetic_interface_vm_1}*" | grep "pci" | sed 's/\// /g' | awk '{print $12}')
    LogMsg "Virtual function found: $vf_interface_vm_1"

    # Ping the remote host
    ping -c 11 "$static_IP_2" >/dev/null 2>&1
    if [ 0 -eq $? ]; then
        LogMsg "Successfully pinged $static_IP_2 through $synthetic_interface_vm_1"
    else
        msg="ERROR: Unable to ping $static_IP_2 through $synthetic_interface_vm_1"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    fi

    # Send 1GB file from VM1 to VM2 via eth1
    scp -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$output_file" "$REMOTE_USER"@"$static_IP_2":/tmp/"$output_file"
    if [ 0 -ne $? ]; then
        msg="ERROR: Unable to send the file from VM1 to VM2 ($static_IP_2)"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    else
        LogMsg "Successfully sent $output_file to $static_IP_2"
    fi

    tx_value=$(cat /sys/class/net/${vf_interface_vm_1}/statistics/tx_packets)
    LogMsg "TX value after sending the file: $tx_value"
    if [ $tx_value -lt 400000 ]; then
        msg="ERROR: Insufficient TX packets sent"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    fi

    # Get the VF name from VM2
    cmd_to_send="ip addr | grep \"$static_IP_2\" | awk '{print \$NF}'"
    synthetic_interface_vm_2=$(ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$static_IP_2" $cmd_to_send)
    cmd_to_send="find /sys/devices/* -name "*${synthetic_interface_vm_2}*" | grep pci | sed 's/\// /g' | awk '{print \$12}'"
    vf_interface_vm_2=$(ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$static_IP_2" $cmd_to_send)
    
    rx_value=$(ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$static_IP_2" cat /sys/class/net/${vf_interface_vm_2}/statistics/rx_packets)
    LogMsg "RX value after sending the file: $rx_value"
    if [ $rx_value -lt 400000 ]; then
        msg="ERROR: Insufficient RX packets received"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    fi
    UpdateSummary "Successfully sent file from VM1 to VM2 through $synthetic_interface_vm_1"

    __ip_iterator_1=$(($__ip_iterator_1 + 2))
    __ip_iterator_2=$(($__ip_iterator_2 + 2))
    : $((__iterator++))
done

UpdateSummary "Successfully pinged and sent files through $vf_count VFs"
SetTestStateCompleted
exit 0