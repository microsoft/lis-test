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
# FC_disks.sh
# Description:
#	This script was created to automate the testing of a Linux
#	Integration services. This script will identify the number of 
#	total disks detected inside the guest VM.
#	It will then format one FC disk and perform read/write checks on it.
#   This test verifies the first FC disk, if you want to check every disk
#   move the exit statement from line 215 to line 217.
#     
#	 To pass test parameters into test cases, the host will create
#    a file named constants.sh. This file contains one or more
#    variable definition.
#
################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

CONSTANTS_FILE="constants.sh"
diskCount=0
sdCount=0
firstDrive=1

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

#
# Update LISA with the current status
#
cd ~
UpdateTestState $ICA_TESTRUNNING
LogMsg "Updating test case state to running"

#
# Source the constants file
#
if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    ERRmsg="Error: no ${CONSTANTS_FILE} file"
    LogMsg $ERRmsg
    echo $ERRmsg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

#
# Identifying the test-case ID
#
if [ ! ${TC_COVERED} ]; then
    LogMsg "The TC_COVERED variable is not defined!"
	echo "The TC_COVERED variable is not defined!" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

#
# Echo TCs we cover
#
echo "Covers ${TC_COVERED}" > ~/summary.log

#
# Count the number of SCSI= and IDE= entries in constants
#
for entry in $(cat ./constants.sh)
do
    # Convert to lower case
    lowStr="$(tr '[A-Z]' '[a-z' <<<"$entry")"

    # does it start wtih ide or scsi
    if [[ $lowStr == ide* ]];
    then
        diskCount=$((diskCount+1))
    fi

    if [[ $lowStr == scsi* ]];
    then
        diskCount=$((diskCount+1))
    fi
done

echo "Constants variable file disk count: $diskCount"

#
# Compute the number of sd* drives on the system.
#
for drive in $(find /sys/devices/ -name 'sd*' | grep 'sd.$' | sed 's/.*\(...\)$/\1/')
do
    sdCount=$((sdCount+1))
done

#
# Subtract the boot disk from the sdCount, then make sure the two disk counts match
#
sdCount=$((sdCount-1))
echo "/sys/devices disk count = $sdCount"

if [ $sdCount -lt 1 ];
then
    echo " disk count ($diskCount) from /sys/devices ($sdCount) returns only the boot disk"
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

#
# For each drive, run fdisk -l and extract the drive size in bytes 
#
for drive in $(find /sys/devices/ -name 'sd*' | grep 'sd.$' | sed 's/.*\(...\)$/\1/')
do
    #
    # Skip /dev/sda
    #
	if [ ${drive} = "sda" ]; then
        continue
    fi
    driveName="/dev/${drive}"
    fdisk -l $driveName > fdisk.dat 2> /dev/null
    # Format the Disk and Create a file system , Mount and create file on it .
    
    (echo d;echo;echo w)|fdisk  $driveName
    if [ "$?" != "0" ]; then
        LogMsg "Error in executing fdisk on ${driveName} !"
        echo "Error in executing fdisk on ${driveName} !" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 60
    fi

    (echo n;echo p;echo 1;echo;echo;echo w)|fdisk  $driveName
    if [ "$?" = "0" ]; then
        sleep 5
        mkfs.ext3  ${driveName}1
        if [ "$?" = "0" ]; then
            LogMsg "mkfs.ext3   ${driveName}1 successful..."
            mount   ${driveName}1 /mnt
                    if [ "$?" = "0" ]; then
                    LogMsg "Drive mounted successfully..."
                    mkdir /mnt/Example
                    dd if=/dev/zero of=/mnt/Example/data bs=10M count=30
                    if [ "$?" = "0" ]; then
                        LogMsg "Successful created directory /mnt/Example"
                        LogMsg "Listing directory: ls /mnt/Example"
                        ls /mnt/Example
                        df -h
                        umount /mnt
                        if [ "$?" = "0" ]; then
                            LogMsg "Drive unmounted successfully..."
                     fi
                        LogMsg "Disk test completed for ${driveName}1"
                        echo "Disk test is completed for ${driveName}1" >> ~/summary.log
                    else
                        LogMsg "Error in creating directory /mnt/Example!"
                        echo "Error in creating directory /mnt/Example!" >> ~/summary.log
                        UpdateTestState $ICA_TESTFAILED
                        exit 60
                    fi
                else
                    LogMsg "Error in mounting drive!"
                    echo "Drive mount : Failed!" >> ~/summary.log
                    UpdateTestState $ICA_TESTFAILED
                    exit 70
                fi
        else
            LogMsg "Error in creating file-system!"
            echo "Creating file-system has failed!" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 80
        fi
    else
        LogMsg "Error in executing fdisk  ${driveName}1"
        echo "Error in executing fdisk  ${driveName}1" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 90
    fi
UpdateTestState $ICA_TESTCOMPLETED

exit 0
done
