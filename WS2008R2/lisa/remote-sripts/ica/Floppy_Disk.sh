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

# Description:
#     This script was created to automate the testing of a Linux
#     Integration services.This script detects the floppy disk    
#     and performs read, write and delete operations on the   
#     Floppy disk.
#     Steps:
#	  1. Make sure that a floppy disk (.vfd) is attached to 
#        the Diskette drive
#	  2. Mount the Floppy Disk. 
#     3. Create a file named Sample.txt on the Floppy Disk
#     4. Read the file created on the Floppy Disk 
#	  5. Delete the file created on the Floppy Disk.
#     6. Unmount the Floppy Disk.

echo "########################################################"
echo "This Test Case creates a floppy device if it does not"
echo "already exist, then creates a file system on the device,"
echo "mounts the device, and the performs read, write and delete"
echo "operations on the floppy disk"

DEBUG_LEVEL=3
LINUX="Linux"
FREEBSD="FreeBSD"

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

cd ~

if [ -e ~/summary.log ]; then
    dbgprint 1 "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

UpdateSummary()
{
    echo $1 >> ~/summary.log
}

#
# Convert any .sh files to Unix format
#
dos2unix -f ica/* > /dev/null  2>&1

GetOSType()
{
    OSType=$(uname -s)
	return $OSType
}

CreateFileSystemOnFd()
{
    GetOSType
    if [ "$OSType" = "$LINUX" ]; then
        echo "Linux System"
        echo "Create /dev/fd0 if it does not already exist"

        if [ ! -e /dev/fd0 ]; then
            /dev/MAKEDEV /dev/fd0
            sts=$?

            if [ 0 -ne ${sts} ]; then
                dbgprint 1 "Error creating floppy device"
	            dbgprint 1 "Aborting test"
	        exit 1
            fi
        fi

	    #
        # Put a file system on the floppy
        #
        echo "Put a file system on /dev/fd0"

        mkfs -t ext3 /dev/fd0 1440
        sts=$?

        if [ 0 -ne ${sts} ]; then
            dbgprint 1 "Error formatting /dev/fd0"
            dbgprint 1 "Aborting test"
            UpdateTestState "TestAborted"
            exit 1
        fi
    fi

    if [ "$OSType" = "$FREEBSD" ]; then
        echo "FreeBSD System"
		echo "Create file system on /dev/fd0"
        newfs /dev/fd0
        sts=$?
        if [ 0 -ne ${sts} ]; then
            dbgprint 1 "Error creating floppy device"
	        dbgprint 1 "Aborting test"
			UpdateTestState "TestAborted"
	        exit 1
        fi
    fi
}

# Create the file system on floppy device
CreateFileSystemOnFd

#
# Mount the floppy disk
#
echo "Mount the floppy disk"

mount /dev/fd0 /mnt/
sts=$?
if [ 0 -ne ${sts} ]; then
    dbgprint 1 "Unable to mount the Floppy Disk"
    dbgprint 1 "Mount Floppy Disk failed: ${sts}"
    dbgprint 1 "Aborting test."
    UpdateTestState "TestAborted"
    exit 1
else
    dbgprint 1  "Floppy disk is mounted successfully inside the VM"
    dbgprint 1  "Floppy disk is detected inside the VM"
    UpdateSummary "Floppy disk detected : Success"
fi 

echo "##### Perform read ,write and delete  operations on the Floppy Disk ######"
cd /mnt/

echo "#####Perform write operation on the floppy disk #####"
echo "Creating a file Sample.txt ........."
echo "This is a sample file been created for testing..." >Sample.txt

sts=$?
if [ 0 -ne ${sts} ]; then
    dbgprint 1 "Unable to create a file on the Floppy Disk"
    dbgprint 1 "Write to Floppy Disk failed: ${sts}"
    dbgprint 1 "Aborting test."
    UpdateTestState "TestAborted"
    exit 1
else
    dbgprint 1  "Sample.txt file created successfully on the Floppy disk"
    UpdateSummary "File Creation inside floppy disk : Success"
fi

echo "#####Perform read operation on the floppy disk #####"
cat Sample.txt

sts=$?
if [ 0 -ne ${sts} ]; then
    dbgprint 1 "Unable to read Sample.txt file from the floppy disk"
    dbgprint 1 "Read file from Floppy disk failed: ${sts}"
    dbgprint 1 "Aborting test."
    UpdateTestState "TestAborted"
    exit 1
else
     dbgprint 1 "Sample.txt file is read successfully from the Floppy disk"
     UpdateSummary "File read inside floppy disk : Success"
fi

echo "##### Perform delete operation on the Floppy disk #####"

rm Sample.txt
sts=$?
        
if [ 0 -ne ${sts} ]; then
    dbgprint 1 "Unable to delete Sample.txt file from the floppy disk"
    dbgprint 1 "Delete file failed: ${sts}"
    dbgprint 1 "Aborting test."
    UpdateTestState "TestAborted"
    exit 1
else
    dbgprint 1  "Sample.txt file is deleted successfully from the Floppy disk"
    UpdateSummary "File deletion inside floppy disk : Success"
fi

echo "#### Unmount the floppy disk ####"
cd ~
umount /mnt/
sts=$?      

if [ 0 -ne ${sts} ]; then
    dbgprint 1 "Unable to unmount the floppy disk"
    dbgprint 1 "umount failed: ${sts}"
    dbgprint 1 "Aborting test."
    UpdateTestState "TestAborted"
    exit 1
else
    dbgprint 1  "Floppy disk unmounted successfully"
    UpdateSummary "Floppy disk unmount: Success"
fi

echo "#########################################################"
echo "Result : Test Completed Succesfully"
dbgprint 1 "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"



















