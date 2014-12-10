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

## Check if Variable in Const file is present or not
if [ ! ${DISK} ]; then
	dbgprint 1 "The SCSI_DISK variable is not defined."
	dbgprint 1 "aborting the test."
	UpdateTestState "TestAborted"
	exit 1
fi


checkdisk()
{

	TOTAL_DISK=$(find /sys/devices/ -name  sd* | grep host | wc -l )
	ROOT_DISK=$(find /sys/devices/ -name  sda* | grep host | wc -l)
	NEW_DISK=$(($TOTAL_DISK-$ROOT_DISK))

	return $NEW_DISK
}

echo "Test : Checking if scsi disk are present inside guest VM or not ?"

checkdisk
if [ "$NEW_DISK" = "$DISK" ] ; then
	
	 dbgprint 1 "*********************************************************************************"

	dbgprint 1 "Result : New disk is present inside guest VM "

	dbgprint 1 "*********************************************************************************"
	dbgprint 1 " fdisk -l is : "
	fdisk -l
	dbgprint 1 "*********************************************************************************"

        UpdateTestState "TestCompleted"
	
else
	dbgprint 1 "Result : New disk is not present in Guest VM "

	UpdateTestState "TestAborted"
	dbgprint 1 "Result : Number of scsi disk inside guest VM is $noofscsidisk"
	dbgprint 1 "*********************************************************************************"
        dbgprint 1 " fdisk -l is : "
        fdisk -l
        dbgprint 1 "*********************************************************************************"

	exit 1

fi

echo "#########################################################"
echo "Result : Test Completed Succesfully"
dbgprint 1 "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"



