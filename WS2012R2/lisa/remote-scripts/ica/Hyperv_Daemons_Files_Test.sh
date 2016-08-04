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
# Check hyper-v daemons related file under default folder
#######################################################################
CheckDaemonsFiles()
{
  dameonFile=`ls /usr/lib/systemd/system | grep -i "$1"`
  dameonFile2=`ls /etc/systemd/system/multi-user.target.wants | grep -i "$1"`
  if [[ "$dameonFile" != "$1" ]] || [[ "$dameonFile2" != "$1" ]] ; then
    LogMsg "ERROR: $1 is not in /usr/lib/systemd or /etc/systemd/system/multi-user.target.wants , test failed"
    UpdateTestState $ICA_TESTFAILED
    exit 1
  fi
}

#######################################################################
# Check hyper-v daemons related file under default folder for rhel 6
#######################################################################
CheckDaemonsFilesRHEL6()
{
  dameonFile=`ls /etc/rc.d/init.d | grep -i "$1"`

  if [[ "$dameonFile" != "$1" ]] ; then
    LogMsg "ERROR: $1 is not in /etc/rc.d/init.d , test failed"
    UpdateTestState $ICA_TESTFAILED
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
   # test hyper-v daemons files exist target folder
  CheckDaemonsFiles "hypervkvpd.service"
  CheckDaemonsFiles "hypervvssd.service"
  CheckDaemonsFiles "hypervfcopyd.service"

elif is_rhel6; then # For older systems we use ps
  CheckDaemonsFilesRHEL6 "hypervkvpd.service"
  CheckDaemonsFilesRHEL6 "hypervvssd.service"
  CheckDaemonsFilesRHEL6 "hypervfcopyd.service"
else
  echo "Does not support current linux release!"
  echo "TestAborted" > state.txt
  exit 2
fi

UpdateTestState $ICA_TESTCOMPLETED
exit 0
