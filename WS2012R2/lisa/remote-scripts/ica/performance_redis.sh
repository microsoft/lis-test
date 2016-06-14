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
#     For the test to run you have to place the REDIS_PACKAGE.tar.gz archive in the
#     Tools folder under lisa.
#
# Parameters:
#      REDIS_PACKAGE:            the redis tool package 
#      REDIS_HOST_IP:            the ip address of the machine runs Redis server
#      REDIS_HOST_PORT:          the ip port of the machine runs Redis server
#      REDIS_CLIENTS:            number of parallel connections 
#      REDIS_RANDOM_KEY_SCOPE:   use random keys for SET/GET/INCR, random values for SADD
#      REDIS_DATA_SIZE:          data size of SET/GET value in bytes 
#      REDIS_TESTSUITES:         only run the comma-separated list of tests. The test names are the same as the ones produced as output.
#      REDIS_NUMBER_REQUESTS:    total number of requests
#      SERVER_SSHKEY:            key for server
#      STATIC_IP:                static ip of the Redis client machine
#      NETMASK:                  netmask of client private network
#      VM2NAME:                  name of the machine running Redis server
#      VM2SERVER:                host of the machine running Redis server
#      MAC:                      MAC address of private network of machine running Redis server
#      TEST_PIPELINE_COLLECTION: collection of pipeline values for the tests
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

