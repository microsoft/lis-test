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
# Description:
#     This script was created to automate the testing of a Linux
#     Integration services.This script detects the floppy disk    
#     and performs read, write and delete operations on the   
#     Floppy disk.
#     Steps:
#	  1. Make sure that a floppy disk (.vfd) is attached to 
#          the Diskette drive
#	  2. Mount the Floppy Disk. 
#      3. Create a file named Sample.txt on the Floppy Disk
#      4. Read the file created on the Floppy Disk 
#	  5. Delete the file created on the Floppy Disk.
#      6. Unmount the Floppy Disk.
#
#  
################################################################

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

UpdateSummary()
{
    echo $1 >> ~/summary.log
}

cd ~
UpdateTestState "TestRunning"

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

if [ -e $HOME/constants.sh ]; then
	. $HOME/constants.sh
else
	LogMsg "ERROR: Unable to source the constants file."
	UpdateTestState "TestAborted"
	exit 1
fi

#Check for Testcase ID
if [ ! ${TC_COVERED} ]; then
    LogMsg "Error: The TC_COVERED variable is not defined."
	echo "Error: The TC_COVERED variable is not defined." >> ~/summary.log
    UpdateTestState "TestAborted"
    exit 1
fi

echo "Covers : ${TC_COVERED}" >> ~/summary.log

#
# check if floppy module is loaded or not 
#
LogMsg "Check if floppy module is loaded"

FLOPPY=`lsmod | grep floppy`
if [[ $FLOPPY != "" ]] ; then
    LogMsg "Floppy disk  module is present"
else
    LogMsg "Floppy disk module is not present in VM"
    LogMsg "Loading Floppy disk module..."
    modprobe floppy
    sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "Unable to load Floppy Disk module!"
	UpdateSummary "Floppy disk module loaded : Failed!"
        UpdateTestState "TestFailed"
        exit 1
    else
        LogMsg  "Floppy disk module loaded inside the VM"
        UpdateSummary "Floppy disk module loaded : Success"
        sleep 3
    fi
fi

#
# Format the floppy disk
#
LogMsg "mkfs -t vfat /dev/fd0"

mkfs -t vfat /dev/fd0
if [ $? -ne 0 ]; then
    msg="Unable to mkfs -t vfat /dev/fd0"
    LogMsg "Error: ${msg}"
    echo $msg >> ~/summary.log
    UpdateTestState "TestFailed"
    exit 20
fi

#
# Mount the floppy disk
#
LogMsg "Mount the floppy disk"
mount /dev/fd0 /mnt/
sts=$?
if [ 0 -ne ${sts} ]; then
    LogMsg "Unable to mount the Floppy Disk"
    LogMsg "Mount Floppy Disk failed: ${sts}"
    LogMsg "Aborting test."
	UpdateSummary "Unable to mount the Floppy Disk"
    UpdateTestState "TestFailed"
    exit 1
else
    LogMsg  "Floppy disk is mounted successfully inside the VM"
    LogMsg "Floppy disk is detected inside the VM"
    UpdateSummary "Floppy disk detected : Success"
fi

LogMsg "Perform read ,write and delete  operations on the Floppy Disk"
cd /mnt/
LogMsg "Perform write operation on the floppy disk"
LogMsg "Creating a file Sample.txt"
LogMsg "This is a sample file been created for testing..." >Sample.txt
sts=$?
if [ 0 -ne ${sts} ]; then
    LogMsg "Unable to create a file on the Floppy Disk"
    LogMsg "Write to Floppy Disk failed: ${sts}"
    LogMsg "Aborting test."
	UpdateSummary "Unable to create a file on the Floppy Disk"
    UpdateTestState "TestFailed"
    exit 1
else
    LogMsg  "Sample.txt file created successfully on the Floppy disk"
    UpdateSummary "File Creation inside floppy disk : Success"
fi

LogMsg "Perform read operation on the floppy disk"
cat Sample.txt
sts=$?
       if [ 0 -ne ${sts} ]; then
            LogMsg "Unable to read Sample.txt file from the floppy disk"
	        LogMsg "Read file from Floppy disk failed: ${sts}"
	        LogMsg "Aborting test."
			UpdateSummary "Unable to read Sample.txt file from the floppy disk"
            UpdateTestState "TestFailed"
		    exit 1
        else
            LogMsg "Sample.txt file is read successfully from the Floppy disk"
		    UpdateSummary "File read inside floppy disk : Success"          
       fi

LogMsg "Perform delete operation on the Floppy disk"

rm Sample.txt
sts=$?
        
        if [ 0 -ne ${sts} ]; then
            LogMsg "Unable to delete Sample.txt file from the floppy disk"
	        LogMsg "Delete file failed: ${sts}"
	        LogMsg "Aborting test."
			UpdateSummary "Unable to delete Sample.txt file from the floppy disk"
            UpdateTestState "TestFailed"
		    exit 1
        else
           LogMsg "Sample.txt file is deleted successfully from the Floppy disk"
		   UpdateSummary "File deletion inside floppy disk : Success"           
       fi

LogMsg "#### Unmount the floppy disk ####"
cd ~
umount /mnt/
sts=$?      
        if [ 0 -ne ${sts} ]; then
            LogMsg "Unable to unmount the floppy disk"
	        LogMsg "umount failed: ${sts}"
	        LogMsg "Aborting test."
			UpdateSummary "Unable to unmount the floppy disk"
            UpdateTestState "TestFailed"
		    exit 1
        else
            LogMsg  "Floppy disk unmounted successfully"
		    UpdateSummary "Floppy disk unmount: Success"   
        fi

LogMsg "#########################################################"
LogMsg "Result : Test Completed Succesfully"
LogMsg "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"
