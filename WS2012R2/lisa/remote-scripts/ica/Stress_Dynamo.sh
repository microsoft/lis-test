#!/bin/bash
##############################################################################
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
# Stress test IOMETER
#
# IOMETER - Stress_Dynamo.sh
#
# Description:
#   This is a semi-automated test-case. For the test to run you need
#   to have a Windows guest with IOMETER 1.1.0-rc1 installed and the 
#   Iometer for Linux (Dynamo client) archive placed in the Tools folder 
#   inside lisablue. The versions must match. In the xml you have to 
#   specify the Windows client's IP address.

# Parameters:
#     IOMETER_IP: The IP of the Windows guest
#     TOTAL_DISKS: Number of disks attached
#     TEST_DEVICE1 = /dev/sdb
#     TEST_DEVICE2 = /dev/sdc
#
############################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

CONSTANTS_FILE="constants.sh"

# To add the timestamp to the log file
LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}
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
# Source the constants.sh file to pickup definitions from
# the ICA automation
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

echo "constants disk count = $diskCount"

#
# Compute the number of sd* drives on the system.
#
sdCount=0
for drive in $(find /sys/devices/ -name sd* | grep 'sd.$' | sed 's/.*\(...\)$/\1/')
do
    sdCount=$((sdCount+1))
done

#
# Subtract the boot disk from the sdCount, then make
# sure the two disk counts match
#
sdCount=$((sdCount-1))
echo "/sys/devices disk count = $sdCount"

if [ $sdCount != $diskCount ];
then
    echo "constants.sh disk count ($diskCount) does not match disk count from /sys/devices ($sdCount)"
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

case $(LinuxRelease) in
    "UBUNTU")
        FS="ext4"
    ;;
    "SLES")
        FS="ext3"
    ;;
     *)
        FS="ext4"
    ;; 
esac

#
# For each drive, run fdisk -l and extract the drive
# size in bytes.  The setup script will add Fixed
#.vhd of size 1GB, and Dynamic .vhd of 137GB
#
FixedDiskSize=1073741824
Disk4KSize=4096
DynamicDiskSize=136365211648

firstDrive=1
mntno=1
for drive in $(find /sys/devices/ -name sd* | grep 'sd.$' | sed 's/.*\(...\)$/\1/')
do
    #
    # Skip /dev/sda
    #
  if [ ${drive} = "sda" ];
    then
        continue
    fi

    driveName="/dev/${drive}"
    fdisk -l $driveName > fdisk.dat 2> /dev/null
    # Format the Disk and Create a file system , Mount and create file on it . 
    (echo d;echo;echo w)|fdisk  $driveName
    (echo n;echo p;echo 1;echo;echo;echo w)|fdisk  $driveName
    if [ "$?" = "0" ]; then
    sleep 5

   # IntegrityCheck $driveName
    mkfs.${FS}  ${driveName}1
    mkdir /mnt/${mntno}
    if [ "$?" = "0" ]; then
        LogMsg "mkfs.${FS}   ${driveName}1 successful..."
        mount   ${driveName}1 /mnt/${mntno}
                if [ "$?" = "0" ]; then
                LogMsg "Drive mounted successfully..."
                mkdir /mnt/${mntno}/Example
                dd if=/dev/zero of=/mnt/${mntno}/Example/data bs=10M count=50
                if [ "$?" = "0" ]; then
                    LogMsg "Successful created directory /mnt/${mntno}/Example"
                    LogMsg "Listing directory: ls /mnt/${mntno}/Example"
                    ls /mnt/${mntno}/Example
                    df -h
                    LogMsg "Disk test's completed for ${driveName}1"
                    echo "Disk test's is completed for ${driveName}1" >> ~/summary.log
                else
                    LogMsg "Error in creating directory /mnt/${mntno}/Example..."
                    echo "Error in creating directory /mnt/${mntno}/Example" >> ~/summary.log
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
    else
        LogMsg "Error in executing fdisk  ${driveName}1"
        echo "Error in executing fdisk  ${driveName}1" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 90
    fi
    mntno=$((mntno+1))
done


#
# Install IOMETER and check if its installed successfully
#


# Make sure the IOMETER exists
IOMETER=/root/${FILE_NAME}

if [ ! -e ${IOMETER} ];
then
    echo "Cannot find iometer file." >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

# Get Root Directory of the archive
#ROOTDIR=iometer-1.1.0-rc1
ROOTDIR=`tar tjf ${FILE_NAME} | sed -e 's@/.*@@' | uniq`

# Now Extract the archive.
tar -xvjf ${IOMETER}
sts=$?
if [ 0 -ne ${sts} ]; then
    echo "Failed to extract IOMETER tarball" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

# cd in to directory    
if [ !  ${ROOTDIR} ];
then
    echo "Cannot find ROOTDIR." >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 40
fi

cd ${ROOTDIR}/src

#
# Change the IOStress header for compilation
#
sed -i s,"defined(IOMTR_OS_LINUX) || defined(IOMTR_OSFAMILY_NETWARE)","defined(IOMTR_OSFAMILY_NETWARE)",g IOPerformance.h

#
# Compile the application
#
make -f Makefile-$(uname).$(uname -m) all
sts=$?
    if [ 0 -ne ${sts} ]; then
        echo "Error:  make linux  ${sts}" >> ~/summary.log
        UpdateTestState "TestAborted"
        echo "make linux : Failed" 
        exit 50
    else
        echo "make linux : Success"

    fi
    
LogMsg "IOMETER installed successfully"

#
#Turn off firewall
#
service iptables stop

#
# run IOMETER
#
./dynamo -i ${IOMETER_IP} -m ${ipv4}
if [ $? -ne 0 ] ; then
    LogMsg "IOMETER test failed"
    echo "IOMETER test failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 60
fi
sleep 1

LogMsg "IOMETER test completed successfully"
echo "IOMETER test completed successfully" >> ~/summary.log

#
# Let ICA know we completed successfully
#
LogMsg "Updating test case state to completed"
UpdateTestState $ICA_TESTCOMPLETED

exit 0