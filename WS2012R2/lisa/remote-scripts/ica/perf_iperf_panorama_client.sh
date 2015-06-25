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
# perf_iperf_panorama_client.sh
#
# Description:
#     For the test to run you have to place the iperf tool package in the
#     Tools folder under lisa.
#
# Parameters:
#     IPERF_PACKAGE: the iperf3 tool package
#     IPERF3_SERVER_IP: the ipv4 address of the server
#     INDIVIDUAL_TEST_DURATION: the test duration of each iperf3 test
#     CONNECTIONS_PER_IPERF3: how many iPerf connections will be created by iPerf3 client to a single iperf3 server
#     SERVER_OS_USERNAME: the user name used to copy test signal file to server side
#     TEST_SIGNAL_FILE: the signal file send by client side to sync up the number of test connections
#     TEST_RUN_LOG_FOLDER: the log folder name. sar log and top log will be saved in this folder for further analysis
#     IPERF3_TEST_CONNECTION_POOL: the list of iperf3 connections need to be tested
#
#######################################################################

ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"

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

if [ "${IPERF3_SERVER_IP:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the IPERF3_SERVER_IP test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${INDIVIDUAL_TEST_DURATION:="UNDEFINED"}" = "UNDEFINED" ]; then
    INDIVIDUAL_TEST_DURATION=600
    msg="Error: the INDIVIDUAL_TEST_DURATION test parameter is missing and the default value will be used: ${INDIVIDUAL_TEST_DURATION}."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ "${CONNECTIONS_PER_IPERF3:="UNDEFINED"}" = "UNDEFINED" ]; then
    CONNECTIONS_PER_IPERF3=4
    msg="Error: the CONNECTIONS_PER_IPERF3 test parameter is missing and the default value will be used: ${CONNECTIONS_PER_IPERF3}."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ "${SERVER_OS_USERNAME:="UNDEFINED"}" = "UNDEFINED" ]; then
    SERVER_OS_USERNAME="root"
    msg="Warning: the SERVER_OS_USERNAME test parameter is missing and the default value will be used: ${SERVER_OS_USERNAME}."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ "${TEST_SIGNAL_FILE:="UNDEFINED"}" = "UNDEFINED" ]; then
    TEST_SIGNAL_FILE="~/iperf3.test.sig"
    msg="Warning: the TEST_SIGNAL_FILE test parameter is missing and the default value will be used: ${TEST_SIGNAL_FILE}."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ "${TEST_RUN_LOG_FOLDER:="UNDEFINED"}" = "UNDEFINED" ]; then
    TEST_RUN_LOG_FOLDER="iperf3-client-logs"
    msg="Warning: the TEST_RUN_LOG_FOLDER test parameter is is missing and the default value will be used:${TEST_RUN_LOG_FOLDER}"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ "${IPERF3_TEST_CONNECTION_POOL:="UNDEFINED"}" = "UNDEFINED" ]; then
    IPERF3_TEST_CONNECTION_POOL=(1 2 4 8 16 32 64 128 256 512 1024 2000 3000 6000)
    msg="Warning: the IPERF3_TEST_CONNECTION_POOL test parameter is is missing and the default value will be used:${IPERF3_TEST_CONNECTION_POOL}"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

echo "iPerf package name                  = ${IPERF_PACKAGE}"
echo "iPerf server ip                     = ${IPERF3_SERVER_IP}"
echo "individual test duration (sec)      = ${INDIVIDUAL_TEST_DURATION}"
echo "connections per iperf3              = ${CONNECTIONS_PER_IPERF3}"
echo "user name on server                 = ${SERVER_OS_USERNAME}"
echo "test signal file                    = ${TEST_SIGNAL_FILE}"
echo "test run log folder                 = ${TEST_RUN_LOG_FOLDER}"
echo "iperf3 test connection pool         = ${IPERF3_TEST_CONNECTION_POOL}"

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
# Install gcc which is required to build iperf3
#
zypper --non-interactive install gcc

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

# go back to test root folder
cd ~

