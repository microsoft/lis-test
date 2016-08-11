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

CheckSelinuxRules()
{
  aucStatus=`ausearch -m avc -c "$1"`
  if [[ -n $aucStatus  ]]; then
    LogMsg "ERROR: $1 is searched out in audit log, test failed. Log is $aucStatus"
    UpdateTestState $ICA_TESTFAILED
    UpdateSummary "$1 is searched out in audit log, test failed."
    UpdateSummary $aucStatus
    exit 1
  fi
}

#######################################################################
# Main script body
#######################################################################

# Create the state.txt file so ICA knows we are running
UpdateTestState $ICA_TESTRUNNING

# Source the constants file
if [ -e constants.sh ]; then
    . constants.sh
else
    LogMsg "WARN: Unable to source the constants file."
fi

# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

if [ ! ${TC_COVERED} ]; then
    LogMsg "The TC_COVERED variable is not defined!"
  echo "The TC_COVERED variable is not defined!" >> ~/summary.log
fi

echo "This script covers test case: ${TC_COVERED}" >> ~/summary.log

CheckSelinuxRules "kvp"
CheckSelinuxRules "vss"
CheckSelinuxRules "fcopy"

UpdateTestState $ICA_TESTCOMPLETED
exit 0