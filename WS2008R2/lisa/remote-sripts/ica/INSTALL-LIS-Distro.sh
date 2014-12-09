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
#     This script was created to automate the testing of a Linux
#     Integration services.this script test the VCPU count  
#     inside the Linux VM and compare it to VCPU count given in
#     Hyper-V setting pane by performing the following
#     steps:
#	 1. Install IC from the given location.
#	 2. Verify if IC is installed.
#        3. Verify the modules are present in /lib/modules.
#        4. Reboot the VM.
#     To identify objects to compare with, we source a file
#     named constants.sh.  This file will be given to us from 
#     Hyper-V Host server.  It contains definitions like:
#         VCPU=1
#         Memory=2000
#         LIC instllable dir.

DEBUG_LEVEL=3

dbgprint()
{
    if [ $1 -le $DEBUG_LEVEL ]; then
        echo "$2"
    fi
}

if [ -e $HOME/constants.sh ]; then
 . $HOME/constants.sh
else
 echo "ERROR: Unable to source the config file."
 exit 1
fi

#if [ -e $FTM_TC/FTM-FRAMEWORK.sh ]; then
# . $FTM_TC/FTM-FRAMEWORK.sh
#else
# echo "ERROR: Unable to source the FRAMEWORK file."
# exit 1
#fi

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

UpdateTestState "TestRunning"

if [ -e ~/summary.log ]; then
    dbgprint 1 "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

UpdateSummary()
{
    echo $1 >> ~/summary.log
}


if [ ! ${TARBALL} ]; then
    dbgprint 0 "The TARBALL variable is not defined."
    dbgprint 0 "Aborting the test."
    UpdateTestState "TestAborted"
    exit 20
fi

#
# Copy the tarball from the repository server
#
dbgprint 1 "scp -i .ssh/ica_repos_id_rsa root@${REPOSITORY_SERVER}:${REPOSITORY_PATH}/${TARBALL} ."
scp -i .ssh/ica_repos_id_rsa root@${REPOSITORY_SERVER}:${REPOSITORY_PATH}/${TARBALL} .


dbgprint 3 "Extracting LIS sources from ${TARBALL}"
# The 'm' option was added to the tar extraction so that the modification
# of all the files in the tarball will be set to the time that the files
# were extracted on the Linux VM (instead of the modification time that is
# recorded in the tarball).
#
# This fixes a potential clock skew error loop when building the kernel.  When
# the ICA repository server is moved to a physical machine this workaround can
# be removed.  The whole problem is caused because of clock drift (fast clock)
# on the repository server because the repository server is a VM on Hyper-V
# (which has known clock drift problems with Linux VMs).
#
# Added the -j option since we are now using .bz2 compressed tar files.

tar -xmf ${TARBALL}
sts=$?
if [ 0 -ne ${sts} ]; then
    dbgprint 0 "tar failed to extract the LIS from the tarball: ${sts}" 
    dbgprint 0 "Aborting test."
    UpdateTestState "TestAborted"
    exit 40
fi

ROOTDIR=(`tar tf ${TARBALL} | sed -e 's@/.*@@' | uniq`)
if [ ! -e ${ROOTDIR} ]; then
    dbgprint 0 "The tar file did not create the directory: ${ROOTDIR}"
    dbgprint 0 "Aborting the test."
    UpdateTestState "TestAborted"
    exit 50
fi

cd ${ROOTDIR} 

install_ic_rhel6()
{
	dbgprint 0  "**************************************************************** "
        dbgprint 0  "This is RHEL6 and above LIS installation "
        dbgprint 0  "*****************************************************************"

	./rhel6-hv-driver-install
	sts=$?
	if [ 0 -ne ${sts} ]; then
		dbgprint 0 "Execution of install script failed: ${sts}" 
		dbgprint 0 "Aborting test."
		UpdateTestState "TestAborted"
		UpdateSummary "LIS installation on RHEL 6.x : Failed"
	    exit 0
	else
		UpdateSummary "LIS installation on RHEL 6.x : Success"
	fi

	cd tools
	
	gcc -o kvp_daemon hv_kvp_daemon.c
	sts=$?
	if [ 0 -ne ${sts} ]; then
		dbgprint 0 "Execution of install script failed: ${sts}" 
		dbgprint 0 "Aborting test."
		UpdateTestState "TestAborted"
		UpdateSummary "KVP daemon compiled : Failed"
	    exit 0
	else
		UpdateSummary "KVP daemon compiled : success"
	fi
	
	#update rc.local
	
	echo "./root/${ROOTDIR}/tools/kvp_daemon" >> /etc/rc.local
}

install_ic_sles11sp1()
{

	dbgprint 0  "**************************************************************** "	
	dbgprint 0  "This is SLES11SP1 LIS installation "	
	dbgprint 0  "*****************************************************************"	
	LINUX_OBJ=$( uname -r | sed 's#default##g' )

## Execute .C /path/to/the/build/objects M=`pwd` modules 

	make -C /usr/src/"linux-"$LINUX_OBJ"obj"/x86_64/default M=`pwd` modules
	sts=$?
	if [ 0 -ne ${sts} ]; then
		dbgprint 1 "make failed: ${sts}"
		dbgprint 1 "Aborting test."
		UpdateTestState "TestAborted"
		UpdateSummary "make -C : Fail"	
		exit 1
	else
		dbgprint 1 "make -C executed Successfully "
	fi

	KERNEL_VERSION=$( uname -r )

## Copy the *.ko into /lib/modules/.uname .r./kernel/drivers/staging/hv 
	
	cp *.ko /lib/modules/$KERNEL_VERSION/kernel/drivers/staging/hv
	sts=$?
        if [ 0 -ne ${sts} ]; then
        	dbgprint 1 "cp failed: ${sts}"
	        dbgprint 1 "Aborting test."
                UpdateTestState "TestAborted"
	        UpdateSummary "cp *.ko to hv directory : Fail"
		exit 1
        else
	        dbgprint 1 "Copied *.ko files to hv directory successfully "
        fi

	dbgprint 1 "Existing integrated LIS drivers are removed successfully ....."

## Do a depmod 
	depmod
	sts=$?
        if [ 0 -ne ${sts} ]; then
        	dbgprint 1 "depmod failed: ${sts}"
	        dbgprint 1 "Aborting test."
                UpdateTestState "TestAborted"
		exit 1
        else
                dbgprint 1 "Executed depmod successfully "
        fi

##Build the new initrd . mkinitrd 

	mkinitrd
	sts=$?
        if [ 0 -ne ${sts} ]; then
               dbgprint 1 "mkinitrd failed: ${sts}"
	       dbgprint 1 "Aborting test."
               UpdateTestState "TestAborted"
	       UpdateSummary "mkinitrd : Fail"
	       exit 1
        else
	      dbgprint 1 "Executed mkinitrd successfully "
              UpdateSummary "LIS Installation on SLES11SP1: Success"		
        fi



}

## TODO :  Need to use regular expression for more generalization

DISTRO_VER=$(cat /etc/issue)
SLESSP1="Welcome to SUSE Linux Enterprise Server 11 SP1"
RHEL6="Red Hat Enterprise Linux Server release 6.1"

if [[ "$DISTRO_VER" =~ "$SLESSP1" ]]  ; then

	install_ic_sles11sp1
#elif [[ "$DISTRO_VER" =~ "$RHEL6" ]] ; then
#	install_ic_rhel6			
else
	install_ic_rhel6	
	#echo "Not an Supported Distro"
	#exit 1
fi

UpdateSummary "Kernel Version : `uname -r` "
dbgprint 1 "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"







