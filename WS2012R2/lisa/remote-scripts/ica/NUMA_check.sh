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
#	This script compares the host provided Numa Nodes values
#	with the numbers of CPUs and ones detected on a Linux guest VM.
#	To pass test parameters into test cases, the host will create
#	a file named constants.sh. This file contains one or more
#	variable definition.
#
################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

UpdateTestState() {
    echo $1 > $HOME/state.txt
}

UpdateSummary() {
	# To add the timestamp to the log file
    echo `date "+%a %b %d %T %Y"` : ${1} >> ~/summary.log
}

cd ~
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

UpdateTestState $ICA_TESTRUNNING

if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
else
    LogMsg "ERROR: Unable to source the constants file!"
    UpdateSummary "ERROR: Unable to source the constants file!"
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    LogMsg "Error: unable to source utils.sh!"
    UpdateSummary "Error: unable to source utils.sh!"
    UpdateTestState $ICA_TESTABORTED
    exit 1
}

# Source constants file and initialize most common variables
UtilsInit

# Get distro
GetDistro

case $DISTRO in
    redhat* | centos*)
       numactl -s
        if [ $? -ne 0 ]; then
             yum -y install numactl
                 if [ $? -ne 0 ]; then
                    LogMsg "Error: numactl cannot be installed.."
                    UpdateSummary "Error: numactl cannot be installed."
                    UpdateTestState $ICA_TESTABORTED
                    exit 1
                fi
        fi
    ;;
   ubuntu*)
        numactl -s
            if [ $? -ne 0 ]; then
                 apt -y install numactl
                     if [ $? -ne 0 ]; then
                        LogMsg "Error: numactl cannot be installed."
                        UpdateSummary "Error: numactl cannot be installed."
                        UpdateTestState $ICA_TESTABORTED
                        exit 1
                    fi
            fi
    ;;
    suse*)
        numactl -s
            if [ $? -ne 0 ]; then
                 zypper -y install numactl
                     if [ $? -ne 0 ]; then
                        LogMsg "Error: numactl cannot be installed."
                        UpdateSummary "Error: numactl cannot be installed."
                        UpdateTestState $ICA_TESTABORTED
                        exit 1
                    fi
            fi
     ;;
     *)
        LogMsg "WARNING: Distro '${DISTRO}' not supported."
        UpdateSummary "WARNING: Distro '${DISTRO}' not supported."
    ;;
esac

#
# Check Numa nodes
#

NumaNodes=`numactl -H | grep cpu | wc -l`
LogMsg "Info : Detected NUMA nodes = ${NumaNodes}"
LogMsg "Info : Expected NUMA nodes = ${expected_number}"

#
# We do a matching on the values from host and guest
#
if ! [[ $NumaNodes = $expected_number ]]; then
	LogMsg "Error: Guest VM presented value $NumaNodes and the host has $expected_number . Test Failed!"
	UpdateSummary "Error: Guest VM presented value $NumaNodes and the host has $expected_number . Test Failed!"
    UpdateTestState $ICA_TESTFAILED
    exit 30
else
    LogMsg "Info: Numa nodes value is matching with the host. VM presented value is $NumaNodes"
    UpdateSummary "Info: Numa nodes value is matching with the host. VM presented value is $NumaNodes"
fi

#
# Check memory size configured in each NUMA node against max memory size
# configured in VM if MemSize test params configured.
#
if [ -n "$MaxMemSizeEachNode" ]; then
    LogMsg "Info: Max memory size of every node has been set to $MaxMemSizeEachNode MB"
    MemSizeArr=`numactl -H | grep size | awk '{ print $4 }'`
    for i in ${MemSizeArr}; do
        LogMsg "Info: Start checking memory size for node: $i MB"
        if [ $i -gt $MaxMemSizeEachNode ]; then
            LogMsg "Error: The maximum memory size of each NUMA node was $i , which is greater than $MaxMemSizeEachNode MB. Test Failed!"
        	UpdateSummary "Error: The maximum memory size of each NUMA node was $i , which is greater than $MaxMemSizeEachNode MB. Test Failed!"
            UpdateTestState $ICA_TESTFAILED
            exit 30
        fi
    done
    LogMsg "The memory size of all nodes are equal or less than $MaxMemSizeEachNode MB."
fi

#
# If we got here, all validations have been successful and no errors have occurred
#
LogMsg "NUMA check test Completed Successfully"
UpdateSummary "NUMA check test Completed Successfully"
UpdateTestState $ICA_TESTCOMPLETED
