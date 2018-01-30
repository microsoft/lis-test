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

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
	echo "Error: unable to source utils.sh!"
	echo "TestAborted" > state.txt
	exit 2
}

#######################################################################
# Check kernel version is newer than the specified version
# if return 0, the current kernel version is newer than specified version
# else, the current kernel version is older than specified version
#######################################################################
CheckVMFeatureSupportStatus()
{
    specifiedKernel=$1
    if [ $specifiedKernel == "" ];then
        return 1
    fi
    # for example 3.10.0-514.el7.x86_64
    # get kernel version array is (3 10 0 514)
    local kernel_array=(`uname -r | awk -F '[.-]' '{print $1,$2,$3,$4}'`)
    local specifiedKernel_array=(`echo $specifiedKernel | awk -F '[.-]' '{print $1,$2,$3,$4}'`)
    local index=${!kernel_array[@]}
    local n=0
    for n in $index
    do
        if [ ${kernel_array[$n]} -gt ${specifiedKernel_array[$n]} ];then
            return 0
        fi
    done

    return 1
}

#######################################################################
# Pre-settings & Functions
#######################################################################

UtilsInit

# Check kernel version
CheckVMFeatureSupportStatus "3.10.0-610"
if [ $? -ne 0 ]; then
    LogMsg "INFO: this kernel version does not support uio feature, skip test"
    UpdateSummary "INFO: this kernel version does not support uio feature, skip test"
    UpdateTestState $ICA_TESTSKIPPED
    exit 1
fi

# Check if the module is successfully loaded
# Param:
#  $1: module name
#  $2: 1 if the module is expected to be loadd,
#      0 if it is expected NOT loaded
CheckModule(){
    ret=$(lsmod |awk "\$1==\"$1\"" |wc -l)

    if [ $2 -eq 1 ]; then
        if [ $ret -eq 1 ]; then
            LogMsg "Success: $1 loaded"
        else
            LogMsg "Fail: module $1 is not loaded"
            UpdateSummary "Fail: module $1 is not loaded"
            SetTestStateFailed
            exit 1
        fi
    fi

    if [ $2 -eq 0 ]; then
        if [ $ret -eq 0 ]; then
            LogMsg "Success: $1 unloaded"
        else
            LogMsg "Fail: module $1 is not unloaded"
            UpdateSummary "Fail: module $1 is not unloaded"
            SetTestStateFailed
            exit 1
        fi
    fi
}

# Check return value. If return value is 0, log success; if not 0, log error and
# mark the test as failed.
# Param:
# $1: Operation description (Log info)
CheckSuccess(){
    if [ $? -eq 0 ]; then
        LogMsg "Success: $1"
    else
        LogMsg "Error: $1"
        UpdateSummary "Error: $1"
        SetTestStateFailed
        exit 1
    fi
}

#######################################################################
# Main test body
#######################################################################

# Part I: Test loading/unloading uio & uio_hv_generic
for i in $(seq 100)
do
    # Test loading uio
    modprobe uio
    CheckModule uio 1

    # Test unloading uio
    #  make sure uio generic is unloaded before unloading uio
    modprobe -r uio_hv_generic
    modprobe -r uio
    CheckModule uio 0

    # Test loading uio_hv_generic
    modprobe uio_hv_generic
    #  uio shold also be loaded when loading uio generic
    CheckModule uio 1
    CheckModule uio_hv_generic 1

    # Test unloading uio generic
    modprobe -r uio_hv_generic
    CheckModule uio_hv_generic 0

    # Test unloading uio
    modprobe -r uio
    CheckModule uio 0
done

# Part I pass
UpdateSummary "Success: loading/unloading uio and uio_hv_generic modules"

# Part II: Test reassign a device (network adapter) to uio_hv_generic driver

# Setup: load uio generic
modprobe uio_hv_generic
CheckSuccess "Load uio_hv_generic"

# Setup: Find the not connected network adapter, will use it to test uio
InactiveNIC=`ip address |awk '$9=="DOWN" { print substr($2, 1, length($2)-1) }'`
CheckSuccess "Get inactive nic info"

# Setup: acquire adapter class id
ClassID=`cat /sys/class/net/$InactiveNIC/device/class_id |awk '{ print( substr($1, 2, length($1)-2)) }'`
CheckSuccess "Get network adapter class id"

# Setup: acquire adapter device id
DeviceID=`cat /sys/class/net/$InactiveNIC/device/device_id |awk '{ print( substr($1, 2, length($1)-2)) }'`
CheckSuccess "Get network adapter device id"

# Setup: add new id to uio generic
echo $ClassID > /sys/bus/vmbus/drivers/uio_hv_generic/new_id
CheckSuccess "Add new id for uio_hv_generic"

# Setup: unbind device from netvsc
echo -n $DeviceID > /sys/bus/vmbus/drivers/hv_netvsc/unbind
CheckSuccess "Unbind device from hv_netvsc"

# Test binding device to uio generic
echo -n $DeviceID > /sys/bus/vmbus/drivers/uio_hv_generic/bind
CheckSuccess "Assigned device to uio_hv_generic"

# Check /dev/uio0 exists
if [ -e "/dev/uio0" ]; then
    LogMsg "Success: /dev/uio0 found"
else
    LogMsg "Fail: /dev/uio0 not found"
    UpdateSummary "Fail: /dev/uio0 not found"
    SetTestStateFailed
    exit 1
fi

# Test unbinding device from uio generic
echo -n $DeviceID > /sys/bus/vmbus/drivers/uio_hv_generic/unbind
CheckSuccess "Unbind device from uio_hv_generic"

# Part II pass
UpdateSummary "Success: uio_hv_generic: device assign/deassigned"

# Bind device back to netvsc.
# This is not part of the test, just to recover environment so that this
# script can be reruned. Nevertheless, If this part fails, it could be a
# potential issue.
echo -n $DeviceID > /sys/bus/vmbus/drivers/hv_netvsc/bind
CheckSuccess "Assign network adapter back to hv_netvsc"

SetTestStateCompleted
exit 0
