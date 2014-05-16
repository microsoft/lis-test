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
# FC_stressTest.sh
# Description:
#   This script was created to automate the testing of a Linux
#   Integration services. This script will identify the number of 
#   total disks detected inside the guest VM.
#   It will then format one FC disk and perform stress test on it.
#   This test verifies the first FC disk, if you want to check every disk
#   move the exit statement from line 271 to line 273.
#     
#    To pass test parameters into test cases, the host will create
#    a file named constants.sh. This file contains one or more
#    variable definition.
#
################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

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
    esac
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
diskCount=0
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
# Compute the number of drives on the system
#
sdCount=0
for drive in $(find /sys/devices/ -name 'sd*' | grep 'sd.$' | sed 's/.*\(...\)$/\1/')
do
    sdCount=$((sdCount+1))
done

#
# Subtract the boot disk, then make sure the two disk counts match
#
sdCount=$((sdCount-1))
echo "/sys/devices disk count = $sdCount"

if [ $sdCount -lt 1 ]; then
    echo " disk count ($diskCount) from /sys/devices ($sdCount) returns only the boot disk"
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

case $(LinuxRelease) in
    "UBUNTU")
        FS="ext4"
        COMMAND="timeout 900 iozone -s 4G /mnt &"
        EVAL=""
    ;;
    "SLES")
        FS="ext3"
        COMMAND="bash -c \ '(sleep 900; kill \$$) & exec iozone -s 4G /mnt\'"
        EVAL="eval"
    ;;
     *)
        FS="ext4"
        COMMAND="timeout 900 iozone -s 4G /mnt &"
        EVAL=""
    ;; 
esac

firstDrive=1
for drive in $(find /sys/devices/ -name 'sd*' | grep 'sd.$' | sed 's/.*\(...\)$/\1/')
do
	#
	# Skip /dev/sda
	#
	if [ ${drive} = "sda" ]; then
		continue
	fi

	eligible=false;
	size=`fdisk -l /dev/$drive | grep "Disk /dev/sd*" | awk '{print $5}'`; 

	if [ $size -lt 4294967296 ]; then
		continue
		else
			eligible = true;
	fi 

    driveName="/dev/${drive}"
    fdisk -l $driveName > fdisk.dat 2> /dev/null

    # Format the disk, create a file-system, mount and create file on it
    (echo d;echo;echo w)|fdisk  $driveName
    (echo n;echo p;echo 1;echo;echo;echo w)|fdisk  $driveName
    if [ "$?" = "0" ]; then
        sleep 5
    	mkfs.${FS}  ${driveName}1
    	if [ "$?" = "0" ]; then
    		LogMsg "mkfs.${FS}   ${driveName}1 successful..."
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
            LogMsg "Error in executing mkfs  ${driveName}1"
            echo "Error in executing mkfs  ${driveName}1" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 90
        fi

    iozone -h
    if [ "$?" = "0" ]; then
    	${EVAL} ${COMMAND}
    else
    	LogMsg "iozone does not seem to be present!"
    	echo "iozone does not seem to be present!" >> ~/summary.log
    	UpdateTestState $ICA_TESTFAILED
    	exit 90
    fi

    LogMsg "Listing directory: ls /mnt/Example"
    ls /mnt/Example

    if [ "$?" = "0" ]; then
    	LogMsg "Reading from disk successfully"
    	echo "Reading from disk successfully" >> ~/summary.log
    	UpdateTestState $ICA_TESTCOMPLETED
    else
    	LogMsg "Reading from disk has failed!"
    	echo "Reading from disk has failed!" >> ~/summary.log
    	UpdateTestState $ICA_TESTFAILED
    	exit 90
    fi

    exit 0
done

if [ "$eligible" = false ] ; then
	LogMsg "No disk larger than 4GB!"
	echo "No disk larger than 4GB, can't test iozone!" >> ~/summary.log
	UpdateTestState $ICA_TESTFAILED
	exit 90	
fi
