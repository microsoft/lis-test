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
#
# FC_multipath_detect.sh
# Description:
#    The script will count the number of disks shown by multipath.
#    It compares the result with the one received from the host.
#    To pass test parameters into test cases, the host will create
#    a file named constants.sh. This file contains one or more
#    variable definition.
#
################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

UpdateSummary()
{
    echo $1 >> ~/summary.log
}

ConfigRedHat()
{
    yum install device-mapper-multipath >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo "Unable to install device-mapper-multipath package. The system is not registered."
        echo "Please install from ISO device-mapper-multipath package."
        UpdateTestState $ICA_TESTABORTED
    fi
    if [[ ! -e "/etc/multipath.conf" ]]; then
        /sbin/mpathconf --enable >/dev/null 2>&1
        service multipathd restart >/dev/null 2>&1
        service multipathd restart >/dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            echo "Error during service multipathd restart."
            UpdateTestState $ICA_TESTABORTED
        fi
    fi
}

ConfigDebian()
{
    apt-get install -y multipath-tools
    if [[ $? -ne 0 ]]; then
        echo "Unable to install device-mapper-multipath package."
        UpdateTestState $ICA_TESTABORTED
    fi
    
    rm /etc/multipath.conf
    touch /etc/multipath.conf
    service multipath-tools restart
    sleep 6
    if [[ $? -ne 0 ]]; then
        echo "Unable to restart multipath-tools"
        UpdateTestState $ICA_TESTABORTED
    fi
}

ConfigSuse()
{
    multipath -l >/dev/null 2>&1
    if [[ $? -eq 127 ]]; then
        zypper in -y multipath-tools
        if [[ $? -ne 0 ]]; then
            echo "Unable to install multipath-tools package."
            echo "Please install from ISO multipath-tools package."
            UpdateTestState $ICA_TESTABORTED
        fi
    fi
    chkconfig multipathd on
    if [[ $? -ne 0 ]]; then
        echo "Unable to enable multipathd."
        UpdateTestState $ICA_TESTABORTED
    fi
    service multipathd restart
    if [[ $? -ne 0 ]]; then
        echo "Unable to restart multipathd."
        UpdateTestState $ICA_TESTABORTED
    fi

}

ConfigureMultipath()
{
    GetDistro
    case $DISTRO in
        redhat*|centos*)
            ConfigRedHat
        ;;
        debian*|ubuntu*)
            ConfigDebian
        ;;
        suse*)
            ConfigSuse
        ;;
        *)
        echo "Linux distribution is not supported yet!"
        UpdateTestState $ICA_TESTFAILED
        exit 3
        ;;
    esac
}
cd ~
UpdateTestState "TestRunning"

if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
else
    echo "ERROR: Unable to source the constants file."
    UpdateTestState "TestAborted"
    exit 1
fi

#Check for Testcase covered
if [ ! ${TC_COVERED} ]; then
    echo "Warning: The TC_COVERED variable is not defined."
fi

echo "Covers : ${TC_COVERED}"

#
# Start the test
#
dos2unix utils.sh
. utils.sh

ConfigureMultipath

fcDiskCount=`multipath -ll | grep "sd" | wc -l`
if [ $? -ne 0 ]; then
    msg="Failed to count multipath disks."
    echo "Error: ${msg}"
    echo $msg
    UpdateTestState $ICA_TESTFAILED
    exit 30
fi

if [[ $fcDiskCount -ne $expectedCount ]]; then
    msg="Count missmatch between expected $expectedCount and actual $fcDiskCount"
    echo $msg
    UpdateTestState $ICA_TESTFAILED
    exit 30
else
    msg="Count match between expected $expectedCount and actual $fcDiskCount"
    echo $msg
fi

echo "Test Completed Successfully"
UpdateTestState "TestCompleted"
