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

UpdateSummary()
{
    echo $1 >> ~/summary.log
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}


UpdateSummary()
{
    echo $1 >> ~/summary.log
}

DEBUG_LEVEL=3

dbgprint()
{
    if [ $1 -le $DEBUG_LEVEL ]; then
        echo "$2"
    fi
}

#
# Create the state.txt file so ICA knows we are running
#
UpdateTestState $ICA_TESTRUNNING

#
# Cleanup any old summary.log files
#
if [ -e ~/summary.log ]; then
    dbgprint 1 "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

#
# Make sure the constants.sh file exists
#
#if [ ! -e ./constants.sh ];
#then
#    echo "Cannot find constants.sh file."
#    UpdateTestState $ICA_TESTABORTED
#    exit 1
#fi

#
# Count the number of SCSI= and IDE= entries in constants
#
MemTotal=` cat /proc/meminfo | grep MemTotal | awk {'print $2}' `

UpdateSummary "Total Memory before Add is $MemTotal"


mega=1024
Memory=$(($MemTotal / $mega ))

time=30
c=4
while [ $c -gt 0 ] ; do
	StressMemory=$((Memory / $c))
	stressapptest -s $time -M $StressMemory
	NewMemTotal=$( cat /proc/meminfo | grep MemTotal | awk {'print $2}' )
	if [ $NewMemTotal -gt $MemTotal   ]; then
		
		UpdateTestState $ICA_TESTCOMPLETED
		echo "Total Memory before Hot Add is $MemTotal"
		echo "Total Memory After Hot Add is $NewMemTotal"
		echo  "Test PASS : Memory hot add success"
		UpdateSummary "Total Memory After Hot Add is $NewMemTotal"
		exit 0
	fi
	(( c-- ))
done

echo "Total Memory before Hot Add is $MemTotal"
echo "Total Memory After Hot Add is $NewMemTotal"
echo -e "Test Fail : Hot Add Failed "
UpdateTestState $ICA_TESTABORTED
UpdateSummary "Total Memory After Hot Add is $NewMemTotal"

### New Meminfo after stress test

#dmesg > /root/dmesg
#dmesg -c > /dev/null  2>&1

#CALL_TRACE=`cat /root/dmesg | grep -i "hv_balloon: Memory hot add not supported"`
#if [  "$CALL_TRACE" != "" ]   ; then
	
#	echo -e "Test Fail : Hot Add Failed since there is call trace in dmesg"
#	echo -e "Test Fail : hv_balloon: Memory hot add not supported"
#	UpdateTestState $ICA_TESTABORTED
#	UpdateSummary "Total Memory After Hot Add fail is $MemTotal"
#	exit 1
	
#fi

#UpdateSummary "Total Memory After Hot Add is $NewMemTotal"
#echo  "Test PASS : Memory hot add success"
#UpdateTestState $ICA_TESTCOMPLETED

#exit 0

