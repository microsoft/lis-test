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
# This test assumes the TARGET_IP machine is a bare metal
# Linux machine.  This script assumes this machine is running and
# has been provisioned.
#
# This test will download iPerf, build, install, then run iPerf.
# Before starting iPerf on the local machine, the iPerf binary
# is copied to the TARGET_IP machine and started in server mode.
#
# The iPerf output is directed into a file named ~/iperfdata.log
#
# This test script requires the IPERF_PACKAGE test parameter.
#   IPERF_PACKAGE=iperf-2.0.5.tar.gz
#   TARGET_IP=192.168.1.100
#   TARGET_SSHKEY=lisa_id_rsa
#   IPERF_THREADS=4
#   IPERF_BUFFER=8KB
#   IPERF_TCPWINDOW=64KB
#
# A typical XML test definition for this test case would look
# similar to the following:
#        <test>
#           <testName>Perf_iPerf</testName>          
#           <testScript>perf_iperf.sh</testScript>
#           <files>remote-scripts/ica/perf_iperf.sh,ssh/rhel5_id_rsa</files>
#           <testParams>
#               <param>IPERF_PACKAGE=iperf-2.0.5.tar.gz</param>
#               <param>TARGET_IP=192.168.1.100</param>
#               <param>TARGET_SSHKEY=rhel5_id_rsa</param>
#               <param>IPERF_THREADS=10</param>
#           </testParams>
#           <uploadFiles>
#               <file>iperfdata.log</file>
#           </uploadFiles>
#           <timeout>1200</timeout>
#           <OnError>Continue</OnError>
#        </test>
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

if [ "${TARGET_SSHKEY:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the TARGET_SSHKEY test parameter is undefined"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 40
fi

if [ "${IPERF_THREADS:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the IPERF_THREADS test parameter is undefined"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 40
fi

#
# Make sure the SSH key file was copied to this test system
#
if [ ! -e "/root/${TARGET_SSHKEY}" ]; then
    msg="Error: The SSH Key file '/root/${TARGET_SSHKEY}' does not exist"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 50
fi

chmod 600 /root/${TARGET_SSHKEY}

echo "iPerf package   = ${IPERF_PACKAGE}"
echo "TARGET_ip       = ${TARGET_IP}"
echo "TARGET_SSHKEY   = ${TARGET_SSHKEY}"
echo "IPERF_THREADS   = ${IPERF_THREADS}"

#
# Download iperf from the website
#
#wget "http://sourceforge.net/projects/iperf/files/latest/download/${IPERF_PACKAGE}"
#if [ $? -ne 0 ]; then
#    ${msg}="Error: unable to download ${IPERF_PACKAGE}"
#    LogMsg "${msg}"
#    echo "${msg}" >> ~/summary.log
#    UpdateTestState $ICA_TESTFAILED
#    exit 60
#fi

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

scp -o StrictHostKeyChecking=no -i /root/${TARGET_SSHKEY} src/iperf root@${TARGET_IP}:
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

ssh -i /root/${TARGET_SSHKEY} root@${TARGET_IP} "echo '/root/iperf -s -D' | at now"
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

iperf -c ${TARGET_IP} -t 300 -P ${IPERF_THREADS} > ~/iperfdata.log
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

