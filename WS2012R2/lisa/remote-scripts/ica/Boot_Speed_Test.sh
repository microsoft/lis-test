#!/bin/bash

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

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error while performing the test

CONSTANTS_FILE="constants.sh"

LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1}
}

UpdateSummary() {
    echo $1 >> ~/summary.log
}

UpdateTestState() {
    echo $1 > ~/state.txt
}

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

# Source the constants file
if [ -e ~/${CONSTANTS_FILE} ]; then
    source ~/${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    echo $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
   exit 1
fi

yum install -y bc

if [[ "$BASE_TIME" == "" ]];then
    UpdateTestState $ICA_TESTABORTED
else
    UpdateSummary "Base time: ${BASE_TIME}"
fi

base_time=$BASE_TIME
kernel_time="$(systemd-analyze)"
UpdateSummary "$kernel_time"

kernel_time="$(echo $kernel_time | awk '{print $4}')"
val="$(echo $kernel_time | sed 's/[A-Za-z]*//g')"
mesure="$(echo $kernel_time | sed 's/[0-9]\.*//g')"
comp_val="$(echo $base_time | sed 's/[A-Za-z]*//g')"

echo $kernel_time >> /root/boot_speed.log

if [[ "$mesure" == "s" ]];then
    val=$(echo "$val * 1000" | bc -l)
    val=${val%.*}
fi

if [[ "$val" -ge "$comp_val" ]];then
        UpdateTestState $ICA_TESTFAILED
        exit 1
else
        UpdateTestState $ICA_TESTCOMPLETED
        exit 0
fi

