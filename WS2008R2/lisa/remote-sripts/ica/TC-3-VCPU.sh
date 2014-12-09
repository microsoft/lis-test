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

#     This script was created to automate the testing of a Linux
#     Integration services.this script test the VCPU count  
#     inside the Linux VM and compare it to VCPU count given in
#     Hyper-V setting pane by performing the following
#     steps:
#	 1. Make sure we were given a configuration file with VCPU #count
#	 2. Get the VCPU count inside Linux VM .
#    3. Compare it with the VCPU count in constansts file.
#     
#	 To identify objects to compare with, we source a 
#     constansts file
#     named.   This file will be given to us from 
#     Hyper-V Host server.  It contains definitions like:
#         VCPU=1
#         Memory=2000

echo "########################################################"
echo "This is Test Case to Verify If VCPU Count is correct inside VM "

DEBUG_LEVEL=3
LINUX="Linux"
FREEBSD="FreeBSD"

dbgprint()
{
    if [ $1 -le $DEBUG_LEVEL ]; then
        echo "$2"
    fi
}

UpdateTestState()
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

dos2unix -f ica/* > /dev/null  2>&1

# Source the constants file

if [ -e $HOME/constants.sh ]; then
 . $HOME/constants.sh
else
 echo "ERROR: Unable to source the constants file."
 exit 1
fi


#
# Create the state.txt file so the ICA script knows
# we are running


UpdateTestState "TestRunning"

function GetOSType()
{
    OSType=$(uname -s)
    return $OSType
}

#echo "Test: Checking if VCPU Count inside linux VM is Correct. "
echo "Test: Checking if VCPU Count inside VM is Correct. "

function GetVCPUCount()
{
    GetOSType
    if [ "$OSType" = "$LINUX" ]; then
        echo "Linux System"
        VCPU_VM=$(cat /proc/cpuinfo | grep processor | wc -l)
    fi
    if [ "$OSType" = "$FREEBSD" ]; then
        echo "FreeBSD System"
        VCPU_VM=$(sysctl -a | egrep -i 'hw.ncpu' | awk '{print $2}')
    fi
}

#VCPU_LINUX=$(cat /proc/cpuinfo | grep processor | wc -l)

#if [[ $VCPU_LINUX -eq $VCPU ]]; then
# echo -e "Result :PASS : No. of VCPU count is correct inside the Guest VM."

# echo "INFO : No. of VCPU in Linux VM is $VCPU_LINUX and on Hyper-V setting pane is also $VCPU"

# UpdateTestState "TestCompleted"

# else
# echo -e "Test Fail : ERROR: VCPU count in linux VM is different then in Hyper-V setting pane"
# UpdateTestState "TestAborted"
# exit 1

#fi

GetVCPUCount
if [[ $VCPU_VM -eq $VCPU ]]; then
 echo -e "Result :PASS : No. of VCPU count is correct inside the Guest VM."
 echo "INFO : No. of VCPU in the Guest VM is $VCPU_VM and on Hyper-V setting pane is also $VCPU"
 UpdateTestState "TestCompleted"

 else
 echo -e "Test Fail : ERROR: VCPU count in Guest VM is different from the one in Hyper-V setting pane"
 echo "INFO : No. of VCPU in the Guest VM is $VCPU_VM and on Hyper-V setting pane is $VCPU"
 UpdateTestState "TestAborted"
 exit 1

fi

echo "#########################################################"
echo "Result : Test Completed Succesfully"
dbgprint 1 "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"
