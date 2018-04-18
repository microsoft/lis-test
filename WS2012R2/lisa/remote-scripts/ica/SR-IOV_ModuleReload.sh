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
#   Unload/load modules using modprobe, verify SR-IOV Failover is working
#
#   Steps:
#   1. Verify/install pciutils package
#   2. Using the lspci command, examine the NIC with SR-IOV support
#   3. Configure VF
#   4. Check network capability
#   5. Unload module(s) (ixgbevf for Intel or mlx4_core and mlx_en for Mellanox)
#   6. Check network capability
#   7. Load module(s) (ixgbevf for Intel or mlx4_core and mlx_en for Mellanox)
#   8. Check network capability
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

# Ping Dependency VM
ping -I eth1 -c 10 "$VF_IP2" >/dev/null 2>&1
if [ 0 -eq $? ]; then
    msg="Successfully pinged $VF_IP2 through eth1 with before unloading the VF module"
    LogMsg "$msg"
    UpdateSummary "$msg"
else
    msg="ERROR: Unable to ping $VF_IP2 through eth1 with VF up. Further testing will be stopped"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

# Extract VF name
interface=$(ls /sys/class/net/ | grep -v 'eth0\|eth1\|lo')

# Shut down interface
LogMsg "Unloading the module(s)"
lsmod | grep ixgbevf
if [ $? -eq 0 ]; then
    modprobe -r ixgbevf
    moduleName='ixgbevf'
fi

lsmod | grep mlx4_en
if [ $? -eq 0 ]; then
    modprobe -r mlx4_en
    moduleName="mlx4"
fi

lsmod | grep mlx4_core
if [ $? -eq 0 ]; then
    modprobe -r mlx4_core
    moduleName="mlx4"
fi

ifconfig $interface
if [ 0 -eq $? ]; then
    msg="ERROR: VF is still up after unloading the VF module"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

# Ping the remote host after bringing down the VF
ping -I "eth1" -c 10 "$VF_IP2" >/dev/null 2>&1
if [ 0 -eq $? ]; then
    msg="Successfully pinged $VF_IP2 through eth1 after unloading VF module"
    LogMsg "$msg"
    UpdateSummary "$msg"
else
    msg="ERROR: Unable to ping $VF_IP2 through eth1 after unloading VF module"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

# Get TX value before sending the file
txValueBefore=$(ifconfig eth1 | grep "TX packets" | sed 's/:/ /' | awk '{print $3}') 
LogMsg "TX value before sending file: $txValueBefore"

# Send the file
scp -i "$HOME"/.ssh/"$sshKey" -o BindAddress=$VF_IP1 -o StrictHostKeyChecking=no "$output_file" "$REMOTE_USER"@"$VF_IP2":/tmp/"$output_file"
if [ 0 -ne $? ]; then
    msg="ERROR: Unable to send the file from VM1 to VM2 using eth1"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
else
    msg="Successfully sent $output_file to $VF_IP2"
    LogMsg "$msg"
fi

# Get TX value after sending the file
txValueAfter=$(ifconfig eth1 | grep "TX packets" | sed 's/:/ /' | awk '{print $3}') 
LogMsg "TX value after sending the file: $txValueAfter"

# Compare the values to see if TX increased as expected
txValueBefore=$(($txValueBefore + 50))      

if [ $txValueAfter -lt $txValueBefore ]; then
    msg="ERROR: TX packets insufficient"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi            

msg="Successfully sent file from VM1 to VM2 through eth1 after unloading VF modules"
LogMsg "$msg"
UpdateSummary "$msg"

# Load modules again
LogMsg "Loading the module(s)"
if [ $moduleName == "ixgbevf" ]; then
    modprobe ixgbevf
    if [ $? -ne 0 ]; then
        msg="ERROR: failed to load ixgbevf"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi
elif [ $moduleName == "mlx4" ]; then
    modprobe mlx4_core
    if [ $? -ne 0 ]; then
        msg="ERROR: failed to load mlx4_core"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi

    modprobe mlx4_en
    if [ $? -ne 0 ]; then
        msg="ERROR: failed to load mlx_en"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi     
fi

# Verify if VF is up
sleep 5
# Extract VF name
interface=$(ls /sys/class/net/ | grep -v 'eth0\|eth1\|lo')
ifconfig $interface
if [ 0 -ne $? ]; then
    msg="ERROR: VF has not restarted from ifconfig after the module was loaded"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

# Check for Call traces
CheckCallTracesWithDelay 120

# Ping the remote host after bringing down the VF
ping -I "eth1" -c 10 "$VF_IP2" >/dev/null 2>&1
if [ 0 -eq $? ]; then
    msg="Successfully pinged $VF_IP2 through eth1 after VF module was loaded"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateCompleted
else
    msg="ERROR: Unable to ping $VF_IP2 through eth1 after VF module was loaded"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi