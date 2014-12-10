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

########################################################################
#     This script was created to automate the testing of a Linux/FreeBSD
#     Integration services.this script tests the VCPU count  
#     inside the Linux/FreeBSD VM and compares it to VCPU count given in
#     Hyper-V setting pane by performing the following
#     steps:
#	 1. Make sure we were given a configuration file with VCPU #count
#	 2. Get the VCPU count inside Linux/FreeBSD VM .
#        3. Compare it with the VCPU count in constansts.sh file. There
#        are two kinds of types:
#            a. No iteration=n defined in constants.sh, will be 
#               VCPU=n
#            b. There is iteration=n defined in constants.sh, will be
#               VCPU=n
#               iteration=n
#               iterationParam=n
#             In case b, iterationParam=n will used as the VCPU count
#             instead of VCPU==n

echo "########################################################"
echo "This is Test Case to Verify If VCPU Count is correct inside VM "

DEBUG_LEVEL=3
LINUX="Linux"
FREEBSD="FreeBSD"

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

function GetOSType()
{
    OSType=$(uname -s)
    return $OSType
}

#echo "Test: Checking if VCPU Count inside linux VM is Correct. "

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

# Check if there is iteration=n 
if [ -n "$iteration" ]; then

    # Check if there is iterationParam=n
    if [ -z "$iterationParam" ]; then
        echo "ERROR: No iterationParam. "
        # Update the state.txt file so ICA scripts knows I am failing
        UpdateTestState "TestFailed"
        exit 1
    fi

    # Update the state.txt file so ICA scripts knows I am running
    UpdateTestState "TestRunning"

    GetVCPUCount
    echo "Test: iteration is defined. Checking if VCPU Count inside VM is Correct. "
    echo "iteration=" $iteration
    echo "iterationParam=" $iterationParam

    if [ $VCPU_VM -eq $iterationParam ]; then
        echo -e "Result :PASS : No. of VCPU count is correct inside the Guest VM."
        echo "INFO : No. of VCPU in the Guest VM is $VCPU_VM and on Hyper-V setting pane is also $iterationParam"
        echo "#########################################################"
        echo "Result : Test Completed Succesfully"
        dbgprint 1 "Exiting with state: TestCompleted."
        UpdateTestState "TestCompleted"
        exit 0
    else
        echo -e "Test Fail : ERROR: VCPU count in Guest VM is different from the one in Hyper-V setting pane"
        echo "INFO : No. of VCPU in the Guest VM is $VCPU_VM and on Hyper-V setting pane is $VCPU"
        UpdateTestState "TestFailed"
        exit 1
    fi
fi

# If there is no iteration=n
if [ -z "$VCPU" ]; then
    echo "ERROR: No VCPU defined. "
    #Update the state.txt file so ICA scripts knows I am failing
    UpdateTestState "TestFailed"
    exit 1
fi

#
# Create the state.txt file so the ICA script knows I am running
UpdateTestState "TestRunning"

GetVCPUCount
echo "Test: iteration is not definde. Checking if VCPU Count inside VM is Correct. "
if [ $VCPU_VM -eq $VCPU ]; then
    echo -e "Result :PASS : No. of VCPU count is correct inside the Guest VM."
    echo "INFO : No. of VCPU in the Guest VM is $VCPU_VM and on Hyper-V setting pane is also $VCPU"
    UpdateTestState "TestCompleted"

else
    echo -e "Test Fail : ERROR: VCPU count in Guest VM is different from the one in Hyper-V setting pane"
    echo "INFO : No. of VCPU in the Guest VM is $VCPU_VM and on Hyper-V setting pane is $VCPU"
    UpdateTestState "TestFailed"
    exit 1

fi

echo "#########################################################"
echo "Result : Test Completed Succesfully"
dbgprint 1 "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"

