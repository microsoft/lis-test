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

# Run iPerf as an ICA test case

ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"

CONSTANTS_FILE="constants.sh"

DEBUG_LEVEL=3


dbgprint()
{
    if [ $1 -le $DEBUG_LEVEL ]; then
        echo "$2"
    fi
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}


#
# Create the state.txt file so ICA knows we are running
#
UpdateTestState $ICA_TESTRUNNING

#
# Source the constants file from ICA
#
dbgprint 3 "Sourcing constants.sh"
if [ -e  ~/${CONSTANTS_FILE} ]; then
        . ~/${CONSTANTS_FILE}
else
    echo "ERROR: Unable to source the ${CONSTANTS_FILE} file"
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

#
# Make sure the variables we need are defined
#
dbgprint 3 "Checking definitions in constants.sh"
if [ ! ${REPOSITORY_SERVER} ]; then
    echo "ERRROR: the variable REPOSITORY_SERVER is not defined"
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

if [ ! ${REPOSITORY_PATH} ]; then
    echo "ERROR: the variable REPOSITORY_PATH is not defined"
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

if [ ! ${TARBALL} ]; then
    echo "ERROR: the variable TARBALL is not defined"
    UpdateTestState $ICA_TESTABORTED
    exit 40
fi

if [ ! ${ROOT_DIR} ]; then
    echo "ERROR: the variable ROOT_DIR is not defined"
    UpdateTestState $ICA_TESTABORTED
    exit 50
fi

if [ ! ${IPERF_SERVER} ]; then
    echo "ERROR: the variable IPERF_SERVER is not defined"
    UpdateTEstState $ICA_TESTABORTED
    exit 60
fi

#
# Download the iPerf tarball
# - first, remove any old root directories and tar files
#
dbgprint 3 "Cleaning up any old files laying around"
if [ -e ${ROOT_DIR} ]; then
    rm -rf ${ROOT_DIR}
fi

if [ -e ${TARBALL} ]; then
    rm -f ${TARBALL}
fi

dbgprint 3 "Downloading iperf tar file"
tarFile="${REPOSITORY_PATH}/${TARBALL}"
dbgprint 3 "tarFile = ${tarFile}"

dbgprint 3 "scp -i .ssh/ica_repos_id_rsa root@${REPOSITORY_SERVER}:${tarFile}"
scp -i .ssh/ica_repos_id_rsa root@${REPOSITORY_SERVER}:${tarFile} .
if [ $? -eq 1 ]; then
    echo "ERROR: unable to copy ${tarFile} from repository server"
    UpdateTestState $ICA_TESTABORTED
    exit 70
fi

#
# Make sure the iPerf tar file was copied down
#
dbgprint 3 "Checking tarball"
if [ ! -e ${TARBALL} ]; then
    echo "ERROR: the tar file ${TARBALL} does not exist"
    UpdateTestState $ICA_TESTABORTED
    exit 80
fi

dbgprint 3 "Extracting tarball"
tar -xzf ${TARBALL}
if [ $? -ne 0 ]; then
    echo "ERROR: unable to extract files from the tarball"
    UpdateTestState $ICA_TESTABORTED
    exit 90
fi

if [ ! -e ${ROOTDIR} ]; then
    echo "ERROR: the root directory ${ROOTDIR} was not created"
    UpdateTestState $ICA_TESTABORTED
    exit 100
fi

#
# Build iPerf
#
cd ${ROOT_DIR}

./configure

make

dbgprint 5 "Copying src/iperf to ~"
rm -f ~/iperf
cp src/iperf ~

cd ~

#
# Run a test where we write data to the IPERF_SERVER
#
rm -f server.out
rm -f write.out
rm -f read.out

dbgprint 3 "Starting iperf server on ${IPERF_SERVER}"
dbgprint 5 "ssh -i .ssh/sles11_id_rsa root@${IPERF_SERVER} bin/iperf -s -P 10 > server.out &"
ssh -i .ssh/sles11_id_rsa root@${IPERF_SERVER} bin/iperf -s -P 10 > server.out &
sleep 5

dbgprint 5 "~/iperf -c ${IPERF_SERVER} -P 10 > write.out"
~/iperf -c ${IPERF_SERVER} -P 10 > write.out

ssh -i .ssh/sles11_id_rsa root@${IPERF_SERVER} killall iperf 2&> /dev/null


#
# Now reverse the roles - we read data from the IPERF_SERVER
#
myIP=`ifconfig eth0 | grep 'inet addr' | grep -v 127.0.0.1 | cut -d: -f2 | cut -d ' ' -f1`
#dbgprint 3 "myIP = ${myIP}"

dbgprint 3 "Starting iperf server on localhost"
~/iperf -s -P 10 > server.out &
sleep 5

dbgprint 3 "Starting iperf client on ${IPERF_SERVER}"
dbgprint 5 "ssh -i .ssh/sles11_id_rsa root@${IPERF_SERVER} bin/iperf -c ${myIP} -p 10 > read.out"
ssh -i .ssh/sles11_id_rsa root@${IPERF_SERVER} bin/iperf -c ${myIP} -P 10 > read.out

echo -e "\r\n\r\n\r\n"
echo "Write results"
cat write.out

echo -e "\r\n\r\n\r\n"
echo "Read results"
cat read.out

echo -e "\r\nSetting test state to TestCompleted"
UpdateTestState $TestCompleted
exit 0

