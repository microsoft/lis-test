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
# Check_clocksource.sh
#
# Description:
#	This script was created to check if the current_clocksource is not null.
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
# For rhel6.9+ and rhel7.3+, default clocksource is hyperv_clocksource_tsc_page
#
CheckSource()
{
    clocksource="hyperv_clocksource_tsc_page"
    current_clocksource="/sys/devices/system/clocksource/clocksource0/current_clocksource"
    if ! [[ $(find $current_clocksource -type f -size +0M) ]]; then
        LogMsg "Test Failed. No file was found current_clocksource greater than 0M."
        echo "Test Failed. No file was found in clocksource of size greater than 0M." >> ~/summary.log
        SetTestStateFailed
        exit 1
    else
        __file_name=$(cat $current_clocksource)
        if [[ "$__file_name" == "$clocksource" ]]; then
            LogMsg "Test successful. Proper file was found."
        else
            LogMsg "Test failed. Proper file was NOT found."
            echo "Test failed. Proper file was NOT found." >> ~/summary.log
            SetTestStateFailed
            exit 1
        fi
    fi

    # check cpu with constant_tsc
    if [[ $(grep constant_tsc /proc/cpuinfo) ]];then
        LogMsg "Test successful. /proc/cpuinfo contains flag constant_tsc"
    else
        LogMsg "Test failed. /proc/cpuinfo does not contain flag constant_tsc"
        echo "Test failed. /proc/cpuinfo does not contain flag constant_tsc" >> ~/summary.log
        SetTestStateFailed
        exit 1
    fi

    # check dmesg with hyperv_clocksource_tsc_page
    if [[ $(dmesg | grep "clocksource $clocksource") ]];then
        LogMsg "Test successful. dmesg contains log - clocksource $clocksource"
    else
        LogMsg "Test failed. dmesg does not contain log - clocksource $clocksource"
        echo "Test failed. dmesg does not contain log - clocksource $clocksource" >> ~/summary.log
        SetTestStateFailed
        exit 1
    fi
}

#
# MAIN SCRIPT
#
CheckSource
echo "Test passed: the current_clocksource is not null and value is right." >> ~/summary.log
LogMsg "Test completed successfully"
SetTestStateCompleted
