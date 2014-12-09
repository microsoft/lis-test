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

#     This script was created to automate the testing of a Linux
#     Integration services.This script test the detection of a disk  
#     inside the Linux VM by performing the following
#     Steps:
#	 1. Make sure we we have a disk inside the Linux VM.
#        2. Check for  mainline as for mainline the new disk will be detected as sda
#	 2. Get the disk count inside Linux VM 
#        3. Compare it with 2 (as one disk will be used for Linux OS).
# Create the state.txt file so the ICA script knows
# we are running


dbgprint()
{
    if [ $1 -le $DEBUG_LEVEL ]; then
        echo "$2"
    fi
}


UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

#
# Source the constants file
#
if [ -e ~/summary.log ]; then
    dbgprint 1 "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
else
    echo "ERROR: Unable to source the constants file."
    exit 1
fi

UpdateTestState "TestRunning"

No_Of_Disk=$(fdisk -l | awk '{print $2}' | grep /dev/hd | wc -l)

#Delete root partition no. 

   No_Of_Disk=`expr $No_Of_Disk - 1`
   if [[ "$No_Of_Disk" -eq "$IDE_DISK" ]]; then
 	echo -e "TEST CASE PASS : No. of Synthetic IDE Disk inside Guest VM is $No_Of_Disk"
	UpdateTestState "TestCompleted"

   else
        echo -e "Test Fail : ERROR: Synthetic IDE Disk Count is wrong in Guest VM"
        UpdateTestState "TestAborted"

   fi









 
