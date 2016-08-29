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

#######################################################################
# 
# STOR_Verify_Sector_Size.sh
# Description:
#    This script will verify logical sector size for 512 only and physical
#    sector size is 4096, mainly for 4k alignment feature.
#     step
#    1. Fdisk with {n,p,w}, fdisk -lu (by default display sections units )
#    2. Verify the first sector of the disk can divide 8
#    3. Verify the logial sector and physical size
#    Note: for logical size is 4096, already 4k align, no need to test.
#
########################################################################

ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"

# Need to add one disk before test
driveName=/dev/sdb

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

# Make sure the constants.sh file exists
if [ ! -e ./constants.sh ]; then
    LogMsg "Cannot find constants.sh file."
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

# Source the constants file
if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
else
    LogMsg "ERROR: Unable to source the constants file."
    exit 1
fi

# add new disk partition with "n" and showing the sectors units format
(echo n; echo p; echo 1; echo ; echo ; echo w) |  fdisk $driveName

startSector=`fdisk -lu $driveName | tail -1 | awk '{print $2}'`
logicalSectorSize=`fdisk -lu $driveName | grep -i 'Sector size' | grep -oP '\d+' | head -1`
PhysicalSectorSize=`fdisk -lu $driveName | grep -i 'Sector size' | grep -oP '\d+' | tail -1`

if [ $(($startSector%8)) -eq 0 ]; then
   echo "Check the first sector size on $driveName disk $startSector can divide 8: Success"
   UpdateSummary "Check the first sector size on $driveName disk $startSector can divide 8 : Success"
else
  echo "Error: first sector size on $driveName disk Failed"
  UpdateSummary " first sector size on $driveName disk Failed"
  UpdateTestState "TestAborted"
  exit 1
fi

#check logical sector size is 512 and physical sector is 4096, 4k alignment only needs to test in 512 sector
if [[ $logicalSectorSize = 512 && $PhysicalSectorSize = 4096 ]]; then

   echo "Check logical and physical sector size on disk $driveName : Success"
   UpdateSummary "Check logical and physical sector size on disk $driveName : Success"
else

   echo "Error: Check logical and physical sector size on disk  $driveName : Failed "
   UpdateTestState "TestAborted"
   UpdateSummary " Error: Check logical and physical sector size on disk  $driveName : Failed"
   exit 1
fi

UpdateTestState $ICA_TESTCOMPLETED
exit 0
