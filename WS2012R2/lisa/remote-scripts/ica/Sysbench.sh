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

#######################################################################
# Adds a timestamp to the log file
#######################################################################
function LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1}
}

#######################################################################
# Keeps track of the state of the test
#######################################################################
function UpdateTestState()
{
    echo $1 > ~/state.txt
}

LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

UpdateSummary()
{
 if [ -f "$__LIS_SUMMARY_FILE" ]; then
  if [ -w "$__LIS_SUMMARY_FILE" ]; then
   echo "$1" >> "$__LIS_SUMMARY_FILE"
  else
   LogMsg "Warning: summary file $__LIS_SUMMARY_FILE exists and is a normal file, but is not writable"
   chmod u+w "$__LIS_SUMMARY_FILE" && echo "$1" >> "$__LIS_SUMMARY_FILE" || LogMsg "Warning: unable to make $__LIS_SUMMARY_FILE writeable"
   return 1
  fi
 else
  LogMsg "Warning: summary file $__LIS_SUMMARY_FILE either does not exist or is not a regular file. Trying to create it..."
  echo "$1" >> "$__LIS_SUMMARY_FILE" || return 2
 fi

 return 0
}

function UpdateSummary()
{
    echo $1 >> ~/summary.log
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

pushd $ROOT_DIR
LogMsg "Cloning sysbench"
git clone https://github.com/akopytov/sysbench.git
if [ $? -gt 0 ]; then
    LogMsg "Failed to cloning sysbench."
    UpdateSummary "Compiling sysbench failed."
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi
pushd "$ROOT_DIR/sysbench"
# Create the state.txt file so LISA knows we are running
UpdateTestState $ICA_TESTRUNNING

# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi
LogMsg "This script tests sysbench on VM."

if is_fedora ; then
    # Installing dependencies of sysbench on fedora.
    # yum install -y mysql-devel
    
    # mysql-devel should not be a requirement if we compile without mysql support
    #wget ftp://mirror.switch.ch/pool/4/mirror/mysql/Downloads/MySQL-5.6/MySQL-devel-5.6.24-1.el7.x86_64.rpm
    #rpm -iv MySQL-devel-5.6.24-1.el7.x86_64.rpm

    bash ./autogen.sh
    bash ./configure --without-mysql
    make
    make install
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Unable to install sysbench. Aborting..."
        UpdateTestState $ICA_TESTABORTED
        exit 10
    fi
        LogMsg "Sysbench installed successfully."
    fi
 elif is_ubuntu ; then
     # Installing sysbench on ubuntu
    apt-get install -y sysbench
    if [ $? -ne 0 ]; then
             LogMsg "ERROR: Unable to install sysbench. Aborting..."
             UpdateTestState $ICA_TESTABORTED
             exit 10
    fi
        LogMsg "Sysbench installed successfully!"

 elif is_suse ; then
        bash ./autogen.sh
        bash ./configure --without-mysql
        make
        make install
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Unable to install sysbench. Aborting..."
            UpdateTestState $ICA_TESTABORTED
            exit 10
        fi
        LogMsg "Sysbench installed successfully."
    fi
 #else # other distro's
  #   LogMsg "Distro not suported. Aborting"
  #   UpdateTestState $ICA_TESTABORTED
  #   exit 10
# fi
 FILEIO_PASS=-1
 CPU_PASS=-1

function cputest ()
{
    LogMsg "Creating cpu.log."
    sysbench --test=cpu --num-threads=1 run > /root/cpu.log
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Unable to exectute sysbench CPU. Aborting..."
        UpdateTestState $ICA_TESTABORTED
    fi

    PASS_VALUE_CPU=`cat /root/cpu.log |awk '/approx./ {print $2;}'`
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Cannot find cpu.log."
        UpdateTestState $ICA_TESTABORTED
    fi

    RESULT_VALUE=$((PASS_VALUE_CPU+0))
    if  [ $RESULT_VALUE -gt 80 ]; then
        CPU_PASS=0
        LogMsg "CPU Test passed. "
        UpdateSummary "CPU Test passed."

    fi
    LogMsg "`cat /root/cpu.log`"
    return "$CPU_PASS"
}

cputest

function fileio ()
 {
    sysbench --test=fileio --num-threads=1 --file-test-mode=$1 run > /root/$1.log
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Unable to execute sysbench fileio mode $1. Aborting..."
        UpdateTestState $ICA_TESTFAILED
    fi

    PASS_VALUE_FILEIO=`cat /root/$1.log |awk '/approx./ {print $2;}'`
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Cannot find $1.log."
        UpdateTestState $ICA_TESTFAILED
    fi

    RESULT_VALUE_FILEIO=$((PASS_VALUE_FILEIO+0))
    if  [ $RESULT_VALUE_FILEIO -gt 80 ]; then
        FILEIO_PASS=0
        LogMsg "Fileio Test -$1- passed with approx. $RESULT_VALUE_FILEIO percentils."
        UpdateSummary "Fileio Test -$1- passed with approx. $RESULT_VALUE_FILEIO percentils."

    fi

    LogMsg "`cat /root/$1.log`"
    cat /root/$1.log >> /root/fileio.log
    rm /root/$1.log
    return "$FILEIO_PASS"
 }

LogMsg " Testing fileio. Writing to fileio.log."
for test_item in ${TEST_FILE[*]}
do
    fileio $test_item
    if [ $FILEIO_PASS -eq -1 ]; then
        LogMsg "ERROR: Test mode $test_item failed "
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
