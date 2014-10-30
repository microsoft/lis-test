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

#######################################################################
#
# Performance_LINPACK.sh
#
# Description:
#     For the test to run you have to place the l_lpk_p_11.2.0.003.tgz archive in the
#     Tools folder under lisa.
#
# Parameters:
#     TOOL_NAME: the LINPACK toolkit package
#     LINPACK_SCRIPT: the LINPACK script to run
#
#######################################################################



ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"


#
# Function definitions
#

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` ": ${1}"
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

cd ~
UpdateTestState $ICA_TESTRUNNING
LogMsg "Starting test"

#
# Delete any old summary.log file
#
LogMsg "Cleaning up old summary.log"
if [ -e ~/summary.log ]; then
    rm -f ~/summary.log
fi

touch ~/summary.log

#
# Source the constants.sh file
#
LogMsg "Sourcing constants.sh"
if [ -e ~/constants.sh ]; then
    . ~/constants.sh
else
    msg="Error: ~/constants.sh does not exist"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

#
# Make sure the required test parameters are defined
#
if [ "${TOOL_NAME:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the LINPACK test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${LINPACK_SCRIPT:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the LINPACK_SCRIPT test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

echo "Linpack package   = ${TOOL_NAME}"
echo "Linpack scripts   = ${LINPACK_SCRIPT}"

#
# Extract the files from the tar package
#
tar -xzf ./${TOOL_NAME}
if [ $? -ne 0 ]; then
    msg="Error: Unable extract ${TOOL_NAME}"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 70
fi

#
# Get the root directory of the tarball
#
rootDir=`tar -tzf ${TOOL_NAME} | sed -e 's@/.*@@' | uniq`
if [ -z ${rootDir} ]; then
    msg="Error: Unable to determine root directory if ${TOOL_NAME} tarball"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 80
fi

LogMsg "rootDir = ${rootDir}"
cd /root/${rootDir}/benchmarks/linpack/

#
# Start LINPACK
#
LogMsg "Starting LINPACK"

./runme_xeon64 > /root/LINPACK.log

#
# If we made it here, everything worked.
# Indicate success
#
LogMsg "Test completed successfully"
UpdateTestState $ICA_TESTCOMPLETED

exit 0

