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

########################################################################
# installlis.sh
# Description:
#     This script was created to automate the testing of a Linux
#     Integration services.
#     Install LIS from RPM's. 
#	 1. Make sure we have a constants.sh file.
#     
#
################################################################


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
dbgprint 1 "scp -i .ssh/ica_repos_id_rsa root@${LIS_BUILD_SERVER}/${TARBALL} ."
scp -i .ssh/rhel5_id_rsa root@${LIS_BUILD_SERVER}/${TARBALL} .


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

./install.sh
sts=$?
    if [ 0 -ne ${sts} ]; then
        dbgprint 0 "Installation of LIS failed"
        dbgprint 0 "Aborting the test."
        UpdateTestState "TestAborted"
        UpdateSummary "LIS Installation: Failed"
        exit 60
    fi
    
UpdateSummary "LIS Installation:    Success"
dbgprint 1 "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"







