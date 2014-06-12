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
# STOR_VHDXResize_GrowFSAfterResize.sh
# Description:
#     This script will verify if you can resize the filesystem on a resized  
#     VHDx file
#     Hyper-V setting pane. The test performs the following
#     step
#    1. Restores partition
#    2. Checks the filesystem
#    3. Perform filesystem resize
#    4. Mounts the partition
#    5. Performs read/write operations
#    6. Unmounts partition
#    7. Deletes partition  
#
########################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error while performing the test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

cd ~

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

#######################################################################
# Checks what Linux distro we are running
#######################################################################
LinuxRelease()
{
    DISTRO=`grep -ihs "buntu\|Suse\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux" /etc/{issue,*release,*version}`

    case $DISTRO in
        *buntu*)
            echo "UBUNTU";;
        Fedora*)
            echo "FEDORA";;
        CentOS*)
            echo "CENTOS";;
        *SUSE*)
            echo "SLES";;
        Red*Hat*)
            echo "RHEL";;
        Debian*)
            echo "DEBIAN";;
        *)
            LogMsg "Unknown Distro"
            UpdateTestState "TestAborted"
            UpdateSummary "Unknown Distro, test aborted"
            exit 1
            ;; 
    esac
}

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

# Source the constants file
if [ -e ~/${CONSTANTS_FILE} ]; then
    source ~/${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    echo $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

#
# Verify if guest sees the drive
#
if [ ! -e "/dev/sdb" ]; then
    msg = "The Linux guest cannot detect the drive"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi
LogMsg "The Linux guest detected the drive"

#
# Restore the partition
#
(echo n; echo p; echo 1; echo ; echo ;echo w) | fdisk /dev/sdb 2> /dev/null
if [ $? -gt 0 ]; then
    LogMsg "Failed to restore partition"
    echo "Restore partition: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi
LogMsg "Partition restored"

#
#Checking filesystem
#
e2fsck -y -v -f /dev/sdb1
if [ $? -gt 0 ]; then
        LogMsg "Failed to check filesystem"
        echo "Checking filesystem: Failed" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 10
fi
LogMsg "Filesystem checked"

#
# Resizing the filesystem 
#
resize2fs /dev/sdb1
if [ $? -gt 0 ]; then
    LogMsg "Failed to resize filesystem"
    echo "Resizing the filesystem: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi
LogMsg "Filesystem resized"

#
# Mount partition
#
if [ ! -e "/mnt" ]; then
    mkdir /mnt 2> ~/summary.log
    if [ $? -gt 0 ]; then
        LogMsg "Failed to create mount point"
        echo "Creating mount point: Failed" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 10
    fi
    LogMsg "Mount point /dev/mnt created"
fi

mount /dev/sdb1 /mnt 2> ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to mount partition"
    echo "Mounting partition: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi
LogMsg "Partition mount successful"

#
# Read/Write mount point
#
mkdir /mnt/ICA2/ 2> ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to create directory /mnt/ICA2/"
    echo "Creating /mnt/ICA2/ directory: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

echo 'testing' > /mnt/ICA2/ICA_Test2.txt 2> ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to create file /mnt/ICA2/ICA_Test2.txt"
    echo "Creating file /mnt/ICA2/ICA_Test2.txt: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

ls /mnt/ICA2/ICA_Test2.txt > ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to list file /mnt/ICA2/ICA_Test2.txt"
    echo "Listing file /mnt/ICA2/ICA_Test2.txt: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

cat /mnt/ICA2/ICA_Test2.txt > ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to read file /mnt/ICA/ICA_Test.txt"
    echo "Listing read /mnt/ICA2/ICA_Test2.txt: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

# unalias rm 2> /dev/null
rm /mnt/ICA2/ICA_Test2.txt > ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to delete file /mnt/ICA2/ICA_Test2.txt"
    echo "Deleting /mnt/ICA2/ICA_Test2.txt file: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

rmdir /mnt/ICA2/ 2> ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to delete directory /mnt/ICA2/"
    echo "Deleting /mnt/ICA2/ directory: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

umount /mnt
if [ $? -gt 0 ]; then
    LogMsg "Failed to unmount partition"
    echo "Unmounting partition: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi
LogMsg "Unmount partition successful"

(echo d; echo 1; echo w) | fdisk /dev/sdb 2> ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to delete partition"
    echo "Deleting partition: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi
LogMsg "Delete partition successful"

UpdateTestState $ICA_TESTCOMPLETED

exit 0;
