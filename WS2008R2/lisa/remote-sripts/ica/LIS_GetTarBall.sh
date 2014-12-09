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

# Description:
#   This script gets all the data from attched ISO and archives to .tar.gz
# 	It is used to create LIS tarballs to maintain LISA repositories    

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

LogMsg "########################################################"


UpdateTestState()
{
    echo $1 > ~/state.txt
}

cd ~

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

UpdateSummary()
{
    echo $1 >> ~/summary.log
}

if [ -e ~/constants.sh ]; then
	. ~/constants.sh
else
	LogMsg "ERROR: Unable to source the constants file."
	UpdateTestState "TestAborted"
	exit 1
fi


# Convert any .sh files to Unix format
#

dos2unix -f ~/*.sh > /dev/null  2>&1

# check if CDROM  module is loaded or no 
if [ -e /lib/modules/$(uname -r)/kernel/drivers/ata/ata_piix.ko ]; then
CD=`lsmod | grep ata_piix`
if [[ $CD != "" ]] ; then
	LogMsg "ata_piix module is present"
else
	LogMsg "ata_piix module is not present in VM"
	LogMsg "Loading ata_piix module "
	insmod /lib/modules/$(uname -r)/kernel/drivers/ata/ata_piix.ko
	sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "Unable to load ata_piix module"
	    LogMsg "Aborting test."
	    UpdateSummary "ata_piix load : Failed"
        UpdateTestState "TestAborted"
	    exit 1
    else
	    LogMsg "ata_piix module loaded inside the VM"
	    
    fi
fi

fi

sleep 2
	

LogMsg "##### Mount the CDROM #####"
mount /dev/cdrom /mnt/
sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "Unable to mount the CDROM"
	    LogMsg "Mount CDROM failed: ${sts}"
	    LogMsg "Aborting test."
        UpdateTestState "TestAborted"
	    exit 1
    else
	    LogMsg  "CDROM is mounted successfully inside the VM"
        LogMsg  "CDROM is detected inside the VM"
    fi

LogMsg "##### Copy contents of CDROM ######"
mkdir LIS
cp -r /mnt/* LIS

sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "Unable to copy data from the CDROM"
	    LogMsg "Copy data from CDROM failed: ${sts}"
	    LogMsg "Aborting test."
        UpdateTestState "TestAborted"
	    exit 1
    else
        LogMsg "Data copy successful from the CDROM"
	    
    fi

#Create TARBALL
TARBALL=$( echo ${IsoFilename} | cut -f 1 -d '.' )
TARBALL="${TARBALL}.tar.gz"

tar -cmf ${TARBALL} ./LIS

sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "Unable to create TARBALL"
	    LogMsg "create TARBALL from CDROM failed: ${sts}"
	    LogMsg "Aborting test."
        UpdateTestState "TestAborted"
	    exit 1
    else
        LogMsg "create TARBALL successful from the CDROM"
		UpdateSummary "Create TARBALL : Success"
		UpdateSummary "${TARBALL} will be copied to Logs Directory"
	    
    fi
	
#copy to Repository
# scp -r ./${TARBALL} .ssh/rhel5_id_rsa roost@${REPOSITORY_SERVER}:${REPOSITORY_PATH}

# sts=$?
    # if [ 0 -ne ${sts} ]; then
        # LogMsg "Unable to upload TARBALL to repository"
	    # LogMsg "Upload TARBALL  failed: ${sts}"
	    # LogMsg "Aborting test."
        # UpdateTestState "TestAborted"
	    # exit 1
    # else
        # LogMsg "TARBALL successfully uploaded to repository"
	    
    # fi
	

LogMsg "#########################################################"
LogMsg "Result : Test Completed Succesfully"
LogMsg "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"



















