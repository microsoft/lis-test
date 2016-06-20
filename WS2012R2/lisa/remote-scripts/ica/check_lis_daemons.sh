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
ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_FAILED="TestFailed"

#######################################################################
# Adds a timestamp to the log file
#######################################################################
LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}
}

#######################################################################
# Updates the summary.log file
#######################################################################
UpdateSummary()
{
    echo $1 >> ~/summary.log
}

#######################################################################
# Keeps track of the state of the test
#######################################################################
UpdateTestState()
{
    echo $1 > ~/state.txt
}

#######################################################################
# Main script body
#######################################################################

cd ~

# Create the state.txt file so ICA knows we are running
UpdateTestState $ICA_TESTRUNNING

LogMsg "This script checks LIS daemons"

# Source the constants file
if [ -e constants.sh ]; then
    . constants.sh
else
    LogMsg "WARN: Unable to source the constants file."
fi

dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

for daemon in ${DAEMONS[*]}; do
    if is_rhel7 ; then #If the system is using systemd we use systemctl
        if [[ "$(systemctl is-active hyperv"$daemon"d)" == "active" ]] || \
           [[ "$(systemctl is-active hv_"$daemon"_daemon)" == "active" ]]; then
            LogMsg "$daemon Daemon is running"
            UpdateSummary "$daemon Daemon is running"

        elif [[ "$(systemctl is-active hyperv"$daemon"d)" == "unknown" ]] && \
             [[ "$(systemctl is-active hv_"$daemon"_daemon)" == "unknown" ]]; then
            LogMsg "ERROR: $daemon Daemon not installed, test aborted"
            UpdateSummary "ERROR: $daemon Daemon not installed, test aborted"
            UpdateTestState $ICA_TESTABORTED
            exit 1
        else
            LogMsg "ERROR: $daemon Daemon is installed but not running. Test aborted"
            UpdateSummary "ERROR: $daemon Daemon is installed but not running. Test failed"
            UpdateTestState $ICA_FAILED
            exit 1
        fi
    else # For older systems we use ps
        if [[ $(ps -ef | grep '[h]v_'$daemon'_daemon') ]]; then
            LogMsg "$daemon Daemon is running"
            UpdateSummary "$daemon Daemon is running"
        else
            LogMsg "ERROR: $daemon Daemon not running, test aborted"
            UpdateSummary "ERROR: $daemon Daemon not running, test aborted"
            UpdateTestState $ICA_TESTABORTED
            exit 1
        fi
    fi
done
UpdateTestState $ICA_TESTCOMPLETED
exit 0