if [ "${SERVER_SSHKEY:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="WARNING: the SERVER_SSHKEY test parameter is undefined"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ "${STATIC_IP:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the STATIC_IP test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 30
fi

#
# Configure Static interfaces
#
dos2unix ./NET_set_static_ip.sh
chmod +x ./NET_set_static_ip.sh
./NET_set_static_ip.sh
if [ $? -ne 0 ]; then 
    exit 1
fi
ssh -i /root/.ssh/${SERVER_SSHKEY} -o StrictHostKeyChecking=no root@${STATIC_IP2} "exit"
scp -i /root/.ssh/${SERVER_SSHKEY} /root/NET_set_static_ip.sh root@[${STATIC_IP2}]:/root/
scp -i /root/.ssh/${SERVER_SSHKEY} /root/utils.sh root@[${STATIC_IP2}]:/root/
ssh -i /root/.ssh/${SERVER_SSHKEY} root@${STATIC_IP2} "echo 'STATIC_IP=${REDIS_HOST_IP}' >> /root/constants.sh"
ssh -i /root/.ssh/${SERVER_SSHKEY} root@${STATIC_IP2} "echo 'ipv4=${STATIC_IP2}' >> /root/constants.sh"
ssh -i /root/.ssh/${SERVER_SSHKEY} root@${STATIC_IP2} "dos2unix ./NET_set_static_ip.sh; chmod +x ./NET_set_static_ip.sh; ./NET_set_static_ip.sh"
if [ $? -ne 0 ]; then
    msg="Error: Unable set static ip on vm2"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 40
fi
msg="Successfully assigned ip to vm2"
LogMsg "${msg}"
echo "${msg}" >> ~/summary.log
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
make install
if [ $? -ne 0 ]; then
    msg="Error: make install redis tool failed"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 60
fi
msg="Successfully installed redis on client"
LogMsg "${msg}"
echo "${msg}" >> ~/summary.log

#
# Copy the redis package to the REDIS_HOST_IP machine
#
LogMsg "Copying Redis package to target machine"
scp  -i /root/.ssh/${SERVER_SSHKEY} -o StrictHostKeyChecking=no /root/${REDIS_PACKAGE} root@${REDIS_HOST_IP}:/root/
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
pkill -f redis-benchmark
ssh -i /root/.ssh/${SERVER_SSHKEY} root@${REDIS_HOST_IP} pkill -f redis-server > /dev/null
LogMsg "Install Redis on remote machine"
#unzip the package on target machine
ssh -i /root/.ssh/${SERVER_SSHKEY} root@${REDIS_HOST_IP} "tar -xzf /root/${REDIS_PACKAGE} "
#compile redis on target machine
ssh -i /root/.ssh/${SERVER_SSHKEY} root@${REDIS_HOST_IP} "cd /root/${rootDir}; make; make install"
#run redis server on CPU0
#"echo 'taskset 0x00000001 /root/${rootDir}/src/redis-server' | at now"
#ssh -i /root/.ssh/${SERVER_SSHKEY} root@${REDIS_HOST_IP} "taskset -c 0 /root/${rootDir}/src/redis-server >> /dev/null &"
if [ $? -ne 0 ]; then
    msg="Error: Unable to install REDIS on target machine"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 100
fi

msg="Successfully installed redis on server"
LogMsg "${msg}"
echo "${msg}" >> ~/summary.log
log_folder="/root/${rootDir}/logs"

ssh -i /root/.ssh/${SERVER_SSHKEY} root@${REDIS_HOST_IP} mkdir -p $log_folder
mkdir -p $log_folder

pkill -f redis-benchmark
ssh -i /root/.ssh/${SERVER_SSHKEY} root@${REDIS_HOST_IP} pkill -f redis-server  >> /dev/null 
cd src/
t=0

while [ "x${TEST_PIPELINE_COLLECTION[$t]}" != "x" ]
do
    
    pipelines=${TEST_PIPELINE_COLLECTION[$t]}
    msg="TEST: $pipelines pipelines"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    echo "${msg}" >> ~/redis.log

    # prepare running redis-server
    ssh -i /root/.ssh/${SERVER_SSHKEY} root@${REDIS_HOST_IP} mkdir -p                   $log_folder/$pipelines
    ssh -i /root/.ssh/${SERVER_SSHKEY} root@${REDIS_HOST_IP} "sar -n DEV 1 900   2>&1 > $log_folder/$pipelines/$pipelines.sar.netio.log " &
    ssh -i /root/.ssh/${SERVER_SSHKEY} root@${REDIS_HOST_IP} "iostat -x -d 1 900 2>&1 > $log_folder/$pipelines/$pipelines.iostat.diskio.log " &
    ssh -i /root/.ssh/${SERVER_SSHKEY} root@${REDIS_HOST_IP} "vmstat 1 900       2>&1 > $log_folder/$pipelines/$pipelines.vmstat.memory.cpu.log " &
    
    # start redis server
    ssh -i /root/.ssh/${SERVER_SSHKEY} root@${REDIS_HOST_IP} "/root/${rootDir}/src/redis-server >> /dev/null &"
    if [ $? -ne 0 ]; then
        msg="Error: Unable to start redis-server on the Target machine"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 120
    fi

    # prepare running redis-benchmark
    mkdir -p                   $log_folder/$pipelines
    sar -n DEV 1 900   2>&1  > $log_folder/$pipelines/$pipelines.sar.netio.log &         >> /dev/null        
    iostat -x -d 1 900 2>&1  > $log_folder/$pipelines/$pipelines.iostat.diskio.log &     >> /dev/null
    vmstat 1 900       2>&1  > $log_folder/$pipelines/$pipelines.vmstat.memory.cpu.log & >> /dev/null

    #start running the redis-benchmark on client
    sleep 20
    ./redis-benchmark -h ${REDIS_HOST_IP} -c ${REDIS_CLIENTS} -P $pipelines -t ${REDIS_TESTSUITES} -d ${REDIS_DATA_SIZE} -n ${REDIS_NUMBER_REQUESTS} >> ~/redis.log
    if [ $? -ne 0 ]; then
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    #cleanup redis-server
    ssh -i /root/.ssh/${SERVER_SSHKEY} root@${REDIS_HOST_IP} pkill -f sar           >> /dev/null
    ssh -i /root/.ssh/${SERVER_SSHKEY} root@${REDIS_HOST_IP} pkill -f iostat        >> /dev/null
    ssh -i /root/.ssh/${SERVER_SSHKEY} root@${REDIS_HOST_IP} pkill -f vmstat        >> /dev/null 
    ssh -i /root/.ssh/${SERVER_SSHKEY} root@${REDIS_HOST_IP} pkill -f redis-server  >> /dev/null   

    #cleanup redis-benchmark
    pkill -f sar             >> /dev/null
    pkill -f iostat          >> /dev/null
    pkill -f vmstat          >> /dev/null
    pkill -f redis-benchmark >> /dev/null

    LogMsg "sleep 60 seconds for next test"
    sleep 60
    t=$(($t + 1))
done

#
# If we made it here, everything worked.
# Indicate success
#
ssh -i /root/.ssh/${SERVER_SSHKEY} root@${REDIS_HOST_IP} "shutdown now"
LogMsg "Test completed successfully"
UpdateTestState $ICA_TESTCOMPLETED

exit 0
