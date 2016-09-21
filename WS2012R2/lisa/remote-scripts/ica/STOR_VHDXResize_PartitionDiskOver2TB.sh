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
# STOR_VHDXResize_PartitionDiskOver2TB.sh
# Description:
#     This script will verify if you can create, format, mount, perform
#     read/write operation, unmount and deleting a partition on
#     a VHDx file larger than 2TB
#     Hyper-V setting pane. The test performs the following
#     step
#    1. Make sure we have a constants.sh file.
#    2. Creates partition
#    3. Creates filesystem
#    4. Performs read/write operations
#    5. Unmounts partition
#    6. Deletes partition
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

if [ "${fileSystems:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter fileSystems is not defined in constants file."
    LogMsg "$msg"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi
#
# Verify if guest sees the new drive
#
if [ ! -e "/dev/sdb" ]; then
    msg="The Linux guest cannot detect the drive"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi
LogMsg "The Linux guest detected the drive"

# Support $NewSize and $growSize,if not define $NewSize, check $growSize
if [ -z $NewSize ] && [ -n $growSize ]; then
  NewSize=$growSize
  LogMsg "Target parted size is $NewSize"
fi

#
# Create the new partition
#
parted /dev/sdb -s mklabel gpt mkpart primary 0GB $NewSize 2> ~/summary.log
if [ $? -gt 0 ]; then
    LogMsg "Failed to create partition by parted with $NewSize"
    echo "Creating partition: Failed by parted with $NewSize" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi
LogMsg "Partition created by parted"
sleep 5

#
# Format the partition
#
count=0
for fs in "${fileSystems[@]}"; do
    LogMsg "Start testing filesystem: $fs"
    command -v mkfs.$fs
    if [ $? -ne 0 ]; then
        echo "File-system tools for $fs not present. Skipping filesystem $fs.">> ~/summary.log
        LogMsg "File-system tools for $fs not present. Skipping filesystem $fs."
        count=`expr $count + 1`
    else
        mkfs -t $fs /dev/sdb1 2> ~/summary.log
        if [ $? -gt 0 ]; then
            LogMsg "Failed to format partition with $fs"
            echo "Formating partition: Failed with $fs" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 10
        fi
        LogMsg "Successfully formated partition with $fs"
        break
    fi
done

if [ $count -eq ${#fileSystems[@]} ]; then
    LogMsg "Failed to format partition with ext4 and ext3"
    echo "Formating partition: Failed with all filesystems proposed." >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi


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
dos2unix STOR_VHDXResize_ReadWrite.sh
chmod +x STOR_VHDXResize_ReadWrite.sh
./STOR_VHDXResize_ReadWrite.sh

umount /mnt
if [ $? -gt 0 ]; then
    LogMsg "Failed to unmount partition"
    echo "Unmounting partition: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi
LogMsg "Unmount partition successful"

parted /dev/sdb -s rm 1
if [ $? -gt 0 ]; then
    LogMsg "Failed to delete partition"
    echo "Deleting partition: Failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi
LogMsg "Deleting partition successful"

UpdateTestState $ICA_TESTCOMPLETED

exit 0;
