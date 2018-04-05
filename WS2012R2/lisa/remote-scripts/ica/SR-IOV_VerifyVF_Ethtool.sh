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
#########################################################################
# Description:
#   SR-IOV_VerifyVF_Ethtool.sh check if VF is loaded and traffic is registered
#	on ethtool parameters.
#
#   Steps:
#   1. Verify/install pciutils package, Ethtool
#   2. Using the lspci command, examine the NIC with SR-IOV support
#   3. Configure VM
#   4. Check network capability
#   5. Send a 1GB file from VM1 to VM2 and check results with ethtool
#
########################################################################

ICA_TESTRUNNING="TestRunning"
ICA_TESTSKIPPED="TestSkipped"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTFAILED="TestFailed"
ICA_TESTABORTED="TestAborted"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}
}

UpdateSummary()
{
    echo $1 >> ~/summary.log
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

LogMsgVFStatus()
{	
	#test VM
	ethtool -S "eth$__iterator" | grep vf
	#remote VM
	remote=$(ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$VF_IP2" ethtool -S "eth$__iterator" | grep vf)
	LogMsg "$remote"
}

#######################################################################
#
# Main script body
#
#######################################################################

#For 1GB file the minimum traffic is 1024MB
MBytes=1024

#Value of packtes that can be exist before file transfer
minPackets=10000

#Create the state.txt file so ICA knows we are running
UpdateTestState $ICA_TESTRUNNING

#Convert eol
dos2unix SR-IOV_Utils.sh

#Source SR-IOV_Utils.sh. This is the script that contains all the 
#SR-IOV basic functions (checking drivers, checking VFs, assigning IPs)
. SR-IOV_Utils.sh || {
    echo "ERROR: unable to source SR-IOV_Utils.sh!"
    UpdateTestState $ICA_TESTABORTED
    exit 2
}

#Check the parameters in constants.sh
Check_SRIOV_Parameters
if [ $? -ne 0 ]; then
    msg="ERROR: The necessary parameters are not present in constants.sh. Please check the xml test file."
    LogMsg "$msg"
    UpdateSummary "$msg"
    UpdateTestState $ICA_TESTFAILED
fi

#Check if the SR-IOV driver is in use
VerifyVF
if [ $? -ne 0 ]; then
    msg="ERROR: VF is not loaded! Make sure you are using compatible hardware."
    LogMsg "$msg"
    UpdateSummary "$msg"
    UpdateTestState $ICA_TESTFAILED
fi
UpdateSummary "VF is present on VM!"

#Set static IP to the VF
ConfigureVF
if [ $? -ne 0 ]; then
    msg="ERROR: Could not set a static IP to the VF!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    UpdateTestState $ICA_TESTFAILED
fi

#Check if ethtool exist and install it if not
VerifyIsEthtool

#
# Ping from VM1 to VM2
#
vfCount=$(find /sys/devices -name net -a -ipath '*vmbus*' | grep pci | wc -l)
if [ $vfCount -gt 0 ]; then
	__iterator=1

	#Check if Statistics from ethtool are available
	sts=$(ethtool -S "eth$__iterator" 2>&1)
	if [[ $sts = *"no stats available"* ]]; then
		LogMsg "$sts"
		LogMsg "Operation not supported. Test Skipped."
		UpdateSummary "Operation not supported. Test Skipped."
		UpdateTestState $ICA_TESTSKIPPED
		exit 2
	fi

	#Check if VF parameters from ethtool are available
	ethtool -S "eth$__iterator" | grep vf > /dev/null
	if [ $? -ne 0 ]; then
		LogMsg "VF params not exists. Test Skipped."
		UpdateSummary "VF params not exists. Test Skipped."
		UpdateTestState $ICA_TESTSKIPPED
		exit 2
	fi
	
	# Create an 1gb file to be sent from VM1 to VM2
	Create1Gfile
	if [ $? -ne 0 ]; then
		msg="ERROR: Could not create the 1gb file on VM1!"
		LogMsg "$msg"
		UpdateSummary "$msg"
		UpdateTestState $ICA_TESTFAILED
	fi
	
	#LogMsg values of tx and rx before ping
	LogMsgVFStatus
	
    # Ping the remote host
    ping -I "eth$__iterator" -c 10 "$VF_IP2" >/dev/null 2>&1
    if [ 0 -eq $? ]; then
        msg="Successfully pinged $VF_IP2 through eth$__iterator."
        LogMsg "$msg"
        UpdateSummary "$msg"
    else
        msg="ERROR: Unable to ping $VF_IP2 through eth$__iterator."
        LogMsg "$msg"
        UpdateSummary "$msg"
    fi

	##LogMsg values of tx and rx after ping
	LogMsgVFStatus
    
    # Send 1GB file from VM1 to VM2 via eth1
    #
    scp -i "$HOME"/.ssh/"$sshKey" -o BindAddress=$VF_IP1 -o StrictHostKeyChecking=no "$output_file" "$REMOTE_USER"@"$VF_IP2":/tmp/"$output_file"
    if [ 0 -ne $? ]; then
        msg="ERROR: Unable to send the file from VM1 to VM2 using eth$__iterator."
        LogMsg "$msg"
        UpdateSummary "$msg"
        UpdateTestState $ICA_TESTFAILED
        exit 10
    else
        msg="Successfully sent $output_file to $VF_IP2."
        LogMsg "$msg"
    fi

	#LogMsg values of tx and rx after send file
	LogMsgVFStatus
	
    # Verify both eth1 on VM1 and VM2 to see if file was sent between them
	txPackets=$(ethtool -S "eth$__iterator" | grep vf | grep "vf_tx_packets" | sed 's/:/ /' | awk '{print $2}')
	txBytes=$(ethtool -S "eth$__iterator" | grep vf | grep "vf_tx_bytes" | sed 's/:/ /' | awk '{print $2}')
	txMB=$(echo $txBytes | awk '{ byte =$1 /1024/1024; print byte}')
    LogMsg "TX MB after sending the file: $txMB MB."
	LogMsg "TX Packtes after sending the file: $txPackets."
    if [ ${txMB%.*} -lt $MBytes ] || [ $txPackets -lt $minPackets ]; then
        msg="ERROR: TX MBs or TX Packets are insufficient."
        LogMsg "$msg"
        UpdateSummary "$msg"
        UpdateTestState $ICA_TESTFAILED
        exit 10
    fi

    rxPackets=$(ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$VF_IP2" ethtool -S "eth$__iterator" | grep vf | grep "vf_rx_packets" | sed 's/:/ /' | awk '{print $2}')
    rxBytes=$(ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$VF_IP2" ethtool -S "eth$__iterator" | grep vf | grep "vf_rx_bytes" | sed 's/:/ /' | awk '{print $2}')
	rxMB=$(echo $rxBytes | awk '{ byte =$1 /1024/1024; print byte}')
	LogMsg "RX MB after sending the file: $rxMB MB."
	LogMsg "RX Packets after sending the file : $rxPackets."
    if [ ${rxMB%.*} -lt $MBytes ] || [ $rxPackets -lt $minPackets ]; then
        msg="ERROR: RX MBs or RX Packets are insufficient."
        LogMsg "$msg"
        UpdateSummary "$msg"
        UpdateTestState $ICA_TESTFAILED
        exit 10
    fi

    msg="Successfully sent file from VM1 to VM2 through eth1."
    LogMsg "$msg"
    UpdateSummary "$msg"
	UpdateTestState $ICA_TESTCOMPLETED
	exit 0
else
	msg="No VF found.Test failed."
    LogMsg "$msg"
    UpdateSummary "$msg"
	UpdateTestState $ICA_TESTFAILED
	exit 1
fi