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
declare os_VENDOR os_RELEASE os_UPDATE os_PACKAGE os_CODENAME

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
# Determine if current distribution is a Fedora-based distribution
# (Fedora, RHEL, CentOS, etc).
#######################################################################
function is_fedora {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "Fedora" ] || [ "$os_VENDOR" = "Red Hat" ] || \
        [ "$os_VENDOR" = "CentOS" ] || [ "$os_VENDOR" = "OracleServer" ]
}

#######################################################################
# Determine if current distribution is a Rhel/CentOS 7 distribution
#######################################################################

function is_rhel7 {
    if [[ -z "$os_RELEASE" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "Red Hat" ] || \
        [ "$os_VENDOR" = "CentOS" ] || [ "$os_VENDOR" = "OracleServer" ] && \
        [ "$os_RELEASE" = "7" ]
}

#######################################################################
# Determine if current distribution is a SUSE-based distribution
# (openSUSE, SLE).
#######################################################################
function is_suse {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "openSUSE" ] || [ "$os_VENDOR" = "SUSE LINUX" ]
}

#######################################################################
# Determine if current distribution is an Ubuntu-based distribution
# It will also detect non-Ubuntu but Debian-based distros
#######################################################################
function is_ubuntu {
    if [[ -z "$os_PACKAGE" ]]; then
        GetOSVersion
    fi
    [ "$os_PACKAGE" = "deb" ]
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

dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

if is_rhel7 ; then #If the system is using systemd we use systemctl
    if [[ "$(systemctl is-active hypervfcopyd)" == "active" ]] || \
       [[ "$(systemctl is-active hv_fcopy_daemon)" == "active" ]]; then
        LogMsg "FCOPY Daemon is running"
        UpdateTestState $ICA_TESTCOMPLETED
        exit 0
    
    elif [[ "$(systemctl is-active hypervfcopyd)" == "unknown" ]] && \
         [[ "$(systemctl is-active hv_fcopy_daemon)" == "unknown" ]]; then
        LogMsg "ERROR: FCOPY Daemon not installed, test aborted"
        UpdateTestState $ICA_TESTABORTED
        exit 1
    
    else
        LogMsg "ERROR: FCOPY Daemon is installed but not running. Test aborted"
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi

else # For older systems we use ps
    if [[ $(ps -ef | grep '[h]v_fcopy_daemon') ]]; then
        LogMsg "FCOPY Daemon is running"
        UpdateTestState $ICA_TESTCOMPLETED
        exit 0
    else
        LogMsg "ERROR: FCOPY Daemon not running, test aborted"
        UpdateTestState $ICA_TESTABORTED
        exit 1

    fi
fi