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

#     This script was created to automate the testing of a Linux
#     Integration services.this script test number of scsi disk 
#     present inside guest vm is correct.
#     steps:
#	 1. Make sure we were given a configuration file.
#	 2. Verify LIC modules storvsc is loaded.
#        3. This script should be run only after LIC is installed.
#        4. VM should have a added scsi disk.
#        5. Make sure SCSi disk is present inside guest VM.

echo "########################################################"
echo "This is Test Case to Verify If number of scsi disk are correct inside vm "

DEBUG_LEVEL=3

cd ~

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

dbgprint()
{
    if [ $1 -le $DEBUG_LEVEL ]; then
        echo "$2"
    fi
}

if [ -e ~/summary.log ]; then
    dbgprint 1 "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi
#
# Convert any .sh files to Unix format
#

dbgprint 1 "Converting the files in the ica director to unix EOL"
dos2unix -f ica/* > /dev/null  2>&1
       
# Source the constants file
DEBUG_LEVEL=3

if [ -e $HOME/constants.sh ]; then
 . $HOME/constants.sh
else
 echo "ERROR: Unable to source the constants file."
 exit 1
fi

if [ -e $HOME/ica/config ]; then
	. $HOME/ica/config
else
	echo "ERROR: Unable to source the Automation Framework config file."
	UpdateTestState "TestAborted"
	exit 1
fi



UpdateTestState "TestRunning"

#Source the FTM Framework script
#if [ -e $ICA_BASE_DIR/FTM-FRAMEWORK.sh ]; then
# . $ICA_BASE_DIR/FTM-FRAMEWORK.sh
#else
# echo "ERROR: Unable to source the FRAMEWORK file."
# exit 1
#fi

# Determine wheather storvsc  modules is loaded or not
checkscsidisk()
{
	if [ ! -f /proc/scsi/scsi ]; then
	        echo "ERROR: /proc/scsi/scsi file doesn not exsist"
        	exit $E_NONEXISTENT_FILE
	else
		noofscsidisk=$(cat /proc/scsi/scsi | grep "Virtual Disk" | wc -l)
		return $noofscsidisk
		exit 0
	fi
}

#echo "Test: Checking if sotrvsc module is loaded or not. "
#verifymodule storvsc 
#sts=$?
#if [ 0 -ne ${sts} ]; then
#	dbgprint 1 "storvsc Failed to load on the system, please check if #you have LIC installed"
#	dbgprint 1 "Aborting test."
#	UpdateTestState "TestFailed"
#	exit 1
#else
#	dbgprint 1 "Storvsc Module is up and running inside guest VM."
#fi
#
# 
# Execute the checkscsidisk function to get no of SCSi disk present in #vm
# We need a No. of SCSI Disk present in VM from ICA Framework in #variable called SCSI_DISK should be present in confi file

echo "Test : Checking if scsi disk are present inside guest VM or not ?"

checkscsidisk
if [ "$noofscsidisk" = "$SCSI_DISK" ] ; then
	dbgprint 1 "Result : Number of scsi disk inside guest VM is $noofscsidisk"
        UpdateTestState "TestCompleted"

elif [ "$noofscsidisk" = "$E_NONEXISTENT_FILE" ] ; then
	 dbgprint 1 " /proc/scsi/scsi file doesn not exsist in Guest VM"
	 UpdateTestState "TestAborted"
	 exit 1
else
	dbgprint 1 "SCSI disk is not present in Guest VM "
	UpdateTestState "TestAborted"
	dbgprint 1 "Result : Number of scsi disk inside guest VM is $noofscsidisk"
	exit 1

fi

echo "#########################################################"
echo "Result : Test Completed Succesfully"
dbgprint 1 "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"


