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

ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"

#######################################################################
# Adds a timestamp to the log file
#######################################################################
LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}
}

#######################################################################
# Updates the summary.log file
#######################################################################
UpdateSummary()
{
    echo $1 >> ~/summary.log
}

#######################################################################
# Keeps track of the state of the test
#######################################################################
UpdateTestState()
{
    echo $1 > ~/state.txt
}

#######################################################################
#
# Main script body
#
#######################################################################

# Create the state.txt file so ICA knows we are running
UpdateTestState $ICA_TESTRUNNING

# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

# Check if file exists on VM
if ! [ -e /root/testfile-* ]; then
    LogMsg "ERROR: Testfile is not present on the VM"
    UpdateTestState "TestAborted"
    exit 1
else
    LogMsg "Testfile is present on the VM"
fi

# Get MD5 checksum 
chksum=$(openssl md5 testfile-*)
if [ $? -ne 0 ]; then 
	LogMsg "ERROR: Cannot get MD5 checksum"
    UpdateTestState "TestAborted"
    exit 1
else
	chksum=$(echo "$chksum" | awk -F'= ' '{print $NF}')
	LogMsg "MD5 checksum on Guest VM: $chksum"
    UpdateSummary "MD5 checksum on Guest VM: $chksum"	
fi

UpdateTestState $ICA_TESTCOMPLETED



