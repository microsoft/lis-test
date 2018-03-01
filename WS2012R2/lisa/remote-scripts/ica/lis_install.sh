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

#######################################################################
#
# Description:
#     This script was created to automate the download and instalation
#     of LIS drivers
#	1. Download LIS
#	2. Install LIS
#
#######################################################################

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

function download_archive {
	# Check URL
	wget -q --spider "$LIS_URL$AZURE_TOKEN"
	if [ $? -ne 0 ]; then
	    msg="ERROR: Archive URL is not valid"
	    LogMsg "$msg"
	    UpdateSummary "$msg"
	    SetTestStateFailed
	    exit 1
	fi

	# Download file
	wget "$LIS_URL$AZURE_TOKEN"
    if [ $? -ne 0 ]; then
        msg="ERROR: Archive download failed"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    fi

    msg="Archive was successfully downloaded"
    LogMsg "$msg"
    UpdateSummary "$msg"
}

function install_lis {
	# Extract archive
	tar -xzvf lis-rpm*.tar.gz
    if [ $? -ne 0 ]; then
        msg="ERROR: Extracting the archive failed"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    fi
    
    # Install LIS
    pushd ./LISISO
    bash install.sh 2>&1 | tee ~/LIS_install_complete.log
	if [ $? -ne 0 ]; then
	    msg="Unable to install LIS"
	    LogMsg "$msg"
	    UpdateSummary "$msg"
	    UpdateTestState "TestFailed"
	    exit 1
	fi
	sleep 5
	popd

	# Search for install issues
	cat ~/LIS_install_complete.log | grep -i "warning\|error\|aborting"
	if [ $? -eq 0 ]; then
		msg="Warning: Warning\error\abort detected while installing LIS"
	    LogMsg "$msg"
	    UpdateSummary "$msg"
	    UpdateTestState "TestFailed"
	    exit 1
	fi
}

function main {
	download_archive

	install_lis

    msg="LIS was successfully installed"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateCompleted
}

main $@