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
# performance_redis.sh
#
# Description:
#     For the test to run you have to place the redis-2.8.17.tar.gz archive in the
#     Tools folder under lisa.
#
# Parameters:
#      REDIS_PACKAGE:         the redis tool package 
#      REDIS_HOST_IP:         the ip address of the machine runs Redis server
#      REDIS_HOST_PORT:       the ip port of the machine runs Redis server
#      REDIS_CLIENTS:         number of parallel connections 
#      REDIS_RANDOM_KEY_SCOPE: use random keys for SET/GET/INCR, random values for SADD
#      REDIS_DATA_SIZE:       data size of SET/GET value in bytes 
#      REDIS_TESTSUITES:      only run the comma-separated list of tests. The test names are the same as the ones produced as output.
#      REDIS_NUMBER_REQUESTS: total number of requests
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
if [ "${REDIS_PACKAGE:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the REDIS_PACKAGE test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${REDIS_HOST_IP:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the REDIS_HOST_IP test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 30
fi

if [ "${REDIS_HOST_PORT:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="WARNING: the REDIS_HOST_PORT test parameter is undefined"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    REDIS_HOST_PORT=6379
fi

if [ "${REDIS_CLIENTS:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="WARNING: the REDIS_CLIENTS test parameter is undefined"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    REDIS_CLIENTS=1000
fi

if [ "${REDIS_RANDOM_KEY_SCOPE:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="WARNING: the REDIS_RANDOM_KEY_SCOPE test parameter is undefined"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    REDIS_RANDOM_KEY_SCOPE=100000000000
fi

if [ "${REDIS_DATA_SIZE:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="WARNING: the REDIS_DATA_SIZE test parameter is undefined"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    REDIS_DATA_SIZE=1
fi

if [ "${REDIS_TESTSUITES:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="WARNING: the REDIS_TESTSUITES test parameter is undefined"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    REDIS_TESTSUITES="SET"
fi

if [ "${REDIS_NUMBER_REQUESTS:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="WARNING: the REDIS_NUMBER_REQUESTS test parameter is undefined"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    REDIS_NUMBER_REQUESTS=10000000
fi

echo "REDIS_PACKAGE          = ${REDIS_PACKAGE}"
echo "REDIS_HOST_IP          = ${REDIS_HOST_IP}"
echo "REDIS_HOST_PORT        = ${REDIS_HOST_PORT}"
echo "REDIS_CLIENTS          = ${REDIS_CLIENTS}"
echo "REDIS_RANDOM_KEY_SCOPE = ${REDIS_RANDOM_KEY_SCOPE}"
echo "REDIS_DATA_SIZE        = ${REDIS_DATA_SIZE}"
echo "REDIS_TESTSUITES       = ${REDIS_TESTSUITES}"
echo "REDIS_NUMBER_REQUESTS  = ${REDIS_NUMBER_REQUESTS}"

#
# Extract the files from the Redis tar package, on client machine
#
tar -xzf ./${REDIS_PACKAGE}
if [ $? -ne 0 ]; then
    msg="Error: Unable extract ${REDIS_PACKAGE}"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 40
fi

# Get the root directory of the tarball, on client machine
rootDir=`tar -tzf ${REDIS_PACKAGE} | sed -e 's@/.*@@' | uniq`
if [ -z ${rootDir} ]; then
    msg="Error: Unable to determine root directory if ${REDIS_PACKAGE} tarball"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 50
fi

LogMsg "rootDir = ${rootDir}"
cd ${rootDir}

# Build tool on client machine
make 
if [ $? -ne 0 ]; then
    msg="Error: make redis tool failed"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 60
fi

#
# Copy the redis package to the REDIS_HOST_IP machine
#
LogMsg "Copying Redis package to target machine"
scp /root/${REDIS_PACKAGE} root@[${REDIS_HOST_IP}]:
if [ $? -ne 0 ]; then
    msg="Error: Unable to copy REDIS PACKAGE to target machine"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 100
fi

#
# Start Redis on the target machine
#
LogMsg "Install Redis on remote machine"
#unzip the package on target machine
ssh root@${REDIS_HOST_IP} "tar -xzf /root/${REDIS_PACKAGE} "
#compile redis on target machine
ssh root@${REDIS_HOST_IP} "cd /root/${rootDir}; make"
#run redis server on CPU0
ssh root@${REDIS_HOST_IP} "echo 'taskset 0x00000001 /root/${rootDir}/src/redis-server' | at now"

if [ $? -ne 0 ]; then
    msg="Error: Unable to start redis-server on the Target machine"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 120
fi

#
# Give the server a few seconds to initialize
#
LogMsg "Wait 10 seconds so the server can initialize"
sleep 10

#
# Run redis and save the output to a logfile
#
LogMsg "Starting redis benchmark on client"
cd src/

echo "Start running: ./redis-benchmark -h ${REDIS_HOST_IP} -p ${REDIS_HOST_PORT} -c ${REDIS_CLIENTS} -r ${REDIS_RANDOM_KEY_SCOPE} -d ${REDIS_DATA_SIZE} -t ${REDIS_TESTSUITES} -n ${REDIS_NUMBER_REQUESTS}"
./redis-benchmark -h ${REDIS_HOST_IP} -p ${REDIS_HOST_PORT} -c ${REDIS_CLIENTS} -r ${REDIS_RANDOM_KEY_SCOPE} -d ${REDIS_DATA_SIZE} -t ${REDIS_TESTSUITES} -n ${REDIS_NUMBER_REQUESTS} > ~/redis.log
if [ $? -ne 0 ]; then
    msg="Error: Unable to start redis benchmark on the client"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 200
fi

#
# If we made it here, everything worked.
# Indicate success
#
LogMsg "Test completed successfully"
UpdateTestState $ICA_TESTCOMPLETED

exit 0

