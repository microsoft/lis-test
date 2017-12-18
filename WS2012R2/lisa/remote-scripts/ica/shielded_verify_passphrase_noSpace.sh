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
#   Shielded Pre-TDC test that checks if lsvmprep fails if the passphrase
# is not 'passphrase' or fails if the boot partition is filled
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

# Change passphrase
if [ $change_passphrase == "yes" ]; then
	(echo 'passphrase';echo 'passphraseTest';echo 'passphraseTest') | cryptsetup luksChangeKey /dev/sda3	
fi

# Fill disk
if [ $fill_disk == "yes" ]; then
    dd if=/dev/zero of=/boot/filename bs=$((1024*1024)) count=$((10*1024))
    dd if=/dev/zero of=/boot/efi/filename bs=$((1024*1024)) count=$((10*1024))
fi

# Run lsvmprep. It is expected to fail
cd /opt/lsvm*
yes YES | ./lsvmprep
if [ $? -eq 0 ]; then
    msg="ERROR: lsvmprep was successfully runned!"
    LogMsg "$msg"
    UpdateSummary "$msg"
	SetTestStateFailed
else
    msg="lsvmprep failed as expected!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    LogMsg "Updating test case state to completed"
    SetTestStateCompleted
fi