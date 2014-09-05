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


ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}



UpdateSummary()
{
    echo $1 >> ~/summary.log
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

 CheckForError()
{
    while true; do
        a=`tail /var/log/messages | grep "No additional sense information"`
        if [[ -n $a ]]; then
            UpdateSummary "System hanging at mkfs $1"
            sleep 1
            UpdateTestState $ICA_TESTABORTED
            exit 1
        fi
    done
 }

IntegrityCheck(){
targetDevice=$1
testFile="/dev/shm/testsource"
blockSize="100000000"
blocks="1"
_gb=1073741824
targetSize=$(blockdev --getsize64 $targetDevice)
if [ "$targetSize" -gt "$_gb" ] ; then
  targetSize=$_gb
  blocks=$(($targetSize / $blockSize))
 fi
dd if=/dev/urandom of=$testFile bs=$blockSize count=1 status=noxfer 2> /dev/null
checksum=$(sha1sum $testFile | cut -d " " -f 1)
LogMsg "Checking ${blocks} blocks"
for ((y=0 ; y<blocks ; y++)) ; do
  LogMsg "Writing block $y to device $targetDevice ..." 
  dd if=$testFile of=$targetDevice bs=$blockSize count=1 seek=$y status=noxfer 2> /dev/null
  testChecksum=$(dd if=$targetDevice bs=$blockSize count=1 skip=$y status=noxfer 2> /dev/null | sha1sum | cut -d " " -f 1)
  if [ "$checksum" == "$testChecksum" ] ; then
    LogMsg "Checksum matched for block $y"
  else
    LogMsg "Checksum mismatch at block $y"
    echo "Checksum mismatch for block $y" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
  fi
done
echo "Checksum test pass for ${y} out of ${blocks} blocks on drive ${targetDevice}" >> ~/summary.log
rm -f $testFile
}

TestFileSystem()
{
    drive=$1
    fs=$2
    # Format the Disk and Create a file system , Mount and create file on it . 
    parted -s -- $drive mklabel gpt
    parted -s -- $drive mkpart primary 64s -64s
    if [ "$?" = "0" ]; then
        sleep 5
        wipefs -a "${driveName}1"
        CheckForError ${driveName}1 &
        # IntegrityCheck $driveName
        mkfs.$fs   ${driveName}1
        if [ "$?" = "0" ]; then
            LogMsg "mkfs.${fs}   ${driveName}1 successful..."
            mount ${driveName}1 /mnt
            if [ "$?" = "0" ]; then
                LogMsg "Drive mounted successfully..."
                mkdir /mnt/Example
                dd if=/dev/zero of=/mnt/Example/data bs=10M count=50
                if [ "$?" = "0" ]; then
                    LogMsg "Successful created directory /mnt/Example"
                    LogMsg "Listing directory: ls /mnt/Example"
                    ls /mnt/Example
                    df -h
                    rm -rf /mnt/*
                    umount /mnt
                    if [ "$?" = "0" ]; then
                        LogMsg "Drive unmounted successfully..."
                    fi
                    LogMsg "Disk test completed for ${driveName}1 with filesystem ${fs}"
                    echo "Disk test is completed for ${driveName}1  with filesystem ${fs}" >> ~/summary.log
                else
                    LogMsg "Error in creating directory /mnt/Example... for ${fs}"
                    echo "Error in creating directory /mnt/Example for ${fs}" >> ~/summary.log
                fi
            else
                LogMsg "Error in mounting drive..."
                echo "Drive mount : Failed" >> ~/summary.log
                UpdateTestState $ICA_TESTFAILED
            fi
        else
            LogMsg "Error in creating file system ${fs}.."
            echo "Creating Filesystem : Failed ${fs}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    else
        LogMsg "Error in executing parted  ${driveName}1 for ${fs}"
        echo "Error in executing parted  ${driveName}1 for ${fs}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
    fi  

    # Perform Data integrity test 

    IntegrityCheck ${driveName}1
}
# Source the constants file
if [ -e ~/${CONSTANTS_FILE} ]; then
    source ~/${CONSTANTS_FILE}
else
    msg="Error: in ${CONSTANTS_FILE} file"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

echo "Covers : ${TC_COVERED}" >> ~/summary.log

#
# Create the state.txt file so ICA knows we are running
#
UpdateTestState $ICA_TESTRUNNING

#
# Cleanup any old summary.log files
#
if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

#
# Make sure the constants.sh file exists
#
if [ ! -e ./constants.sh ];
then
    echo "Cannot find constants.sh file."
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

#Check for Testcase count
if [ ! ${TC_COVERED} ]; then
    LogMsg "Error: The TC_COVERED variable is not defined."
    echo "Error: The TC_COVERED variable is not defined." >> ~/summary.log
    UpdateTestState "TestAborted"
    exit 1
fi

echo "Covers : ${TC_COVERED}" >> ~/summary.log

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
    for fs in ${fileSystems[@]}; do
        LogMsg "Testing filesystem: $fs"
        TestFileSystem $driveName $fs
    done
done

UpdateTestState $ICA_TESTCOMPLETED

exit 0