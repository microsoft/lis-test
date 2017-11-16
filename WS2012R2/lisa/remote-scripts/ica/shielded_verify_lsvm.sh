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
#   Basic Shielded Pre-TDC test that verifies if lsvmtools is installed
#
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
    dpkg -l | grep lsvmtools    
elif [ $os_PACKAGE == 'rpm' ]; then
    rpm -qa | grep lsvmtools
else
    msg="ERROR: Could not determine os_PACKAGE. Please check if utils.sh was successfully sourced"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
fi

if [ $? -eq 0 ]; then
    msg="lsvmtools is installed!"
    LogMsg "$msg"
    UpdateSummary "$msg"    
    LogMsg "Updating test case state to completed"
    SetTestStateCompleted
else
    msg="ERROR: lsvmtools is not installed"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi