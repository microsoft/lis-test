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

DBGLEVEL=3

dbgprint()
{
    if [ $1 -le $DBGLEVEL ]; then
        echo "$2"
    fi
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

#
# Create the state.txt file so ICA knows we are running
#
UpdateTestState $ICA_TESTRUNNING

#
# Source the ICA config file
#
if [ -e ./constants.sh ]; then
    . ./constants.sh
else
    echo "Error: Unable to source constants.sh"
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

timeout=2
if [ $SLEEP_TIMEOUT ]; then
    timeout=$SLEEP_TIMEOUT
fi

echo "Sleeping for $timeout seconds"
sleep $timeout
echo "Sleep completed"

echo "Simple test" > summary.log
echo "sleep for $timeout seconds" >> summary.log

#
# Let the callknow everything worked
#
UpdateTestState $ICA_TESTABORTED

exit 0

