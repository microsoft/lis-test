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
#     Integration services.this script test number of scsi disk 
#     present inside guest vm is correct.

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

# Source the constants file

if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
else
    LogMsg "ERROR: Unable to source the constants file."
    exit 1
fi


#Check for Testcase count
if [ ! ${TC_COUNT} ]; then
    LogMsg "The TC_COUNT variable is not defined."
	echo "The TC_COUNT variable is not defined." >> ~/summary.log
    LogMsg "Terminating the test."
    UpdateTestState "TestAborted"
    exit 1
fi

echo "Covers : ${TC_COUNT}" >> ~/summary.log

UpdateTestState "TestRunning"

#Source the FTM Framework script
#if [ -e $ICA_BASE_DIR/FTM-FRAMEWORK.sh ]; then
# . $ICA_BASE_DIR/FTM-FRAMEWORK.sh
#else
# echo "ERROR: Unable to source the FRAMEWORK file."
# exit 1
#fi

## Check if Variable in Const file is present or not
if [ ! ${NO} ]; then
	LogMsg "The NO variable is not defined."
	echo "The NO variable is not defined." >> ~/summary.log
	LogMsg "aborting the test."
	UpdateTestState "TestAborted"
	exit 1
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

LogMsg "Test : Checking if scsi disk are present inside guest VM or not ?"

checkdisk
if [ "$NEW_DISK" = "$NO" ] ; then
    LogMsg "Result : New disk is present inside guest VM "
    LogMsg " fdisk -l is : "
    fdisk -l	
else
    LogMsg "Result : New disk is not present in Guest VM "
    UpdateTestState "TestAborted"
    LogMsg "Result : Number of scsi disk inside guest VM is $noofscsidisk"
    echo "Result : Number of scsi disk inside guest VM is $noofscsidisk" >> ~/summary.log
    LogMsg " fdisk -l is : "
    fdisk -l
    exit 1
fi

i=1
while [ $i -le $NO ]
do
    j=TEST_DEVICE$i
    if [ ${!j:-UNDEFINED} = "UNDEFINED" ]; then
        LogMsg "Error: constants.sh did not define the variable $j"
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi

    LogMsg "TEST_DEVICE = ${!j}"
        
    echo "Target device = ${!j}" >> ~/summary.log


DISK=`echo ${!j} | cut -c 6-8`
#
# Fomate-mount-unmount disk
#
(echo d;echo;echo w)|fdisk /dev/$DISK
(echo n;echo p;echo 1;echo;echo;echo w)|fdisk /dev/$DISK
sleep 5
if [ "$?" = "0" ]; then
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
					UpdateTestState "TestAborted"
					exit 1
                fi
            else
                LogMsg "Error in mounting drive..."
				echo "Drive mount : Failed" >> ~/summary.log
				UpdateTestState "TestAborted"
				exit 1
            fi
        else
            LogMsg "Error in creating file system.."
			echo "Creating Filesystem : Failed" >> ~/summary.log
			UpdateTestState "TestAborted"
			exit 1
        fi
    else
        LogMsg "Error in executing fdisk /dev/${DISK}..."
        echo "Error in executing fdisk /dev/${DISK}..." >> ~/summary.log
        UpdateTestState "TestAborted"	
        exit 1		
    fi
    i=$[$i+1]
done

LogMsg "#########################################################"
LogMsg "Result : Test Completed Succesfully"
LogMsg "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"