# Make all bash scripts run-able
dos2unix ~/*.sh
chmod 755 ~/*.sh

#
# Copy server side scripts and trigger server side scripts
#
LogMsg "Copy files to server: ${IPERF3_SERVER_IP}"
scp ~/perf_iperf_panorama_server.sh ${SERVER_OS_USERNAME}@[${IPERF3_SERVER_IP}]:
if [ $? -ne 0 ]; then
    msg="Error: Unable to copy test scripts to target server machine: ${IPERF3_SERVER_IP}. scp command failed."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 120
fi
scp ~/${IPERF_PACKAGE} ${SERVER_OS_USERNAME}@[${IPERF3_SERVER_IP}]:
scp ~/constants.sh ${SERVER_OS_USERNAME}@[${IPERF3_SERVER_IP}]:

#
# Start iPerf in server mode on the Target server side
#
LogMsg "Starting iPerf in server mode on ${IPERF3_SERVER_IP}"

ssh ${SERVER_OS_USERNAME}@${IPERF3_SERVER_IP} "echo '~/perf_iperf_panorama_server.sh' | at now"
if [ $? -ne 0 ]; then
    msg="Error: Unable to start iPerf3 server scripts on the target server machine"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 130
fi

#
# Wait for server ready
#
wait_for_server=600
server_state_file=serverstate.txt
while [ $wait_for_server -gt 0 ]; do
    # Try to copy and understand server state
    scp ${SERVER_OS_USERNAME}@[${IPERF3_SERVER_IP}]:~/state.txt ~/${server_state_file}

    if [ -f ~/${server_state_file} ];
    then
        server_state=$(head -n 1 ~/${server_state_file})
        echo $server_state
        rm -rf ~/${server_state_file}
        if [ "$server_state" == "iPerf3Running" ];
        then
            break
        fi
    fi
    sleep 5
    wait_for_server=$(($wait_for_server - 5))
done

if [ $wait_for_server -eq 0 ] ;
then
    msg="Error: iperf3 server script has been triggered but not iperf3 are not in running state within ${wait_for_server} seconds."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 135
else
    LogMsg "iPerf3 servers are ready."
fi
#
# Start iPerf3 client instances
#
LogMsg "Starting iPerf3 in client mode"

i=0
mkdir ./${TEST_RUN_LOG_FOLDER}
while [ "x${IPERF3_TEST_CONNECTION_POOL[$i]}" != "x" ]
do
    port=8001
    echo "================================================="
    echo "Running Test: ${IPERF3_TEST_CONNECTION_POOL[$i]}"
    echo "================================================="

    touch ${TEST_SIGNAL_FILE}
    echo ${threads[$i]} > ${TEST_SIGNAL_FILE}
    scp ${TEST_SIGNAL_FILE} $server_username@${IPERF3_SERVER_IP}:
    sleep 7

    number_of_connections=${IPERF3_TEST_CONNECTION_POOL[$i]}
    bash ./perf_capturer.sh $INDIVIDUAL_TEST_DURATION ${TEST_RUN_LOG_FOLDER}/$number_of_connections &

    rm -rf the_generated_client.sh
    echo "./perf_run_parallelcommands.sh " > the_generated_client.sh

    while [ $number_of_connections -gt $CONNECTIONS_PER_IPERF3 ]; do
        number_of_connections=$(($number_of_connections-$CONNECTIONS_PER_IPERF3))
        echo " \"/root/${rootDir}/src/iperf3 -c $IPERF3_SERVER_IP -p $port -P $CONNECTIONS_PER_IPERF3 -t $INDIVIDUAL_TEST_DURATION > /dev/null \" " >> the_generated_client.sh
        port=$(($port + 1))
    done

    if [ $number_of_connections -gt 0 ]
    then
        echo " \"/root/${rootDir}/src/iperf3 -c $IPERF3_SERVER_IP -p $port -P $number_of_connections  -t $INDIVIDUAL_TEST_DURATION > /dev/null \" " >> the_generated_client.sh
    fi
    
    sed -i ':a;N;$!ba;s/\n/ /g'  ./the_generated_client.sh
    chmod 755 the_generated_client.sh

    cat ./the_generated_client.sh
    ./the_generated_client.sh > /dev/null 

    i=$(($i + 1))

    echo "Clients test just finished. Sleep 10 sec for next test..."
    sleep 10
done

exit 0

