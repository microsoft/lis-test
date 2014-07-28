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
# STOR_VHDXResize_GrowFS.sh
# Description:
#     This script will verify if you can create, format, mount, perform 
#     read/write operation, unmount and deleting a partition on a resized  
#     VHDx file
#     Hyper-V setting pane. The test performs the following
#     step
#    1. Creates partition
#    2. Creates filesystem
#    3. Performs read/write operations
#    4. Unmounts partition
#    5. Deletes partition  
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
# Make sure constants.sh contains the variables we expect
#
if [ "${TC_COVERED:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter TC_COVERED is not defined in ${CONSTANTS_FILE}"
    echo $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

#
# Echo TCs we cover
#
echo "Covers ${TC_COVERED}" > ~/summary.log

#
# Verify if guest sees the new drive
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
# Create the new partition
#
(echo n; echo p; echo 1; echo ; echo ;echo w) | fdisk /dev/sdb 2> /dev/null
if [ $? -gt 0 ]; then
    LogMsg "Failed to create partition"
    echo "Creating partition: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi
LogMsg "Partition created"
#
# Format the partition
#
case $(LinuxRelease) in
    "SLES")
		#
		# Format the partition with ext4
		#
		mkfs -t ext3 /dev/sdb1 2> ~/summary.log
		if [ $? -gt 0 ]; then
			LogMsg "Failed to format partition"
			echo "Formating partition: Failed" >> ~/summary.log
			UpdateTestState $ICA_TESTFAILED
			exit 10
		fi
		LogMsg "Successfully formated partition"
		;;
	*)
		#
		# Format the partition with ext4
		#
		mkfs -t ext4 /dev/sdb1 2> ~/summary.log
		if [ $? -gt 0 ]; then
			LogMsg "Failed to format partition"
			echo "Formating partition: Failed" >> ~/summary.log
			UpdateTestState $ICA_TESTFAILED
			exit 10
		fi
		LogMsg "Successfully formated partition"
		;;
esac
#
# Mount partition
#
if [ ! -e "/mnt" ]; then
    mkdir /mnt 2> summary.log
    if [ $? -gt 0 ]; then
        LogMsg "Failed to create mount point"
        echo "Creating mount point: Failed" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 10
    fi
    LogMsg "Mount point /dev/mnt created"
fi

mount /dev/sdb1 /mnt 2> ~summary.log
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
mkdir /mnt/ICA/ 2> ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to create directory /mnt/ICA/"
    echo "Creating /mnt/ICA/ directory: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

echo 'testing' > /mnt/ICA/ICA_Test.txt 2> ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to create file /mnt/ICA/ICA_Test.txt"
    echo "Creating file /mnt/ICA/ICA_Test.txt: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

ls /mnt/ICA/ICA_Test.txt > ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to list file /mnt/ICA/ICA_Test.txt"
    echo "Listing file /mnt/ICA/ICA_Test.txt: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

cat /mnt/ICA/ICA_Test.txt > ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to read file /mnt/ICA/ICA_Test.txt"
    echo "Listing read /mnt/ICA/ICA_Test.txt: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

# unalias rm 2> /dev/null
rm /mnt/ICA/ICA_Test.txt > ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to delete file /mnt/ICA/ICA_Test.txt"
    echo "Deleting /mnt/ICA/ICA_Test.txt file: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi

rmdir /mnt/ICA/ 2> ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to delete directory /mnt/ICA/"
    echo "Deleting /mnt/ICA/ directory: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi
#
# Restore ICA folder
#
mkdir /mnt/ICA/ 2> ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to restore directory /mnt/ICA/"
    echo "Restoring /mnt/ICA/ directory: Failed" >> ~/summary.log
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

UpdateTestState $ICA_TESTCOMPLETED

exit 0;
