#!/bin/bash
#######################################################################
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
#######################################################################

#######################################################################
#
# InstallLisNext.sh
#
# Clone the Lis-Next reporitory from github, then build and 
# install LIS from the source code.
#
#######################################################################


#
# Note:
# ICA_TESTABORTED is an error that occurs during test setup for the test.
# ICA_TESTFAILED  is an error that occurs during the actual test.
#

ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"


LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}


#######################################################################
#
# Main script body
#
#######################################################################

#
# Create the state.txt file so the LISA knows
# we are running
#
cd ~
UpdateTestState $ICA_TESTRUNNING

#
# Remove any old symmary.log files
#
LogMsg "Info : Cleaning up any old summary.log files"
if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

#
# Source any test parameters passed to us via the constants.sh file
#
if [ -e ~/constants.sh ]; then
    LogMsg "Info : Sourcing ~/constants.sh"
    . ~/constants.sh
else
    LogMsg "ERROR: Unable to source the constants file."
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

#
# Source the utils.sh script
#
if [ ! -e ~/utils.sh ]; then
    LogMsg "Error: The utils.sh script was to copied to the VM"
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

. ~/utils.sh

#
# If there is a lis-next directory, delete it since it should not exist.
#
if [ -e ./lis-next ]; then
    LogMsg "Info : Removing an old lis-next directory"
    rm -rf ./lis-next
fi

#
# Clone Lis-Next 
#
LogMsg "Info : Cloning lis-next"
git clone https://github.com/LIS/lis-next
if [ $? -ne 0 ]; then
    LogMsg "Error: unable to clone lis-next"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# Figure out what version of CentOS/RHEL we are running
#
rhel_version=0
GetDistro
LogMsg "Info : Detected OS distro/version ${DISTRO}"

case $DISTRO in
redhat_7|centos_7)
    rhel_version=7
    ;;
redhat_6|centos_6)
    rhel_version=6
    ;;
redhat_5|centos_5)
    rhel_version=5
    ;;
*)
    LogMsg "Error: Unknow or unsupported version: ${DISTRO}"
    UpdateTestState $ICA_TESTFAILED
    exit 1
    ;;
esac

LogMsg "Info : Building ${rhel_version}.x source tree"
cd lis-next/hv-rhel${rhel_version}.x/hv
./rhel${rhel_version}-hv-driver-install
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to build the lis-next RHEL ${rhel_version} code"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

echo "Build LIS-Next from the hv-rhel-${rhel_version}.x code" > ~/summary.log

#
# If we got here, everything worked.
# Let LISA know
#
LogMsg "Exiting with state: TestCompleted."
UpdateTestState $ICA_TESTCOMPLETED

exit 0

