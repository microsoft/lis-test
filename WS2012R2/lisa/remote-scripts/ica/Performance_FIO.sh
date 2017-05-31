#!/bin/bash

############################################################################
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
############################################################################

############################################################################
#
# Performance_FIO.sh
#
# Description:
#     For the test to run you have to place the fio-2.1.10.tar.gz  archive and lis-ssd-test.fio in the
#     Tools folder under lisa.
#
# Parameters:
#     DISKS: Number of disks attached
#     TEST_DEVICE1 = /dev/sdb
#     FILE_NAME=fio-2.1.10.tar.gz
#     FIO_SCENARIO_FILE=lis-ssd-test.fio
#     TestLogDir=/path/to/log/dir/
#     
#
############################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # ERROR during setup of test
ICA_TESTFAILED="TestFailed"        # ERROR during test

CONSTANTS_FILE="constants.sh"
LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the time-stamp to the log file
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

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
        *SUSE*)
            echo "SLES";;
        Red*Hat*)
            echo "RHEL";;
        Debian*)
            echo "DEBIAN";;
    esac
}

#
# Create the state.txt file so ICA knows we are running
#
LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

#
# Source the constants.sh file
#
if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    echo "Warn : no ${CONSTANTS_FILE} found"
fi

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

# Convert eol
dos2unix perf_utils.sh

# Source perf_utils.sh
. perf_utils.sh || {
    echo "ERROR: unable to source perf_utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Convert eol
dos2unix utils.sh

# Source perf_utils.sh
. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

#Apling performance parameters
setup_io_scheduler
if [ $? -ne 0 ]; then
    echo "Unable to add performance parameters."
    LogMsg "Unable to add performance parameters."
    UpdateTestState $ICA_TESTABORTED
fi
echo "Kernel version: $(uname -r)" >> ~/summary.log

case $(LinuxRelease) in
    "UBUNTU")
        LogMsg "Run test on Ubuntu. Install dependencies..."
        apt-get -y install make gcc mdadm libaio-dev        
        sts=$?
        if [ 0 -ne ${sts} ]; then
            echo "Failed to install the dependencies.!" >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
            exit 41
        fi
        # Disable multipath so that it doesn't lock the disks
         if [ -e /etc/multipath.conf ]; then
            rm /etc/multipath.conf
        fi
        echo -e "blacklist {\n\tdevnode \"^sd[a-z]\"\n}" >> /etc/multipath.conf
        service multipath-tools reload
        service multipath-tools restart

    ;;
    "RHEL"|"CENTOS")
        LogMsg "Run test on RHEL. Install libaio-devel..."
        yum -y install libaio-devel mdadm
        sts=$?
        if [ 0 -ne ${sts} ]; then
            echo "Failed to install the libaio-dev library!" >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
            exit 41
        fi
    ;;
    "SLES")
        LogMsg "Run test on SLES. Install libaio-devel..."
        zypper --non-interactive install libaio-devel mdadm
        sts=$?
        if [ 0 -ne ${sts} ]; then
            echo "Failed to install the libaio-devel library!" >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
            exit 41
        fi
    ;;
esac

#Setup FIO-tool
setup_fio
if [ $? -ne 0 ]; then
    LogMsg "ERROR: FIO failed."
    echo "ERROR: FIO failed." >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
fi

#Run FIO
if [ "${TC_COVERED}" == "FIO" ]; then
    echo "INFO: Run FIO on single disk."
    fio_single_disk
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Unable to run FIO."
            echo "ERROR: Unable to run FIO." >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
        fi
else
    echo "INFO: Run FIO on multiple disks."
    fio_raid
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Unable to run FIO."
        echo "ERROR: Unable to run FIO." >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
     fi
fi
LogMsg "FIO test completed successfully"
echo "FIO test completed successfully" >> ~/summary.log
LogMsg "Updating test case state to completed"
UpdateTestState $ICA_TESTCOMPLETED