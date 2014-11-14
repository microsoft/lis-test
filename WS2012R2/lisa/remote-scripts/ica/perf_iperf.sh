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
# perf_iperf.sh
#
# Description:
#     For the test to run you have to place the iperf tool package in the
#     Tools folder under lisa.
#
# Parameters:
#     IPERF_PACKAGE: the iperf toolkit package
#     TARGET_IP:     the ip address for the machine which runs iPerf as server
#     IPERF_THREADS: how many iPerf connections will be created by iPerf client
#     IPERF_BUFFER:  the buffer size set in iPerf client
#     IPERF_TCPWINDOW: the tcp window size set in iPerf client
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
if [ "${IPERF_PACKAGE:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the IPERF_PACKAGE test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${TARGET_IP:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the TARGET_IP test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 30
fi

if [ "${IPERF_THREADS:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the IPERF_THREADS test parameter is undefined"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 40
fi

echo "iPerf package   = ${IPERF_PACKAGE}"
echo "TARGET_ip       = ${TARGET_IP}"
echo "IPERF_THREADS   = ${IPERF_THREADS}"

#
# Extract the files from the IPerf tar package
#
tar -xzf ./${IPERF_PACKAGE}
if [ $? -ne 0 ]; then
    msg="Error: Unable extract ${IPERF_PACKAGE}"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 70
fi

#
# Get the root directory of the tarball
#
rootDir=`tar -tzf ${IPERF_PACKAGE} | sed -e 's@/.*@@' | uniq`
if [ -z ${rootDir} ]; then
    msg="Error: Unable to determine root directory if ${IPERF_PACKAGE} tarball"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 80
fi

LogMsg "rootDir = ${rootDir}"
cd ${rootDir}

#
# Build iperf
#
./configure
if [ $? -ne 0 ]; then
    msg="Error: ./configure failed"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 90
fi

make
if [ $? -ne 0 ]; then
    msg="Error: Unable to build iperf"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 100
fi

make install
if [ $? -ne 0 ]; then
    msg="Error: Unable to install iperf"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 110
fi

#
# Copy the iPerf binary to the TARGET_IP machine
#
LogMsg "Copying iperf to target machine"

sleep 40

scp src/iperf root@[${TARGET_IP}]:
if [ $? -ne 0 ]; then
    msg="Error: Unable to copy iperf binary to target machine"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 120
fi

#
# Start iPerf in server mode on the Target machine
#
LogMsg "Starting iPerf in server mode on ${TARGET_IP}"

ssh root@${TARGET_IP} "echo '/root/iperf -s -D -V' | at now"
if [ $? -ne 0 ]; then
    msg="Error: Unable to start iPerf on the Target machine"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 130
fi

#
# Give the server a few seconds to initialize
#
LogMsg "Wait 5 seconds so the server can initialize"

sleep 5

#
# Run iPerf and save the output to a logfile
#
LogMsg "Starting iPerf client"

iperf -c ${TARGET_IP} -t 300 -P ${IPERF_THREADS} -V > ~/iperfdata.log
if [ $? -ne 0 ]; then
    msg="Error: Unable to start iPerf on the client"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 140
fi

#
# If we made it here, everything worked.
# Indicate success
#
LogMsg "Test completed successfully"
UpdateTestState $ICA_TESTCOMPLETED

exit 0

