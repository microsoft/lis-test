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
# Check_clockevent.sh
#
# Description:
#	This script was created to check if the current_device is not null.
#
################################################################
dos2unix utils.sh
# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 1
}

# Source constants file and initialize most common variables
UtilsInit

#
# Check the file of current_device for clockevent
#
CheckClockEvent()
{
    current_clockevent="/sys/devices/system/clockevents/clockevent0/current_device"
    if ! [[ $(find $current_clockevent -type f -size +0M) ]]; then
        LogMsg "Test Failed. No file was found current_device greater than 0M."
        UpdateSummary "Test Failed. No file was found in current_device of size greater than 0M."
        SetTestStateFailed
        exit 1
    else
        __clockevent=$(cat $current_clockevent)
        if [[ "$__clockevent" == "Hyper-V clockevent" ]]; then
            LogMsg "Test successful. Proper file was found. Clockevent file content is $__clockevent"
            UpdateSummary "Clockevent file content is $__clockevent"
        else
            LogMsg "Test failed. Proper file was NOT found."
            UpdateSummary "Test failed. Proper file was NOT found."
            SetTestStateFailed
            exit 1
        fi
    fi

}

#
# MAIN SCRIPT
#
GetDistro
case $DISTRO in
    redhat_6)
        LogMsg "WARNING: $DISTRO does not support clockevent."
        UpdateSummary "WARNING: $DISTRO does not support clockevent."
        SetTestStateSkipped
        exit 1
        ;;
    redhat_7 | redhat_8)
        CheckClockEvent
        ;;
    fedora_* )
        CheckClockEvent
        ;;
    *)
        msg="WARNING: Distro '$DISTRO' not supported, defaulting to RedHat"
        LogMsg "${msg}"
        UpdateSummary "${msg}"
        CheckClockEvent
        ;;
esac
LogMsg "Test completed successfully"
UpdateSummary "Test passed: the current_clockevent is not null and value is right."
SetTestStateCompleted
exit 0
