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
ICA_TESTFAILED="TestFailed"

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
# Check hyper-v daemons service status under 90-default.preset
#######################################################################
CheckDaemonsPreset()
{
  dameonPreset=`cat /lib/systemd/system-preset/90-default.preset | grep -i "$1"`
  if [ "$dameonPreset" != "$1" ]; then
    LogMsg "ERROR: $1 is not in 90-default.preset, test aborted"
    UpdateTestState $ICA_TESTFAILED
    exit 1
  fi
}

#######################################################################
# Check hyper-v daemons service status is active
#######################################################################
CheckDaemonsStatus()
{
  dameonStatus=`systemctl is-active "$1"`
  if [ $dameonStatus != "active" ]; then
    LogMsg "ERROR: $1 is not in running state, test aborted"
    UpdateTestState $ICA_TESTFAILED
    UpdateSummary "ERROR: Please check whehter enable 'Guest Services and Data Exchange'"
    exit 1

  fi
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
    exit 2
}

if is_rhel7 ; then #If the system is using systemd we use systemctl

  CheckDaemonsPreset "enable hypervkvpd.service"
  CheckDaemonsPreset "enable hypervvssd.service"
  CheckDaemonsPreset "enable hypervfcopyd.service"
   # test hyper-v daemons is enabled by defaultSize
  CheckDaemonsStatus "hypervkvpd.service"
  CheckDaemonsStatus "hypervvssd.service"
  CheckDaemonsStatus "hypervfcopyd.service"

else # For older systems we use ps
    if [[ $(ps -ef | grep 'hypervvssd') ]] || \
       [[ $(ps -ef | grep '[h]v_vss_daemon') ]]; then
        LogMsg "VSS Daemon is running"

    else
        LogMsg "ERROR: VSS Daemon not running, test aborted"
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi
    if [[ $(ps -ef | grep 'hypervkvpd') ]] || \
       [[ $(ps -ef | grep '[h]v_kvp_daemon') ]]; then
        LogMsg "KVP Daemon is running"

    else
        LogMsg "ERROR: KVP Daemon not running, test aborted"
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi

    if [[ $(ps -ef | grep 'hypervfcopyd') ]] || \
       [[ $(ps -ef | grep '[h]v_fcopy_daemon') ]]; then
        LogMsg "Fcopy Daemon is running"

    else
        LogMsg "ERROR: FCopy Daemon not running, test aborted"
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi

fi


UpdateTestState $ICA_TESTCOMPLETED
exit 0
