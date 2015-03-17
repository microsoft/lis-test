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
# Stress test IOzone
# Stress_IOzone.sh
#
# Description:
# For the test to run you have to place the iozone3_420.tar archive in the
# lisablue/Tools folder on the HyperV.
#
#     TOTAL_DISKS: Number of disks attached
#     TEST_DEVICE1 = /dev/sdb
#
############################################################################

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
for drive in /dev/sd*[^0-9]
do
    sdCount=$((sdCount+1))
done

#
# Subtract the boot disk from the sdCount, then make
# sure the two disk counts match
#
sdCount=$((sdCount-1))
echo "//dev/sd* disk count = $sdCount"

if [ $sdCount != $diskCount ];
then
    echo "constants.sh disk count ($diskCount) does not match disk count from /dev/sd* ($sdCount)"
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi


case $(LinuxRelease) in
    "UBUNTU")
        FS="ext4"
        COMMAND="timeout 1800 ./iozone -az -g 50G /mnt &"
        EVAL=""
    ;;
    "SLES")
        FS="ext3"
        COMMAND="bash -c \ '(sleep 1800; kill \$$) & exec ./iozone -az -g 50G /mnt\'"
        EVAL="eval"
    ;;
     *)
        FS="ext4"
        COMMAND="timeout 1800 ./iozone -az -g 50G /mnt &"
        EVAL=""
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

for driveName in /dev/sd*[^0-9];
do
    #
    # Skip /dev/sda
    #
    if [ ${driveName} = "/dev/sda" ]; then
        continue
    fi

    fdisk -l $driveName > fdisk.dat 2> /dev/null
    # Format the Disk and Create a file system , Mount and create file on it .
    (echo d;echo;echo w)|fdisk  $driveName
    (echo n;echo p;echo 1;echo;echo;echo w)|fdisk  $driveName
    if [ "$?" = "0" ]; then
    sleep 5

   # IntegrityCheck $driveName
    mkfs.${FS}  ${driveName}1
    if [ "$?" = "0" ]; then
        LogMsg "mkfs.${FS}   ${driveName}1 successful..."
        mount   ${driveName}1 /mnt
                if [ "$?" = "0" ]; then
                LogMsg "Drive mounted successfully..."
                mkdir /mnt/Example
                dd if=/dev/zero of=/mnt/Example/data bs=10M count=50
                if [ "$?" = "0" ]; then
                    LogMsg "Successful created directory /mnt/Example"
                    LogMsg "Listing directory: ls /mnt/Example"
                    ls /mnt/Example
                    df -h
                    LogMsg "Disk test's completed for ${driveName}1"
                    echo "Disk test's is completed for ${driveName}1" >> ~/summary.log
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
    else
        LogMsg "Error in executing fdisk  ${driveName}1"
        echo "Error in executing fdisk  ${driveName}1" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 90
    fi
done



#
# Install IOzone and check if its installed successfully
#

# Make sure iozone exists
IOZONE=/root/${FILE_NAME}

if [ ! -e ${IOZONE} ];
then
    echo "Cannot find iozone file." >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

# Get Root Directory of the archive
ROOTDIR=`tar -tvf ${IOZONE} | head -n 1 | awk -F " " '{print $6}' | awk -F "/" '{print $1}'`

# Now Extract the archive
tar -xvf ${IOZONE}
sts=$?
if [ 0 -ne ${sts} ]; then
    echo "Failed to extract Iozone archive" >> ~/summary.log
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

cd ${ROOTDIR}/src/current

#
# Compile IOzone
#

make linux
sts=$?
    if [ 0 -ne ${sts} ]; then
        echo "Error:  make linux  ${sts}" >> ~/summary.log
        UpdateTestState "TestAborted"
        echo "make linux : Failed"
        exit 50
    else
        echo "make linux : Success"

    fi


LogMsg "IOzone installed successfully"

#
# Run iozone for 30 minutes
#

${EVAL} ${COMMAND}

#
# Check if SCSI disk is still online
#
mkdir /mnt/Example
dd if=/dev/zero of=/mnt/Example/data bs=10M count=50
    if [ $? -ne 0 ]; then
        LogMsg "Iozone test failed!"
        echo "Iozone test failed!" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 60
    fi
   sleep 1

LogMsg "IOzone test completed successfully"
echo "IOzone test completed successfully" >> ~/summary.log

#
# Let ICA know we completed successfully
#
LogMsg "Updating test case state to completed"
UpdateTestState $ICA_TESTCOMPLETED

exit 0

