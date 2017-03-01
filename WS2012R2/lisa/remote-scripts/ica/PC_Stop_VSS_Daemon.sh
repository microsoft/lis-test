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

# Create the state.txt file so ICA knows we are running
UpdateTestState $ICA_TESTRUNNING

# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

# Source the constants file
if [ -e constants.sh ]; then
    . constants.sh
else
    LogMsg "WARN: Unable to source the constants file."
fi

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    UpdateTestState $ICA_TESTABORTED
}

systemctl --version
if [ $? -eq 0 ]; then
    vss_service_name=$(systemctl | grep vss | awk '{print $1}' | tail -1)
    
    if [ "$(systemctl is-active ${vss_service_name})" == "active" ]; then
        LogMsg "VSS Daemon is running, we will try to stop it gracefully"
        /bin/systemctl stop $vss_service_name
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Failed to stop VSS Daemon"
            UpdateTestState $ICA_TESTABORTED
        fi

        LogMsg "Succesfully stopped the VSS Daemon"
        UpdateTestState $ICA_TESTCOMPLETED

    elif [ "$(systemctl is-active ${vss_service_name})" == "unknown" ]; then
        LogMsg "ERROR: VSS Daemon not installed, test aborted"
        UpdateTestState $ICA_TESTABORTED

    else
        LogMsg "Warning: VSS Daemon is installed but not running"
        UpdateTestState $ICA_TESTCOMPLETED
    fi

else
    if [[ $(ps -ef | grep 'hypervvssd') ]] || \
       [[ $(ps -ef | grep '[h]v_vss_daemon') ]]; then

        LogMsg "VSS Daemon is running"
        vss_pid=$(ps aux | grep vss | head -1 | awk '{print $2}')
        kill $vss_pid
        
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Failed to stop VSS Daemon"
            UpdateTestState $ICA_TESTABORTED
        fi
        LogMsg "Succesfully stopped the VSS Daemon"
        UpdateTestState $ICA_TESTCOMPLETED

    else
        LogMsg "ERROR: VSS Daemon not running, test aborted"
        UpdateTestState $ICA_TESTABORTED
    fi
fi