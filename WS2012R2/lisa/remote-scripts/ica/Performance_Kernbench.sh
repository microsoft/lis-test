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
# Performace test Kernbench
# Performance_Kernbench.sh
#
# Description:
#   For the test to run you have to place the kernbench-0.50.tar.bz2 archive
#    in the lisablue/Tools folder on the HyperV.
#
############################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during running of test

CONSTANTS_FILE="constants.sh"

# To add the timestamp to the log file
LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

# Checks what Linux distribution is running

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
    esac
}


#
# Create the state.txt file so ICA knows we are running
#
LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

#
# Source the constants.sh file to pickup definitions from
# the ICA automation
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

#
# Install Kernbench and check if its installed successfully
#


# Make sure the KERNBENCH exists
KERNBENCH=/root/${FILE_NAME}

if [ ! -e ${KERNBENCH} ];
then
    echo "Cannot find Kernbench file." >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

# Get Root Directory of tarball
#ROOTDIR=kernbench-0.50
ROOTDIR=`tar tjf ${FILE_NAME} | sed -e 's@/.*@@' | uniq`

# Now Extract the archive
tar -xvjf ${KERNBENCH}
sts=$?
if [ 0 -ne ${sts} ]; then
    echo "Failed to extract KERNBENCH archieve" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

# cd in to directory
if [ !  ${ROOTDIR} ];
then
    echo "Cannot find ROOTDIR." >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 40
fi

#
#Install the kernel development package, if needed
#



#
#get the kernel version and change the headers path depending on the distribution
#

VERSION=$(uname -r)
OLD="include/linux/kernel.h"

case $(LinuxRelease) in
    "CENTOS" | "SLES" | "RHEL")
        yum install kernel-devel
        NEW="/usr/src/kernels/${VERSION}/include/linux/kernel.h"
    ;;
    "UBUNTU")
        apt-get install linux-headers-$(uname -r)
        NEW="/usr/src/linux-headers-${VERSION}/include/linux/kernel.h"
    ;;
    "DEBIAN")
        apt-get install linux-headers-$(uname -r)
        NEW="/usr/include/linux/kernel.h"
    ;;
     *)
        LogMsg "Distro not supported"
        UpdateTestState "TestAborted"
        UpdateSummary " Distro not supported, test aborted"
        exit 1
    ;; 
esac


cd ${ROOTDIR}

sed -i.bak "s;$OLD;$NEW;g" kernbench

#
# run Kernbench
#
./kernbench
output=`./kernbench`

if [ $? -ne 0 ] ; then
    LogMsg "Kernbench test failed"
    echo "Kernbench test failed" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 60
fi
sleep 1

if grep -q "No kernel source found" <<<$output; then
    LogMsg "Kernbench test failed"
    echo "Kernbench test failed"  >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 60
fi
sleep 1

LogMsg "Kernbench test completed successfully"
echo "Kernbench test completed successfully" >> ~/summary.log

#
# Let ICA know we completed successfully
#
LogMsg "Updating test case state to completed"
UpdateTestState $ICA_TESTCOMPLETED

exit 0