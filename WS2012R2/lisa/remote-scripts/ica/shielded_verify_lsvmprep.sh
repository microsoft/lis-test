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
#   Basic Shielded Pre-TDC test that checks lsvmprep for any errors
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

# Restore VM to initial setup
./restore*

# Run lsvmprep
cd /opt/lsvm*
yes YES | ./lsvmprep
if [ $? -eq 0 ]; then
    msg="lsvmprep was successfully runned!"
    LogMsg "$msg"
    UpdateSummary "$msg"	
	LogMsg "Updating test case state to completed"
	SetTestStateCompleted
else
    msg="ERROR: lsvmprep failed!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi