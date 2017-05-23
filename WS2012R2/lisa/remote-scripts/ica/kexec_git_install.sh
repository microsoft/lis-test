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
# This script is used to install kexec-tools from git on Upstream jobs
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

# Clone kexec-tools from git
git clone git://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git
if [ $? -ne 0 ]; then
    msg="ERROR: Failed to clone kexec"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

cd kexec-tools

# Start configuring and installing kexec-tools
# Run bootstrap script
./bootstrap
if [ $? -ne 0 ]; then
    msg="ERROR: Failed to run bootstrap script"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

# Run configure script. Prefix is different for Ubuntu and RHEL/CentOS/SLES
if is_ubuntu ; then
	./configure --prefix=/	
else
	./configure --prefix=/usr
fi
if [ $? -ne 0 ]; then
    msg="ERROR: Failed to run configure script"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

make && make install
if [ $? -ne 0 ]; then
    msg="ERROR: Failed to install kdump"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

if is_suse ; then
	chkconfig kdump on
fi

# Do some cleanup
cd ~
rm -rf kexec*

msg="Kdump was successfully installed"
LogMsg "$msg"
UpdateSummary "$msg"
SetTestStateCompleted
exit 0