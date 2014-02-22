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

###############################################################
# Description:
#     This script was created to automate the testing of a Linux
#     Integration services.This script detects the CDROM    
#     and performs read   operations .
#     
################################################################


LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

UpdateSummary()
{
    echo $1 >> ~/summary.log
}

cd ~
UpdateTestState "TestRunning"

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

if [ -e $HOME/constants.sh ]; then
	. $HOME/constants.sh
else
	LogMsg "ERROR: Unable to source the constants file."
	UpdateTestState "TestAborted"
	exit 1
fi

#Check for Testcase count
if [ ! ${TC_COVERED} ]; then
    LogMsg "Error: The TC_COVERED variable is not defined."
	echo "Error: The TC_COVERED variable is not defined." >> ~/summary.log
    UpdateTestState "TestFailed"
    exit 1
fi

echo "Covers : ${TC_COVERED}" >> ~/summary.log

#
# check if CDROM  module is loaded or no 
#
CD=`lsmod | grep ata_piix`
if [[ $CD != "" ]] ; then
	LogMsg "ata_piix module is present"
else
	LogMsg "ata_piix module is not present in VM"
	LogMsg "Loading ata_piix module "
	insmod /lib/modules/`uname -r`/kernel/drivers/ata/ata_piix.ko
	sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "Unable to load ata_piix module"
	    LogMsg "Aborting test."
	    UpdateSummary "ata_piix load : Failed"
        UpdateTestState "TestFailed"
	    exit 1
    else
	    LogMsg "ata_piix module loaded inside the VM"
	    UpdateSummary " ata_piix module loaded : Success"
    fi
fi
	

LogMsg "##### Mount the CDROM #####"
mount /dev/dvd /mnt/
sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "Unable to mount the CDROM"
	    LogMsg "Mount CDROM failed: ${sts}"
	    LogMsg "Aborting test."
        UpdateTestState "TestFailed"
	    exit 1
    else
	    LogMsg  "CDROM is mounted successfully inside the VM"
        LogMsg  "CDROM is detected inside the VM"
	    UpdateSummary " CDROM detected : Success"
    fi

LogMsg "##### Perform read  operations on the CDROM ######"
cd /mnt/

ls /mnt
sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "Unable to read datafrom the CDROM"
	    LogMsg "Read data from CDROM failed: ${sts}"
	    LogMsg "Aborting test."
        UpdateTestState "TestFailed"
	    exit 1
    else
        LogMsg "Data read successfully from the CDROM"
	    UpdateSummary "Data read inside CDROM : Success"
    fi
cd ~
umount /mnt/
sts=$?      
    if [ 0 -ne ${sts} ]; then
        LogMsg "Unable to unmount the CDROM"
	    LogMsg "umount failed: ${sts}"
	    LogMsg "Aborting test."
            UpdateTestState "TestFailed"
	    exit 1
    else
        LogMsg  "CDROM unmounted successfully"
	    UpdateSummary " CDROM unmount: Success"
           
    fi



LogMsg "#########################################################"
LogMsg "Result : Test Completed Succesfully"
LogMsg "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"



















