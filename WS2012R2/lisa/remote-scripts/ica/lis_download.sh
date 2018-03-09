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
#     This script was created to automate the download of 2 LIS
#     packages
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

function download_lis {
    # Download file
    package_name=$(basename $1)
    wget "$1$2" -O "$package_name"
    if [ $? -ne 0 ]; then
        msg="ERROR: LIS download failed"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    fi

    # Extract archive
    tar -xzvf $package_name
        if [ $? -ne 0 ]; then
        msg="ERROR: Extracting the archive failed"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    fi

    # Move folder. After the function is called twice we should
    # have in root folder OLD_LISISO and NEW_LISISO folders
    # OLD_LISISO will have a previous version of LIS
    # NEW_LISISO will have the latest LIS
    mv LISISO "$3_LISISO"
}

function main {
    # Install wget
    yum install wget -y

    download_lis "$LIS_URL" "$AZURE_TOKEN" "NEW"
    download_lis "$LIS_URL_PREVIOUS" "$AZURE_TOKEN" "OLD"

    msg="LIS packages were successfully downloaded"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateCompleted
}

main $@