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
# Performance_FIO.sh
#
# Description:
#     For the test to run you have to place the fio-2.1.10.tar.gz archive in the
#     Tools folder under lisa.
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

echo " Kernel version: $(uname -r)" >> ~/sumamary.log

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
        LogMsg "Run test on Ubuntu. Install dependencies..."
        apt-get -y install make
        apt-get -y install gcc
        apt-get -y install libaio-dev
        sts=$?
        if [ 0 -ne ${sts} ]; then
            echo "Failed to install the libaio-dev library!" >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
            exit 41
        fi
        FS="ext4"
        
        # Disable multipath so that it doesn't lock the disks
         if [ -e /etc/multipath.conf ]; then
            rm /etc/multipath.conf
        fi
        echo -e "blacklist {\n\tdevnode \"^sd[a-z]\"\n}" >> /etc/multipath.conf
        service multipath-tools reload
        service multipath-tools restart 

    ;;
    "RHEL"|"CENTOS")
        LogMsg "Run test on RHEL. Install libaio-devel..."
        yum -y install libaio-devel
        sts=$?
        if [ 0 -ne ${sts} ]; then
            echo "Failed to install the libaio-dev library!" >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
            exit 41
        fi
        FS="ext4"
    ;;
    "SLES")
        LogMsg "Run test on SLES. Install libaio-devel..."
        zypper --non-interactive install libaio-devel
        sts=$?
        if [ 0 -ne ${sts} ]; then
            echo "Failed to install the libaio-devel library!" >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
            exit 41
        fi
        FS="ext4"
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
# Install FIO and check if the installation is successful
#
FIO=/root/${FILE_NAME}

if [ ! -e ${FIO} ];
then
    echo "Cannot find FIO test source file." >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

# Get Root Directory of the archive
ROOTDIR=`tar -tvf ${FIO} | head -n 1 | awk -F " " '{print $6}' | awk -F "/" '{print $1}'`

tar -xvf ${FIO}
sts=$?
if [ 0 -ne ${sts} ]; then
    echo "Failed to extract the FIO archive!" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi
 
if [ !  ${ROOTDIR} ];
then
    echo "Cannot find ROOTDIR." >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 40
fi

cd ${ROOTDIR}

#
# Compile FIO
#
./configure
sts=$?
if [ 0 -ne ${sts} ]; then
    echo "Error: configure  ${sts}" >> ~/summary.log
    UpdateTestState "TestAborted"
     echo "Configure : Failed" 
    exit 50
else
    echo "Configure: Success"
fi

#
# make FIO
#
make
sts=$?
if [ 0 -ne ${sts} ]; then
    echo "Error: make  ${sts}" >> ~/summary.log
    UpdateTestState "TestAborted"
     echo "make : Failed" 
    exit 50
else
    echo "make: Success"
fi

LogMsg "FIO was installed successfully!"

# Run FIO with block size 4k
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/FIOLog-4k.log

# Run FIO with block size 8k
sed --in-place=.orig -e s:"bs=4k":"bs=8k": /root/${FIO_SCENARIO_FILE}
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/FIOLog-8k.log

# Run FIO with block size 16k
sed --in-place=.orig -e s:"bs=8k":"bs=16k": /root/${FIO_SCENARIO_FILE}
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/FIOLog-16k.log

# Run FIO with block size 32k
sed --in-place=.orig -e s:"bs=16k":"bs=32k": /root/${FIO_SCENARIO_FILE}
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/FIOLog-32k.log

# Run FIO with block size 64k
sed --in-place=.orig -e s:"bs=32k":"bs=64k": /root/${FIO_SCENARIO_FILE}
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/FIOLog-64k.log

# Run FIO with block size 128k
sed --in-place=.orig -e s:"bs=64k":"bs=128k": /root/${FIO_SCENARIO_FILE}
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/FIOLog-128k.log

# Run FIO with block size 256k
sed --in-place=.orig -e s:"bs=128k":"bs=256k": /root/${FIO_SCENARIO_FILE}
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/FIOLog-256k.log

#
# Check if the SCSI disk is still connected
#
mkdir /mnt/Example
dd if=/dev/zero of=/mnt/Example/data bs=10M count=50
    if [ $? -ne 0 ]; then
        LogMsg "FIO test failed!"
        echo "FIO test failed!" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 60
    fi
sleep 1

LogMsg "=FIO test completed successfully"
echo "FIO test completed successfully" >> ~/summary.log

#
# Let ICA know we completed successfully
#
LogMsg "Updating test case state to completed"
UpdateTestState $ICA_TESTCOMPLETED

exit 0
