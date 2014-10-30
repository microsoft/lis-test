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
# Performance_STREAM.sh
#
# Description:
#     For the test to run you have to place the numactl-2.0.10.tar.gz archive and stream.c in the
#     Tools folder under lisa.
#
# Parameters:
#     STREAM_SOURCE: the source code of stream (stream.c)
#     LIBNUMA_PACKAGE: the libnuma package
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
if [ "${STREAM_SOURCE:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the STREAM_SOURCE test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${LIBNUMA_PACKAGE:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the LIBNUMA_PACKAGE test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

echo "stream source code= ${STREAM_SOURCE}"
echo "libnuma package   = ${LIBNUMA_PACKAGE}"

#
# Extract the files from the tar package
#
tar -xzf ./${LIBNUMA_PACKAGE}
if [ $? -ne 0 ]; then
    msg="Error: Unable extract ${LIBNUMA_PACKAGE}"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 70
fi

#
# Get the root directory of the tarball
#
rootDir=`tar -tzf ${LIBNUMA_PACKAGE} | sed -e 's@/.*@@' | uniq`
if [ -z ${rootDir} ]; then
    msg="Error: Unable to determine root directory if ${LIBNUMA_PACKAGE} tarball"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 80
fi

LogMsg "rootDir = ${rootDir}"
cd /root/${rootDir}/

#
# Compile libnuma
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
    msg="Error: Unable to make"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 100
fi

make install
if [ $? -ne 0 ]; then
    msg="Error: Unable to install"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 110
fi

#
# Compile STREAM.c
#
# set the number of threads equal to the number of cores on your machine:
export OMP_NUM_THREADS=48

cd /root/
gcc -O3 -std=c99 -fopenmp -lnuma -DN=80000000 -DNTIMES=100 stream.c -o stream-gcc
if [ $? -ne 0 ]; then
    msg="Error: ./Compile stream.c by gcc failed"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 90
fi

LogMsg "Starting stream-gcc"

./stream-gcc > /root/stream-gcc.log

#
# If we made it here, everything worked.
# Indicate success
#
LogMsg "Test completed successfully"
UpdateTestState $ICA_TESTCOMPLETED

exit 0

