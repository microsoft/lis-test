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
#     For the test to run you have to place the fio-2.1.10.tar.gz  archive and lis-ssd-test.fio in the
#     Tools folder under lisa.
#
# Parameters:
#     TOTAL_DISKS: Number of disks attached
#     TEST_DEVICE1 = /dev/sdb
#     FILE_NAME=fio-2.1.10.tar.gz
#     FIO_SCENARIO_FILE=lis-ssd-test.fio
#     TestLogDir=/path/to/log/dir/
#     
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

# Convert eol
dos2unix perf_utils.sh

# Source perf_utils.sh
. perf_utils.sh || {
    echo "Error: unable to source perf_utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}
#Apling performance parameters
setup_io_scheduler
if [ $? -ne 0 ]; then
    echo "Unable to add performance parameters."
    LogMsg "Unable to add performance parameters."
    UpdateTestState $ICA_TESTABORTED
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

echo " Kernel version: $(uname -r)" >> ~/summary.log

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
mkdir /root/${LOG_FOLDER}
LogMsg "FIO was installed successfully!"
# Run FIO with block size 8k and iodepth 1
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-1q.log

# Run FIO with block size 8k and iodepth 2
sed --in-place=.orig -e s:"iodepth=1":"iodepth=2": /root/${FIO_SCENARIO_FILE}
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-2q.log

# Run FIO with block size 8k and iodepth 4
sed --in-place=.orig -e s:"iodepth=2":"iodepth=4": /root/${FIO_SCENARIO_FILE}
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-4q.log

# Run FIO with block size 8k and iodepth 8
sed --in-place=.orig -e s:"iodepth=4":"iodepth=8": /root/${FIO_SCENARIO_FILE}
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-8q.log

Run FIO with block size 8k and iodepth 16
sed --in-place=.orig -e s:"iodepth=8":"iodepth=16": /root/${FIO_SCENARIO_FILE}
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-16q.log

# Run FIO with block size 8k and iodepth 32
sed --in-place=.orig -e s:"iodepth=16":"iodepth=32": /root/${FIO_SCENARIO_FILE}
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-32q.log

# Run FIO with block size 8k and iodepth 64
sed --in-place=.orig -e s:"iodepth=32":"iodepth=64": /root/${FIO_SCENARIO_FILE}
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-64q.log

# Run FIO with block size 8k and iodepth 128
sed --in-place=.orig -e s:"iodepth=64":"iodepth=128": /root/${FIO_SCENARIO_FILE}
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-128q.log

# Run FIO with block size 8k and iodepth 256
sed --in-place=.orig -e s:"iodepth=128":"iodepth=256": /root/${FIO_SCENARIO_FILE}
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-256q.log

# Run FIO with block size 8k and iodepth 512
sed --in-place=.orig -e s:"iodepth=256":"iodepth=512": /root/${FIO_SCENARIO_FILE}
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-512q.log

# Run FIO with block size 8k and iodepth 1024
sed --in-place=.orig -e s:"iodepth=512":"iodepth=1024": /root/${FIO_SCENARIO_FILE}
/root/${ROOTDIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-1024q.log

cd /root
zip -r ${LOG_FOLDER}.zip . -i ${LOG_FOLDER}/*
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
