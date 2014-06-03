#!/bin/bash

############################################################################
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
############################################################################

############################################################################
#
# Performance_IOzone.sh
#
# Description:
# 	For the test to run you have to place the iozone3_420.tar archive in the
# 	Tools folder under lisa.
#
# Parameters:
#     TOTAL_DISKS: Number of disks attached
#     TEST_DEVICE1 = /dev/sdb
#
############################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the time-stamp to the log file
}

UpdateTestState()
{
    echo $1 > ~/state.txt
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
# Create the state.txt file so ICA knows we are running
#
LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

#
# Source the constants.sh file
#
if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    echo "Warn : no ${CONSTANTS_FILE} found"
fi

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

#
# Check if variable is defined in the constants file
#
if [ ! ${TOTAL_DISKS} ]; then
    LogMsg "The TOTAL_DISKS variable is not defined."
    echo "The TOTAL_DISKS variable is not defined." >> ~/summary.log
    LogMsg "aborting the test."
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

echo "Number of disk attached : $TOTAL_DISKS" >> ~/summary.log

fdisk -l
sleep 2
NEW_DISK=$(fdisk -l | grep "Disk /dev/sd*" | wc -l)
NEW_DISK=$((NEW_DISK-1))
if [ "$NEW_DISK" = "$TOTAL_DISKS" ] ; then
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

case $(LinuxRelease) in
    "UBUNTU")
        apt-get install make
        FS="ext4"
    ;;
    "SLES")
        FS="ext3"
    ;;
     *)
        FS="ext4"
    ;; 
esac

i=1
while [ $i -le $TOTAL_DISKS ]
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

# Format and mount the disk
    (echo d;echo;echo w)|fdisk /dev/$DISK
    sleep 2
    (echo n;echo p;echo 1;echo;echo;echo w)|fdisk /dev/$DISK
    sleep 5
    mkfs.${FS} /dev/${DISK}1
    if [ "$?" = "0" ]; then
        LogMsg "mkfs.$FS /dev/${DISK}1 successful..."
        mount /dev/${DISK}1 /mnt
        if [ "$?" = "0" ]; then
            LogMsg "Drive mounted successfully..."    
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
    i=$[$i+1]
done

#
# Install iometer and check if the installation is successful
#
IOZONE=/root/${FILE_NAME}

if [ ! -e ${IOZONE} ];
then
    echo "Cannot find iozone file." >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

# Get Root Directory of the archive
ROOTDIR=`tar -tvf ${IOZONE} | head -n 1 | awk -F " " '{print $6}' | awk -F "/" '{print $1}'`

tar -xvf ${IOZONE}
sts=$?
if [ 0 -ne ${sts} ]; then
    echo "Failed to extract the iozone archive!" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi
 
if [ !  ${ROOTDIR} ];
then
    echo "Cannot find ROOTDIR." >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 40
fi

cd ${ROOTDIR}/src/current

#
# Compile iozone
#
make linux
sts=$?
    if [ 0 -ne ${sts} ]; then
        echo "Error: make linux  ${sts}" >> ~/summary.log
        UpdateTestState "TestAborted"
        echo "make linux : Failed" 
        exit 50
    else
        echo "make linux: Success"

    fi


LogMsg "iometer was installed successfully!"

# 
# Run iozone for throughput test
# IOZONE_PARAMS: -s 48G -r 4K -i 0 -i 1 -i 2 -l 4 -u 4 -I -k 8
# 
cd /mnt
/root/${ROOTDIR}/src/current/iozone ${IOZONE_PARAMS} -b /root/IOZoneResult.xls /mnt > /root/IOZoneLog.log

#
# Check if the SCSI disk is still connected
#
mkdir /mnt/Example
dd if=/dev/zero of=/mnt/Example/data bs=10M count=50
    if [ $? -ne 0 ]; then
        LogMsg "iozone test failed!"
        echo "iozone test failed!" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 60
    fi
sleep 1

LogMsg "=iozone test completed successfully"
echo "iozone test completed successfully" >> ~/summary.log

#
# Let ICA know we completed successfully
#
LogMsg "Updating test case state to completed"
UpdateTestState $ICA_TESTCOMPLETED

exit 0
