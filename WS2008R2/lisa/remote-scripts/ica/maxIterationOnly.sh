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

# Description:
#    This script was created to verify the only the maxiteration
#    property parameters in configuration file


echo "####################################################################"
echo "This is test case to verify the iteration parameters in
constants.sh"

DEBUG_LEVEL=3

function dbgprint()
{
    if [ $1 -le $DEBUG_LEVEL ]; then
        echo "$2"
    fi
}

function UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

if [ -e ~/summary.log ]; then
    dbgprint 1 "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

cd ~

#
# Convert any .sh files to Unix format
#
dos2unix -f ica/* > /dev/null 2>&1

# Source the constants file

#
# Create the state.txt file so the ICA script knows I am running
#

UpdateTestState "TestRunning"

echo "execute maxIterationOnly.sh" > summary.log

dbgprint 1 "Updating test case state to completed"
UpdateTestState "TestCompleted"
