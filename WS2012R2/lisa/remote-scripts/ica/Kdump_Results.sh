#!/bin/bash
#####################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
#####################################################################
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
        *Red*Hat*)
            echo "RHEL";;
        Debian*)
            echo "DEBIAN";;
    esac
}

LogMsg()
{
    # To add the time-stamp to the log file
    echo `date "+%a %b %d %T %Y"` ": ${1}"
}

UpdateTestState()
{
    echo $1 >> ~/state.txt
}

CheckVmcore()
{
    if ! [[ $(find /var/crash/*/vmcore -type f -size +10M) ]]; then
        LogMsg "Test Failed. No file was found in /var/crash of size greater than 10M."
        echo "Test Failed. No file was found in /var/crash of size greater than 10M." >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
    else 
        LogMsg "Test Successful. Proper file was found."
        echo "Test Successful. Proper file was found." >> ~/summary.log
        UpdateTestState $ICA_TESTCOMPLETED
    fi
}

#
# MAIN SCRIPT
#

ICA_TESTFAILED="TestFailed"
ICA_TESTCOMPLETED="TestCompleted"
distro=`LinuxRelease`

case $distro in
    "CENTOS" | "RHEL")
        CheckVmcore
    ;;
    "UBUNTU")
        if ! [[ $(find /var/crash/2* -type f -size +10M) ]]; then
            LogMsg "Test Failed. No file was found in /var/crash of size greater than 10M."
            echo "Test Failed. No file was found in /var/crash of size greater than 10M." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        else 
            LogMsg "Test Successful. Proper file was found."
            echo "Test Successful. Proper file was found." >> ~/summary.log
            UpdateTestState $ICA_TESTCOMPLETED
        fi
    ;;
    "SLES")
        CheckVmcore
    ;;
     *)
        CheckVmcore
    ;; 
esac