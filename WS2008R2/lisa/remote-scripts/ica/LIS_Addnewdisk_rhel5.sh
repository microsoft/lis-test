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
#     Integration services.this script test number of scsi disk 
#     present inside guest vm is correct.
#    
# Parameters:
#     NO : Numbers of disk attached
#     TEST_DEVICE1 = /dev/sdb

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

LogMsg "########################################################"
LogMsg "This is Test Case performs Read/write operation on disks"

cd ~

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

# Source the constants file
if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi


#Check for Testcase count
if [ ! ${TC_COUNT} ]; then
    LogMsg "The TC_COUNT variable is not defined."
	echo "The TC_COUNT variable is not defined." >> ~/summary.log
    LogMsg "Terminating the test."
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

echo "Covers : ${TC_COUNT}" >> ~/summary.log

## Check if Variable in Const file is present or not
if [ ! ${NO} ]; then
	LogMsg "The NO variable is not defined."
	echo "The NO variable is not defined." >> ~/summary.log
	LogMsg "aborting the test."
	UpdateTestState $ICA_TESTABORTED
	exit 30
fi

echo "Number of disk attached : $NO" >> ~/summary.log

checkdisk()
{

    TOTAL_DISK=$(find /sys/devices/ -name  sd* | grep host | grep 'sd.$' | wc -l )
    ROOT_DISK=$(find /sys/devices/ -name  sda* | grep host | grep 'sd.$' | wc -l)
    NEW_DISK=$(($TOTAL_DISK-$ROOT_DISK))

    LogMsg "Result : TOTAL_DISK=$TOTAL_DISK, ROOT_DISK=$ROOT_DISK"

    TOTAL_DISK_OUTPUT=`find /sys/devices/ -name 'sd*'| grep host| grep 'sd.$'`
    ROOT_DISK_OUTPUT=`find /sys/devices/ -name 'sda*'| grep host| grep 'sd.$'`

    LogMsg "Result: TOTAL_DISK_OUTPUT=$TOTAL_DISK_OUTPUT"
    LogMsg "Result: ROOT_DISK_OUTPUT=$ROOT_DISK_OUTPUT"

	return $NEW_DISK
}

LogMsg "Test : Checking if NEW diskS are present inside guest VM or not ?"

#checkdisk
fdisk -l
sleep 2
NEW_DISK=$(fdisk -l | grep "Disk /dev/sd*" | wc -l)
NEW_DISK=$((NEW_DISK-1))
if [ "$NEW_DISK" = "$NO" ] ; then
    LogMsg "Result : New disk is present inside guest VM "
    LogMsg " fdisk -l is : "
    fdisk -l	
else
    LogMsg "Result : New disk is not present in Guest VM "
    UpdateTestState $ICA_TESTFAILED
    LogMsg "Result : Number of new diskS inside guest VM is $NEW_DISK"
    echo "Result : Number of new diskS inside guest VM is $NEW_DISK" >> ~/summary.log
    LogMsg " fdisk -l is : "
    fdisk -l
    exit 40
fi

i=1
while [ $i -le $NO ]
do
    j=TEST_DEVICE$i
    if [ ${!j:-UNDEFINED} = "UNDEFINED" ]; then
        LogMsg "Error: constants.sh did not define the variable $j"
        UpdateTestState $ICA_TESTABORTED
        exit 50
    fi

    LogMsg "TEST_DEVICE = ${!j}"
        
    echo "Target device = ${!j}" >> ~/summary.log


DISK=`echo ${!j} | cut -c 6-8`
#
# Fomate-mount-unmount disk
#
(echo d;echo;echo w)|fdisk /dev/$DISK
sleep 2
(echo n;echo p;echo 1;echo;echo;echo w)|fdisk /dev/$DISK
#if [ "$?" = "0" ]; then
    sleep 5
    mkfs.ext3 /dev/${DISK}1
    if [ "$?" = "0" ]; then
        LogMsg "mkfs.ext3 /dev/${DISK}1 successful..."
        mount /dev/${DISK}1 /mnt
                if [ "$?" = "0" ]; then
                LogMsg "Drive mounted successfully..."
                mkdir /mnt/Example
                dd if=/dev/zero of=/mnt/Example/data bs=10M count=50
                if [ "$?" = "0" ]; then
                    LogMsg "Successful created directory /mnt/Example"
                    LogMsg "Listing directory: ls /mnt/Example"
                    ls /mnt/Example
                    df -h
                    umount /mnt
                    if [ "$?" = "0" ]; then
                        LogMsg "Drive unmounted successfully..."
				    fi
                    LogMsg "Disk test completed for ${!j}"
                    echo "Disk test completed for ${!j}" >> ~/summary.log
                else
                    LogMsg "Error in creating directory /mnt/Example..."
                    echo "Error in creating directory /mnt/Example" >> ~/summary.log
                    UpdateTestState $ICA_TESTFAILED
                    exit 60
                fi
            else
                LogMsg "Error in mounting drive..."
                echo "Drive mount : Failed" >> ~/summary.log
                UpdateTestState $ICA_TESTFAILED
                exit 70
            fi
        else
            LogMsg "Error in creating file system.."
            echo "Creating Filesystem : Failed" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 80
        fi
    # else
        # LogMsg "Error in executing fdisk /dev/${DISK}..."
        # echo "Error in executing fdisk /dev/${DISK}" >> ~/summary.log
        # UpdateTestState $ICA_TESTFAILED	
        # exit 90		
    # fi
    i=$[$i+1]
done

LogMsg "#########################################################"
LogMsg "Result : Test Completed Successfully"
LogMsg "Exiting with state: TestCompleted."
UpdateTestState $ICA_TESTCOMPLETED

exit 0