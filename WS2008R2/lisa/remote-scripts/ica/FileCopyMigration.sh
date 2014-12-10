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

# copy a large file from a nfs share.  The nfs server, nfs export
# and file name are provided in the following test parameters:
#    NFS_SERVER
#    NFS_EXPORT
#    LARGE_FILENAME
#
# The script will mount the nfs share and copy the $LARGE_FILENAME
# and a file named md5sum.  The file md5sum contains the md5sum
# of the $LARGE_FILENAME.  If the md5sum matches the copied files
# md5sum, the test case passes.

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

CONSTANTS_FILE="constants.sh"


UpdateTestState()
{
    echo $1 > ~/state.txt
}


#
# Create the state.txt file so ICA knows we are running
#
echo "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

echo "Starting file copy job" > ~/summary.log

#
# Source the constants.sh file to pickup definitions from
# the ICA automation
#
if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    echo "Info: no ${CONSTANTS_FILE} found"
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

#
# Make sure constants.sh has the test parameters we require
#
echo "Checking contents of constants.sh"
if [ "${NFS_SERVER:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="Test param NFS_SERVER is missing from constants.sh"
    echo $msg
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

if [ "${NFS_EXPORT:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="Test param NFS_EXPORT is missing from constants.sh"
    echo $msg
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

if [ "${FILETOCOPY:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="Test param FILETOCOPY is missing from constants.sh"
    echo $msg
    UpdateTestState $ICA_TESTABORTED
    exit 40
fi

#
# Mount the NFS export
#
echo "Mounting nfs export ${NFS_SERVER}:${NFS_EXPORT}"

mount -o nolock ${NFS_SERVER}:${NFS_EXPORT} /mnt
if [ $? -ne 0 ]; then
    msg="Unable to mount NFS export"
    echo $msg
    UpdateTestState $ICA_TESTFAILED
    exit 50
fi

echo "Checking files exist on nfs export"

if [ ! -e /mnt/FileCopy/md5sum ]; then
    umount /mnt
    msg="The file md5sum is not in nfs export directory"
    echo $msg
    UpdateTestState $ICA_TESTFAILED
    exit 60
fi

if [ ! -e /mnt/FileCopy/${FILETOCOPY} ]; then
    umount /mnt
    msg="The file ${FILETOCOPY} is not in nfs export directory"
    echo $msg
    UpdateTestState $ICA_TESTFAILED
    exit 60
fi

#
# Remove any files that might be laying around from a previous test run
#
echo "Deleting any files from a previous test run"

rm -f ./md5sum
rm -f ./${FILETOCOPY}

#
# Copy the files
#
echo "Copying the files"

cp /mnt/FileCopy/md5sum .
if [ $? -ne 0 ]; then
    umount /mnt
    msg="Unable to copy md5sum from nfs export"
    echo $msg
    UpdateTestState $ICA_TESTFAILED
    exit 70
fi

cp /mnt/FileCopy/${FILETOCOPY} /usr/
if [ $? -ne 0 ]; then
    umount /mnt
    msg="Unable to copy ${FILETOCOPY} from nfs export"
    echo $msg
    UpdateTestState $ICA_TESTFAILED
    exit 80
fi

umount /mnt

#
# Check the MD5Sum
#
echo "Checking the md5sum of the file"

sum=`cat ./md5sum | cut -f 1 -d ' '`
fileSum=`md5sum /usr/${FILETOCOPY} | cut -f 4 -d ' '`
if [ "$sum" != "$fileSum" ]; then
    msg="md5sum of copied file does not match"
    echo $msg
    UpdateTestState $ICA_TESTFAILED
    exit 90
fi

rm -f /usr/${FILETOCOPY}

#
# Let ICA know the test completed successfully
#
echo "Test completed successfully"

UpdateTestState $ICA_TESTCOMPLETED

exit 0

