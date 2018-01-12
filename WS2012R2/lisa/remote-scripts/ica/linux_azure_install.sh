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

########################################################################
#
# Description:
#
# This script is used to install linux-azure kernel
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

# Add proposed repo is sources.list
echo "deb http://archive.ubuntu.com/ubuntu/ xenial-proposed restricted main multiverse universe" >> /etc/apt/sources.list
if [ $? -ne 0 ]; then
    msg="ERROR: Failed to enable proposed in sources.list"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

# Update apt
apt-get update -y
if [ $? -ne 0 ]; then
    msg="ERROR: Failed to update apt"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

# Install linux-azure package
apt-get install -y linux-azure
if [ $? -ne 0 ]; then
    msg="ERROR: Failed to install linux-azure"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

msg="Linux Azure was succesfully installed"
LogMsg "$msg"
UpdateSummary "$msg"

# Install latest kexec-tools
apt-get install -y kexec-tools

SetTestStateCompleted
exit 0
