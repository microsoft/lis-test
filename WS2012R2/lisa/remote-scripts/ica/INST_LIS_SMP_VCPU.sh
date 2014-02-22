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
# CheckVCPU.sh
# Description:
#     This script was created to automate the testing of a Linux
#     Integration services. This script test the VCPU count  
#     inside the Linux VM and compare it to VCPU count given in
#     Hyper-V setting pane. The test performs the following
#     steps:
#	 1. Make sure we have a constants.sh file.
#    2. Make sure constants.sh defines VCPU #count
#	 3. Get the VCPU count inside Linux VM.
#    4. Compare the VMs CPU count with the VCPU from constants.sh
#     
#	 To pass test parameters into test cases, the host will create
#    a file named constants.sh.  This file contains one or more
#    variable definition.  e.g.
#         VCPU=2
#
################################################################

LogMsg()
{
    echo "${1}"
}

UpdateTestState()
{
    echo "${1}" > $HOME/state.txt
}

function GetOSType()
{
    OSType=$(uname -s)
}

function GetVCPUCount()
{
    GetOSType
    if [ "$OSType" = "${LINUX}" ]; then
        echo "Linux System"
        VCPU_VM=$(cat /proc/cpuinfo | grep processor | wc -l)
    fi
    if [ "$OSType" = "${FREEBSD}" ]; then
        echo "FreeBSD System"
        VCPU_VM=$(sysctl -a | egrep -i 'hw.ncpu' | awk '{print $2}')
    fi
}


LINUX="Linux"
FREEBSD="FreeBSD"

#
# Let LISA know we are running
#
cd ~
UpdateTestState "TestRunning"

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -f ~/summary.log
fi

#
# Source the constants file
#
if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
else
    LogMsg "ERROR: Unable to source the constants file."
    exit 10
fi

echo "VCPU = ${VCPU}"
if [ "${VCPU:-"UNDEFINED"}" = "UNDEFINED" ]; then
    LogMsg "Error: constants.sh did not contain a VCPU value"
    UpdateTestState "TestAborted"
    exit 20
fi

GetVCPUCount
LogMsg "Expected CPU count = ${VCPU}"
LogMsg "Actual CPU count = ${VCPU_VM}"

echo "Debug: OSType = ${OSType}"

if [[ $VCPU_VM -ne $VCPU ]]; then
    LogMsg "ERROR: VCPU count in Guest VM does not match Hyper-V setting"
    UpdateTestState "TestFailed"
    exit 30
fi

LogMsg "Test completed successfully"
UpdateTestState "TestCompleted"
exit 0

