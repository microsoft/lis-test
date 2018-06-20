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
# Core_Time_Clocksource.sh
#
# Description:
#	This script was created to check and unbind the current clocksource.
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
# Check the file of current_clocksource
#
CheckSource()
{
    current_clocksource="/sys/devices/system/clocksource/clocksource0/current_clocksource"
    clocksource="hyperv_clocksource_tsc_page"
    if ! [[ $(find $current_clocksource -type f -size +0M) ]]; then
        LogMsg "Test Failed. No file was found current_clocksource greater than 0M."
        UpdateSummary "Test Failed. No file was found in clocksource of size greater than 0M."
        SetTestStateFailed
        exit 1
    else
        __file_content=$(cat $current_clocksource)
        if [[ $__file_content == "$clocksource" ]]; then
            LogMsg "Test successful. Proper file was found. Clocksource file content is $__file_content"
            UpdateSummary "Clocksource file content is $__file_content"
        else
            LogMsg "Test failed. Proper file was NOT found."
            UpdateSummary "Test failed. Proper file was NOT found."
            SetTestStateFailed
            exit 1
        fi
    fi

    # check cpu with constant_tsc
    if [[ $(grep constant_tsc /proc/cpuinfo) ]];then
        LogMsg "Test successful. /proc/cpuinfo contains flag constant_tsc"
    else
        LogMsg "Test failed. /proc/cpuinfo does not contain flag constant_tsc"
        UpdateSummary "Test failed. /proc/cpuinfo does not contain flag constant_tsc"
        SetTestStateFailed
        exit 1
    fi

    # check dmesg with hyperv_clocksource
    __dmesg_output=$(dmesg | grep "clocksource $clocksource")
    if [[ $? -eq 0 ]];then
        LogMsg "Test successful. dmesg contains log - clocksource $__dmesg_output"
        UpdateSummary "Test successful. dmesg contains the following log: $__dmesg_output"
    else
        LogMsg "Test failed. dmesg does not contain log - clocksource $__dmesg_output"
        UpdateSummary "Test failed. dmesg does not contain log - clocksource $__dmesg_output"
        SetTestStateFailed
        exit 1
    fi
}
function UnbindCurrentSource()
{
    unbind_file="/sys/devices/system/clocksource/clocksource0/unbind_clocksource"
    clocksource="hyperv_clocksource_tsc_page"
    echo $clocksource > $unbind_file
    if [[ $? -eq 0 ]];then
        _clocksource=$(cat /sys/devices/system/clocksource/clocksource0/current_clocksource)
        dmesg | grep "Switched to clocksource acpi_pm"
        if [ $? -eq 0 ] && [ $_clocksource == "acpi_pm" ]; then
            LogMsg "Test successful. After unbind, current clocksource is $_clocksource"
            UpdateSummary "Test successful. After unbind, current clocksource is $_clocksource"
        else
            LogMsg "Test failed. After unbind, current clocksource is $_clocksource"
            UpdateSummary "Test failed. After unbind, current clocksource is $_clocksource"
            SetTestStateFailed
            exit 1
        fi
    else
        LogMsg "Test failed. Can not unbind $clocksource"
        UpdateSummary "Test failed. Can not unbind $clocksource"
        SetTestStateFailed
        exit 1
    fi
}
#
# MAIN SCRIPT
#
GetDistro
case $DISTRO in
    redhat_6 | centos_6)
        LogMsg "WARNING: $DISTRO does not support unbind current clocksource, only check"
        UpdateSummary "WARNING: $DISTRO does not support unbind current clocksource, only check"
        CheckSource
        ;;
    redhat_7|redhat_8|centos_7|centos_8|fedora*)
        CheckSource
        UnbindCurrentSource
        ;;
    ubuntu* )
        CheckSource
        UnbindCurrentSource
        ;;
    *)
        msg="ERROR: Distro '$DISTRO' not supported"
        LogMsg "${msg}"
        UpdateSummary "${msg}"
        SetTestStateFailed
        exit 1
        ;;
esac

LogMsg "Test completed successfully."
UpdateSummary "Test passed."
SetTestStateCompleted
exit 0
