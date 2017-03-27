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
# STOR_VHDXResize_ReadWrite.sh
# Description:
#     This script will perform several checks in order to ensure that
#     mounted partition is working properly.
#     The test performs the following steps:
#    1. Creates a file and saves the file size and checksum value
#    2. Creates a folder on the mounted partition
#    3. Copies the created file on that specific path
#    4. Writes, reads and deletes the copied file
#    5. Deletes the previously created folder 
#
########################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error while performing the test

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

cd ~

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

function checkResult() 
{
	if [ $? -ne 0 ]; then
		LogMsg $1
		echo $1 > ~/summary.log
		UpdateTestState $ICA_TESTFAILED
		exit 10
	fi
}

testDir=/mnt/testDir
testFile=/mnt/testDir/testFile

# Check for call trace log
dos2unix check_traces.sh
chmod +x check_traces.sh
./check_traces.sh &

#
# Read/Write mount point
#
mkdir $testDir 2> ~/summary.log
checkResult "Failed to create file $testDir"

dd if=/dev/zero of=/root/testFile bs=64 count=1
original_file_size=$(du -b /root/testFile | awk '{ print $1}')
original_checksum=$(sha1sum /root/testFile | awk '{ print $1}')
cp /root/testFile $testDir
rm -f /root/testFile

target_file_size=$(du -b $testFile | awk '{ print $1}')
if [ $original_file_size != $target_file_size ]; then
	msg="File sizes do not match: ${original_file_size} - ${target_file_size}"
	LogMsg $msg
	echo $msg >> ~/summary.log
	UpdateTestState $ICA_TESTFAILED
	exit 10
fi

target_checksum=$(sha1sum $testFile | awk '{ print $1}')
if [ $original_checksum != $target_checksum ]; then 
	msg="File checksums do not match: ${original_checksum} - ${target_checksum}"
	LogMsg $msg
	echo $msg >> ~/summary.log
	UpdateTestState $ICA_TESTFAILED
	exit 10
fi

echo 'writing to file' > $testFile 2> ~/summary.log
checkResult "Failed to write to $testFile"

ls $testFile > ~/summary.log
checkResult "Failed to list file $testFile"

cat $testFile > ~/summary.log
checkResult "Failed to read file $testFile"

# unalias rm 2> /dev/null
rm $testFile > ~/summary.log
checkResult "Failed to delete file $testFile"

rmdir $testDir 2> ~/summary.log
checkResult "Failed to delete directory $testDir"

msg="Successfully run read/write script"
LogMsg $msg
echo $msg > ~/summary.log

exit 0 