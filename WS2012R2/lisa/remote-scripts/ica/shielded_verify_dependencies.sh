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
#   Basic Shielded Pre-TDC test that verifies if dependencies for 
# lsvmtools are installed
########################################################################

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Source constants file and initialize most common variables
UtilsInit

# Determine what package should be checked
GetOSVersion

if [ $os_PACKAGE == 'deb' ]; then
	declare -a dep=("cryptsetup " "cryptsetup-bin" "initramfs-tools " "initramfs-tools-bin" "initramfs-tools-core" "dmeventd" "dmsetup")
elif [ $os_PACKAGE == 'rpm' ]; then
	declare -a dep=("cryptsetup-" "dracut" "device-mapper")
else
    msg="ERROR: Could not determine os_PACKAGE. Please check if utils.sh was successfully sourced"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
fi

for package in "${dep[@]}"
do
    msg="Checking $package"
    LogMsg "$msg"

    if [ $os_PACKAGE == 'deb' ]; then
        dpkg -l | grep $package
    elif [ $os_PACKAGE == 'rpm' ]; then
        rpm -qa | grep $package    
    fi
   
    if [ $? -ne 0 ]; then
        msg="ERROR: $package is not installed"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi
done

if [ $? -eq 0 ]; then
    msg="All dependency packages are installed"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateCompleted
fi