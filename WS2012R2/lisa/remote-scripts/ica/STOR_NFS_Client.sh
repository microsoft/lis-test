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
# STOR_NFS_Client.sh
# Description:
#     This script will verify if you mount nfs, and dd file to nfs mount point.
#     Hyper-V setting pane. The test performs the following
#     step
#    1. Mount NFS server to /mnt
#    2. DD file to /mnt
#    3. Unmounts /mnt
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

function CheckForError()
{   while true; do
        [[ -f "/var/log/syslog" ]] && logfile="/var/log/syslog" || logfile="/var/log/messages"
        content=$(grep -i "Call Trace" $logfile)
        if [[ -n $content ]]; then
            LogMsg "Warning: System get Call Trace in $logfile"
            echo "Warning: System get Call Trace in $logfile" >> ~/summary.log
            break
        fi

    done
}

 function TestNFS()
 {
   umount /mnt
   mount -t nfs $NFS_Path /mnt

   if [ "$?" = "0" ]; then
       LogMsg "Mount nfs successfully... from $NFS_Path"
       # dd 5G file
       dd if=/dev/zero of=/mnt/data bs=$File_DD_Bs count=$File_DD_Count
       file_size=`ls -l /mnt/data | awk '{ print $5}' | tr -d '\r'`
       # check file size
       calulate_size=$(( $File_DD_Bs * $File_DD_Count))

       if [ $file_size = $calulate_size ]; then
           LogMsg "DD in mouted nfs bs=$File_DD_Bs count=$File_DD_Count successfully..."
           echo "DD in mounted nfs bs=$File_DD_Bs count=$File_DD_Count successfully.. ">> ~/summary.log
       else
           LogMsg "DD in mouted nfs bs=$File_DD_Bs count=$File_DD_Count failed..."
           echo "DD in mouted nfs bs=$File_DD_Bs count=$File_DD_Count  failed..." >> ~/summary.log
           UpdateTestState $ICA_TESTFAILED
       fi
       rm -rf /mnt/*
       umount /mnt
   else
       LogMsg "Mount nfs ... from $NFS_Path failed"
       echo "Mount nfs ... from $NFS_Path failed" >> ~/summary.log
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

StartTst=$(date +%s.%N)
CheckForError &
TestNFS

EndTst=$(date +%s.%N)
DiffTst=$(echo "$EndTst - $StartTst" | bc)
LogMsg "End testing filesystem: $fs; Test duration: $DiffTst seconds."

UpdateTestState $ICA_TESTCOMPLETED

exit 0
