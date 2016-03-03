#!/bin/bash

#####################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
#####################################################################
#
#   Description:
#       Verify the host injected KVP items are present in KVP pool 3.
#   Steps:
#       1.  Verify the KVP daemon is running.
#       2.  Verify kvp pool 3 contains KVP items.  Use the kvp_client tool to dump the contents of pool 3.
#       3.  Check for a subset of the following KVP items in the kvp_client output.
#       Note: Values will vary
#   Acceptance criteria
#       1.  The KVP pool 3 file has a size greater than zero.
#       2.  At least 11 (default value, can be changed in xml) items are present in pool 3.
#
#   Parameters required:
#       Pool
#       Items
#
#   Parameter explanation:
#       Pool - What pool to be checked - default value: 3
#       Items - Minimum number of Items present in KVP Pool 3 - default value: 11
#               Note: If there are fewer items in Kvp Pool 3 that the amount declared in "Items",
#                     the test will fail
#
##################################################################################################################


ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error while performing the test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}


UpdateTestState()
{
    echo $1 > ~/state.txt
}

#
# Create the state.txt file so ICA knows we are running
#
LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING



#
# Delete any summary.log files from a previous run
#
rm -f ~/summary.log
touch ~/summary.log

#
# Source the constants.sh file to pickup definitions from
# the ICA automation
#
if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

#
# Make sure constants.sh contains the variables we expect
#
if [ "${TC_COVERED:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter TC_COVERED is not defined in ${CONSTANTS_FILE}"
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

if [ "${Pool:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter Pool number is not defined in ${CONSTANTS_FILE}"
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 50
fi

if [ "${Items:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter Key is not defined in ${CONSTANTS_FILE}"
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

#
# Echo TCs we cover
#
echo "Covers ${TC_COVERED}" > ~/summary.log

#
# Make sure we have the kvp_client tool
#
if [ ! -e ~/kvp_client ]; then
    msg="Error: kvp_client tool is not on the system"
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 60
fi

chmod 755 ~/kvp_client
#
# Check if KVP pool 3 file has a size greater than zero
#

# Check if file exists on vm
ls -l /var/lib/hyperv/.kvp_pool_${Pool} 
if [ $? -ne 0 ]; then
    msg="Error: the kvp_pool_${Pool} is not present on the vm"
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 70
fi

poolFileSize=$(ls -l /var/lib/hyperv/.kvp_pool_${Pool} | awk '{print $5}')
if [ $poolFileSize -eq 0 ]; then
    msg="Error: the kvp_pool_${Pool} file size is zero"
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 70
fi

#
# Check the number of records in Pool 3. Below 11 entries (default value) the test will fail
#
echo "Items in pool ${Pool}"
~/kvp_client $Pool | sed 1,2d
if [ $? -ne 0 ]; then
    msg="Error: Could not list the KVP Items in pool ${Pool}"
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 70
fi

poolItemNumber=$(~/kvp_client $Pool | awk 'FNR==2 {print $4}')
if [ $poolItemNumber -lt $Items ]; then
    msg="Error: Pool $Pool has only $poolItemNumber items. We need $Items items or more"
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 70
fi

actualPoolItemNumber=$(~/kvp_client $Pool | grep Key | wc -l)
if [ $poolItemNumber -ne $actualPoolItemNumber ]; then
    msg="Error: Pool $Pool reported $poolItemNumber items but actually has $actualPoolItemNumber items"
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 70
fi

LogMsg "Updating test case state to completed"
UpdateTestState $ICA_TESTCOMPLETED

exit 0