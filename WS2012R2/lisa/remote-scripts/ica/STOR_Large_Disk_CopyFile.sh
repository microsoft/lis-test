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
#
# STOR_Large_Disk_CopyFile.sh
# Description:
#     This script will verify if you can copy 5G files on the disk, perform dd, wget, cp, nfs
#
#     The test performs the following steps:
#    1. Creates partition
#    2. Creates filesystem
#    3. Performs copy operations by copy locally, wget, copy from nfs
#    4. Unmounts partition
#    5. Deletes partition
#
########################################################################

ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"
CONSTANTS_FILE="constants.sh"

function LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

function UpdateSummary()
{
    echo $1 >> ~/summary.log
}

function UpdateTestState()
{
    echo $1 > ~/state.txt
}

# test dd 5G files, dd one 5G file locally, then copy to /mnt which is mounted to disk
function TestLocalCopyFile()
{
 LogMsg "Start to dd file"
 echo "start to dd file"
 #dd 5G files
 dd if=/dev/zero of=/root/data bs=2048 count=2500000
 file_size=`ls -l /root/data | awk '{ print $5}' | tr -d '\r'`
 LogMsg "Successful dd file as /root/data"
 LogMsg "Start to copy file to /mnt"
 echo "start to copy file to /mnt"
 cp /root/data /mnt
 rm -f /root/data
 file_size1=`ls -l /mnt/data | awk '{ print $5}' | tr -d '\r'`
 echo "file_size after dd=$file_size"
 echo "file_size after copyed= $file_size1"

 if [[ $file_size1 = $file_size ]]; then
     LogMsg "Successful copy file"
     LogMsg "Listing directory: ls /mnt/"
     ls /mnt/
     df -h
     rm -rf /mnt/*

     LogMsg "Disk test completed for ${driveName}1 with filesystem for copying 5G files ${fs} successfully"
     echo "Disk test completed for ${driveName}1 with filesystem for copying 5G files ${fs} successfully" >> ~/summary.log
 else
     LogMsg "Copying 5G file for ${driveName}1 with filesystem ${fs} failed"
     echo "Copying 5G file for ${driveName}1 with filesystem ${fs} failed" >> ~/summary.log
     UpdateTestState $ICA_TESTFAILED
     exit 80
 fi
}

# test wget file, wget one 5G file to /mnt which is mounted to disk
function TestWgetFile()
{
  file_basename=`basename $Wget_Path`
  wget -O /mnt/$file_basename $Wget_Path

  file_size=`curl -sI $Wget_Path | grep Content-Length | awk '{print $2}' | tr -d '\r'`
  file_size1=`ls -l /mnt/$file_basename | awk '{ print $5}' | tr -d '\r'`
  echo "file_size before wget=$file_size"
  echo "file_size after wget=$file_size1"

  if [[ $file_size = $file_size1 ]]; then
      LogMsg "Drive wget to ${driveName}1 with filesystem ${fs} successfully"
      echo "Drive wget to ${driveName}1 with filesystem ${fs} successfully" >> ~/summary.log
  else
      LogMsg "Drive wget to ${driveName}1 with filesystem ${fs} failed"
      echo "Drive wget to ${driveName}1 with filesystem ${fs} failed" >> ~/summary.log
      UpdateTestState $ICA_TESTFAILED
      exit 80
  fi

  rm -rf /mnt/*
}

# test copy from nfs path, dd one 5G file to /mnt2 which is mounted to nfs, then copy to /mnt
# which is mounted to disk
function TestNFSCopyFile()
{
  if [ ! -d "/mnt_2" ]; then
     mkdir /mnt_2
  fi
  mount -t nfs $NFS_Path /mnt_2

  if [ "$?" = "0" ]; then
      LogMsg "Mount nfs successfully from $NFS_Path"
      # dd 5G file
      dd if=/dev/zero of=/mnt_2/data bs=2048 count=2500000
      sleep 2

      LogMsg "Finish dd file in nfs path, start to copy to drive..."
      cp /mnt_2/data /mnt/
      sleep 2

      file_size=`ls -l /mnt_2/data | awk '{ print $5}' | tr -d '\r'`
      file_size1=`ls -l /mnt/data | awk '{ print $5}' | tr -d '\r'`
      echo "file_size after dd=$file_size"
      echo "file_size after copy=$file_size1"

      rm -rf /mnt/*
      if [ $file_size = $file_size1 ]; then
          LogMsg "Drive mount nfs and copy 5G file successfully..."
          echo "Drive mount nfs and copy 5G file successfully... ">> ~/summary.log
      else
          LogMsg "Drive mount nfs and copy 5G file  failed..."
          echo "Drive mount nfs and copy 5G file  failed..." >> ~/summary.log

          UpdateTestState $ICA_TESTFAILED
          exit 80
      fi
      umount /mnt_2
  else
      LogMsg "Mount nfs ... from $NFS_Path failed"
  fi

}

# Format the disk and create a file system, mount and create file on it.
function TestFileSystemCopy()
{
    drive=$1
    fs=$2
    parted -s -- $drive mklabel gpt
    parted -s -- $drive mkpart primary 64s -64s
    if [ "$?" = "0" ]; then
        sleep 5
        wipefs -a "${driveName}1"
        # IntegrityCheck $driveName
        mkfs.$fs   ${driveName}1
        if [ "$?" = "0" ]; then
            LogMsg "mkfs.${fs}   ${driveName}1 successful..."
            mount ${driveName}1 /mnt
            if [ "$?" = "0" ]; then
                LogMsg "Drive mounted successfully..."

                # step 1: test for local copy file
                if [[ $TestLocalCopy = "True" ]]; then
                     LogMsg "Start to test local copy file"
                     TestLocalCopyFile
                fi

                if [[ $TestWget = "True" ]]; then
                # step 2: wget 5GB file to disk
                     LogMsg "Start to test wget file"
                     TestWgetFile
                fi

                # step 3: mount nfs file, then copy file to disk
                if [[ $TestNFSCopy = "True" ]]; then
                      LogMsg "Start to test copy file from nfs mout point"
                      TestNFSCopyFile
                fi

                df -h
                # umount /mnt files
                umount /mnt
                if [ "$?" = "0" ]; then
                      LogMsg "Drive unmounted successfully..."
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

echo "Covers: ${TC_COVERED}" >> ~/summary.log

# Create the state.txt file so ICA knows we are running
UpdateTestState $ICA_TESTRUNNING

# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

# Make sure the constants.sh file exists
if [ ! -e ./constants.sh ];
then
    echo "Cannot find constants.sh file."
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

#Check for Testcase count
if [ ! ${TC_COVERED} ]; then
    LogMsg "Warning: The TC_COVERED variable is not defined."
    echo "Warning: The TC_COVERED variable is not defined." >> ~/summary.log
fi

echo "Covers: ${TC_COVERED}" >> ~/summary.log

# Check for call trace log
dos2unix check_traces.sh
chmod +x check_traces.sh
./check_traces.sh &

# Count the number of SCSI= and IDE= entries in constants
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

echo "constants disk count= $diskCount"

# Compute the number of sd* drives on the system
for driveName in /dev/sd*[^0-9];
do

    # Skip /dev/sda
    if [ ${driveName} = "/dev/sda" ]; then
        continue
    fi

    for fs in "${fileSystems[@]}"; do
        LogMsg "Start testing filesystem: $fs"
        StartTst=$(date +%s.%N)
        command -v mkfs.$fs
        if [ $? -ne 0 ]; then
            echo "File-system tools for $fs not present. Skipping filesystem $fs.">> ~/summary.log
            LogMsg "File-system tools for $fs not present. Skipping filesystem $fs."

        else
            TestFileSystemCopy $driveName $fs
            EndTst=$(date +%s.%N)
            DiffTst=$(echo "$EndTst - $StartTst" | bc)
            LogMsg "End testing filesystem: $fs; Test duration: $DiffTst seconds."
        fi
    done
done

UpdateTestState $ICA_TESTCOMPLETED

exit 0
