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
    SetTestStateAborted
    exit 1
}

# Source constants file and initialize most common variables
UtilsInit

# Create the state.txt file so ICA knows we are running
SetTestStateRunning
# Set default service name
serviceName="hypervvssd"

if [[ $serviceAction == "start" ]] || [[ $serviceAction == "stop" ]]; then
    LogMsg "Info: service action is $serviceAction"
else
    LogMsg "Info: invalid service action $serviceAction"
    UpdateSummary "Info: invalid action $serviceAction, only support stop and start"
    SetTestStateAborted
    exit 1
fi

GetDistro
case $DISTRO in
    "redhat_7" | "centos_7" | "Fedora" | "redhat_8" | "centos_8")
        serviceName=`systemctl list-unit-files | grep -e 'hypervvssd\|[h]v-vss-daemon\|[h]v_vss_daemon'| cut -d " " -f 1`
    ;;
    "redhat_6" | "centos_6")
        serviceName=`chkconfig list | grep -e 'hypervvssd\|[h]v-vss-daemon\|[h]v_vss_daemon'| cut -d " " -f 1`
    ;;
    *)
        LogMsg "Info: Distro $DISTRO is not supported, skipping test."
        UpdateSummary "Distro $DISTRO is not supported, skipping test."
        SetTestStateSkipped
        exit 1
    ;;
    esac

service $serviceName $serviceAction
if [ $? -eq 0 ]; then
    LogMsg "Set VSS Daemon $serviceName as $serviceAction"
    SetTestStateCompleted
    exit 0
else
    loginfo="ERROR: Fail to set VSS Daemon $serviceName as $serviceAction"
    LogMsg "$loginfo"
    UpdateSummary "$loginfo"
    SetTestStateFailed
    exit 1
fi
