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
#
# Description:
#       This script installs and runs Sysbench tests on a guest VM
#
#       Steps:
#       1. Installs dependencies
#       2. Compiles and installs sysbench
#       3. Runs sysbench
#       4. Collects results
#
#       No optional parameters needed
#
########################################################################
ICA_TESTRUNNING="TestRunning"                                      # The test is running
ICA_TESTCOMPLETED="TestCompleted"                                  # The test completed successfully
ICA_TESTABORTED="TestAborted"                                      # Error during setup of test
ICA_TESTFAILED="TestFailed"                                        # Error while performing the test

CONSTANTS_FILE="constants.sh"
ROOT_DIR="/root"

# For changing Sysbench version only the following parameter has to be changed
Sysbench_Version=1.0.9

#######################################################################
# Keeps track of the state of the test
#######################################################################
function UpdateTestState()
{
    echo $1 > ~/state.txt
}

function cputest ()
{
    LogMsg "Creating cpu.log and starting test."
    sysbench cpu --num-threads=1 run > /root/cpu.log
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Unable to execute sysbench CPU. Aborting..."
        UpdateTestState $ICA_TESTABORTED
    fi

    PASS_VALUE_CPU=`cat /root/cpu.log |awk '/total time: / {print $3;}'`
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Cannot find cpu.log."
        UpdateTestState $ICA_TESTABORTED
    fi

    RESULT_VALUE=$(echo ${PASS_VALUE_CPU} | head -c2)
    if  [ $RESULT_VALUE -lt 15 ]; then
        CPU_PASS=0
        LogMsg "CPU Test passed. "
        UpdateSummary "CPU Test passed."
    fi

    LogMsg "`cat /root/cpu.log`"
    return "$CPU_PASS"
}

function fileio ()
{
    sysbench fileio --num-threads=1 --file-test-mode=$1 prepare > /dev/null 2>&1
    LogMsg "Preparing files to test $1..."
    sysbench fileio --num-threads=1 --file-test-mode=$1 run > /root/$1.log
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Unable to execute sysbench fileio mode $1. Aborting..."
        UpdateTestState $ICA_TESTFAILED
    else
        LogMsg "Running $1 tests..."
    fi

    PASS_VALUE_FILEIO=`cat /root/$1.log |awk '/sum/ {print $2;}' | cut -d. -f1`
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Cannot find $1.log."
        UpdateTestState $ICA_TESTFAILED
    fi

    if  [ $PASS_VALUE_FILEIO -lt 12000 ]; then
        FILEIO_PASS=0
        LogMsg "Fileio Test -$1- passed with latency sum: $PASS_VALUE_FILEIO."
        UpdateSummary "Fileio Test -$1- passed with latency sum: $PASS_VALUE_FILEIO."
    else
        LogMsg "ERROR: Latency sum value is $PASS_VALUE_FILEIO. Test failed."
    fi

    sysbench fileio --num-threads=1 --file-test-mode=$1 cleanup
    LogMsg "Cleaning up $1 test files."

    LogMsg "`cat /root/$1.log`"
    cat /root/$1.log >> /root/fileio.log
    rm /root/$1.log
    return "$FILEIO_PASS"
}
#######################################################################
#
# Main script body
#
#######################################################################
# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
    UpdateSummary "Covers: $TC_COVERED"
else
    LogMsg "Error: no ${CONSTANTS_FILE} file"
    UpdateSummary "Error: no ${CONSTANTS_FILE} file"
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

# Download sysbench
pushd $ROOT_DIR
LogMsg "Cloning sysbench"
wget https://github.com/akopytov/sysbench/archive/$Sysbench_Version.zip
if [ $? -gt 0 ]; then
    LogMsg "Failed to download sysbench."
    UpdateSummary "Failed to download sysbench."
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

unzip $Sysbench_Version.zip
if [ $? -gt 0 ]; then
    LogMsg "Failed to unzip sysbench."
    UpdateSummary "Failed to unzip sysbench."
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

if is_fedora ; then
    # Installing dependencies of sysbench on fedora.
    # yum install -y mysql-devel
    
    # mysql-devel should not be a requirement if we compile without mysql support
    #wget ftp://mirror.switch.ch/pool/4/mirror/mysql/Downloads/MySQL-5.6/MySQL-devel-5.6.24-1.el7.x86_64.rpm
    #rpm -iv MySQL-devel-5.6.24-1.el7.x86_64.rpm

    pushd $ROOT_DIR
    mkdir autoconf
    cd autoconf
    wget http://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz
    tar xvfvz autoconf-2.69.tar.gz
    cd autoconf-2.69
    ./configure
    make
    make install

    yum install devtoolset-2-binutils -y
    yum install automake -y
    yum install libtool -y
    yum install vim -y

    pushd "$ROOT_DIR/sysbench-$Sysbench_Version"
    bash ./autogen.sh
    bash ./configure --without-mysql
    make
    make install
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Unable to install sysbench. Aborting..."
        UpdateSummary "ERROR: Unable to install sysbench. Aborting..."
        UpdateTestState $ICA_TESTABORTED
        exit 10
    fi
    LogMsg "Sysbench installed successfully."

elif is_ubuntu ; then
    apt-get install automake -y
    apt-get install libtool -y
    apt-get install pkg-config -y

    pushd "$ROOT_DIR/sysbench-$Sysbench_Version"
    bash ./autogen.sh
    bash ./configure --without-mysql
    make
    make install
    sysbench --help
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Unable to install sysbench. Aborting..."
        UpdateSummary "ERROR: Unable to install sysbench. Aborting..."
        UpdateTestState $ICA_TESTABORTED
        exit 10
    fi
    LogMsg "Sysbench installed successfully!"

elif is_suse ; then
    pushd "$ROOT_DIR/sysbench-$Sysbench_Version"
    bash ./autogen.sh
    bash ./configure --without-mysql
    make
    make install
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Unable to install sysbench. Aborting..."
        UpdateSummary "ERROR: Unable to install sysbench. Aborting..."
        UpdateTestState $ICA_TESTABORTED
        exit 10
    fi
    LogMsg "Sysbench installed successfully."
fi

FILEIO_PASS=-1
CPU_PASS=-1

cputest

LogMsg "Testing fileio. Writing to fileio.log."
for test_item in ${TEST_FILE[*]}
do
    fileio $test_item
    if [ $FILEIO_PASS -eq -1 ]; then
        LogMsg "ERROR: Test mode $test_item failed "
        UpdateSummary "ERROR: Test mode $test_item failed "
        UpdateTestState $ICA_TESTFAILED
    fi
done
UpdateSummary "Fileio tests passed."

if [ "$FILEIO_PASS" = "$CPU_PASS" ]; then
    UpdateSummary "All tests completed."
    LogMsg "All tests completed."
    UpdateTestState $ICA_TESTCOMPLETED
else
    LogMsg "Test Failed."
    UpdateTestState $ICA_TESTFAILED
fi
