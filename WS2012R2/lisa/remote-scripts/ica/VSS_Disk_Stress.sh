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

#######################################################################
# Adds a timestamp to the log file
#######################################################################
LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}
}

#######################################################################
# Updates the summary.log file
#######################################################################
UpdateSummary()
{
    echo $1 >> ~/summary.log
}

#######################################################################
# Keeps track of the state of the test
#######################################################################
UpdateTestState()
{
    echo $1 > ~/state.txt
}

#######################################################################
# Checks what Linux distro we are running
#######################################################################
LinuxRelease()
{
    DISTRO=`grep -ihs "buntu\|Suse\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux" /etc/{issue,*release,*version}`

    case $DISTRO in
        *buntu*)
            echo "UBUNTU";;
        Fedora*)
            echo "FEDORA";;
        CentOS*)
            echo "CENTOS";;
        *suse*)
            echo "SLES";;
        Red*Hat*)
            echo "RHEL";;
        Debian*)
            echo "DEBIAN";;
        *)
            LogMsg "Unknown Distro"
            UpdateTestState "TestAborted"
            UpdateSummary "Unknown Distro, test aborted"
            exit 1
            ;; 
    esac
}

####################################################################### 
# 
# Main script body 
# 
#######################################################################

# Create the state.txt file so ICA knows we are running
UpdateTestState $ICA_TESTRUNNING

# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

# Make sure the constants.sh file exists
if [ ! -e ./constants.sh ];
then
    LogMsg "Cannot find constants.sh file."
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

# Source the constants file
if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
else
    LogMsg "ERROR: Unable to source the constants file."
    exit 1
fi

# Check if Variable in Const file is present or not
if [ ! ${iOzoneVers} ]; then
    LogMsg "No IOZONE variable in constants.sh"
    UpdateTestState "TestAborted"
    exit 1
fi

# Download iOzone
curl http://www.iozone.org/src/current/iozone$iOzoneVers.tar > iozone$iOzoneVers.tar
sts=$?
if [ 0 -ne ${sts} ]; then
    LogMsg "Error: iOzone download failed ${sts}"
    UpdateSummary "iOzone v$iOzoneVers download: Failed"
else
    LogMsg "iOzone v$iOzoneVers download: Success"
fi


# Make sure the iozone exists
IOZONE=iozone$iOzoneVers.tar
if [ ! -e ${IOZONE} ];
then
    LogMsg "Cannot find iozone file."
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

# Install make
case $(LinuxRelease) in
    "SLES")
    echo y | zypper install make gcc
    ;;
    "DEBIAN" | "UBUNTU")
    apt-get update
    apt-get install build-essential -y
    ;;
    "RHEL" | "CENTOS")
    yum groupinstall "Development Tools" -y
    ;;
    *)
    LogMsg "Distro not supported. Please install make manually."
    ;;
    esac

# Get Root Directory of tarball
ROOTDIR=`tar -tvf ${IOZONE} | head -n 1 | awk -F " " '{print $6}' | awk -F "/" '{print $1}'`

# Now Extract the Tar Ball.
tar -xvf ${IOZONE}
sts=$?
if [ 0 -ne ${sts} ]; then
	LogMsg "Failed to extract Iozone tarball"
	UpdateTestState $ICA_TESTABORTED
    	exit 1
fi

# cd in to directory    
if [ !  ${ROOTDIR} ];
then
    LogMsg "Cannot find ROOTDIR."
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

cd ${ROOTDIR}/src/current

# Compile iOzone
make linux
sts=$?
	if [ 0 -ne ${sts} ]; then
	    LogMsg "Error:  make linux  ${sts}"
	    UpdateTestState "TestAborted"
	    UpdateSummary "make linux : Failed"
	    exit 1
	else
	    LogMsg "make linux : Sucsess"

	fi

# Run Iozone
while true ; do ./iozone -ag 10G   ; done > /dev/null 2>&1 & 
sts=$?
        if [ 0 -ne ${sts} ]; then
            LogMsg "Error:  running IOzone  Failed ${sts}"
            UpdateTestState "TestAborted"
            UpdateSummary " Running IoZone  : Failed"
            exit 1
        else
            LogMsg "Running IoZone : Sucsess"
            UpdateSummary " Running Iozone : Sucsess"
        fi

UpdateTestState $ICA_TESTCOMPLETED
exit 0