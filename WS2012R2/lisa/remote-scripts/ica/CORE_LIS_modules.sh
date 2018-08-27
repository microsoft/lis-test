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
#   CORE_LIS_modules.sh
#
#   Description:
#   This script was created to automate the testing of a Linux
#   Integration services. The script will verify a list of given
#   LIS kernel modules if are loaded and output the version for each.
#
#   To pass test parameters into test cases, the host will create
#   a file named constants.sh. This file contains one or more
#   variable definition.
#
########################################################################

hv_string=$(dmesg | grep "Vmbus version:")
skip_modules=()
MODULES_ERROR=false

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

CONSTANTS_FILE="constants.sh"

LogMsg() {
    # Adding the timestamp to the log file
    echo `date "+%a %b %d %T %Y"` : ${1}
}

UpdateTestState() {
    echo $1 > $HOME/state.txt
}

#
# Update LISA with the current status
#
cd ~
UpdateTestState $ICA_TESTRUNNING

#
# Source the constants file
#
if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

#
# Check if vmbus string is recorded in dmesg
#
if [[ ( $hv_string == "" ) || ! ( $hv_string == *"hv_vmbus:"*"Vmbus version:"* ) ]]; then
    LogMsg "Error! Could not find the VMBus protocol string in dmesg."
    echo "Error! Could not find the VMBus protocol string in dmesg." >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

vmbusIncluded=`grep CONFIG_HYPERV=y /boot/config-$(uname -r)`
if [ $vmbusIncluded ]; then
    skip_modules+=("hv_vmbus")
    echo "Info: Skiping hv_vmbus module as it is built-in." >> ~/summary.log
fi

storvscIncluded=`grep CONFIG_HYPERV_STORAGE=y /boot/config-$(uname -r)`
if [ $storvscIncluded ]; then
    skip_modules+=("hv_storvsc")
    echo "Info: Skiping hv_storvsc module as it is built-in." >> ~/summary.log
fi

# declare temporary array
tempList=()

# remove each module in HYPERV_MODULES from skip_modules
for module in "${HYPERV_MODULES[@]}"; do
    skip=""
    for modSkip in "${skip_modules[@]}"; do
        [[ $module == $modSkip ]] && { skip=1; break; }
    done
    [[ -n $skip ]] || tempList+=("$module")
done
HYPERV_MODULES=("${tempList[@]}")

#
# Verify first if the LIS modules are loaded
#
for module in "${HYPERV_MODULES[@]}"; do
    load_status=$(lsmod | grep $module 2>&1)

    # Check to see if the module is loaded
    if [[ $load_status =~ $module ]]; then
        if rpm --help 2>/dev/null; then
            if rpm -qa | grep hyper-v 2>/dev/null; then
                version=$(modinfo $module | grep version: | head -1 | awk '{print $2}')
                LogMsg "Detected module $module version: ${version}"
                echo "Detected module $module version: ${version}" >> ~/summary.log
                continue
            fi
        fi

        version=$(modinfo $module | grep vermagic: | awk '{print $2}')
        if [[ "$version" == "$(uname -r)" ]]; then
            LogMsg "Detected module $module version: ${version}"
            echo "Detected module $module version: ${version}" >> ~/summary.log
        else
            LogMsg "Error: LIS module $module doesn't match the kernel build version!"
            echo "Error: LIS module $module doesn't match the kernel build version!" >> ~/summary.log
            MODULES_ERROR=true
        fi
    else
        LogMsg "Error: LIS module $module not found!"
        echo "Error: LIS module $module not found!" >> ~/summary.log
        MODULES_ERROR=true
    fi
done

if $MODULES_ERROR; then
    UpdateTestState $ICA_TESTFAILED
    exit 1
else
    UpdateTestState $ICA_TESTCOMPLETED
    exit 0
fi
