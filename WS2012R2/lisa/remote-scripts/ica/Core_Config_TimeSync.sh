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
ICA_TESTABORTED="TestAborted"

#
# Functions definitions
#
LogMsg()
{
    # To add the time-stamp to the log file
    echo `date "+%a %b %d %T %Y"` ": ${1}"
}

UpdateTestState()
{
    echo $1 >> ~/state.txt
}

#######################################################################
#
# LinuxRelease()
#
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
        *SUSE*)
            echo "SLES";;
        *Red*Hat*)
            echo "RHEL";;
        Debian*)
            echo "DEBIAN";;
    esac
}

CheckPTPSupport()
{
    # Check for ptp support
    ptp=$(cat /sys/class/ptp/ptp0/clock_name)
    if [ "$ptp" != "hyperv" ]; then
        msg="PTP not supported for current distro."
        LogMsg $msg
        echo $msg >> summary.log
        exit 0
    fi
}
#######################################################################
#
# ConfigRhel()
#
#######################################################################
ConfigChrony()
{
    echo "refclock PHC /dev/ptp0 poll 3 dpoll -2 offset 0" >> /etc/chrony.conf
    systemctl restart chronyd
    if [ $? -ne 0 ]; then
        msg="ERROR: Chronyd service failed to restart"
        LogMsg $msg
        echo $msg >> summary.log
        UpdateTestState "TestAborted"
        exit 1
    fi
}

ConfigPtp4l()
{
    sed -i "s/time_stamping=\S*/time_stamping     software/g" /etc/ptp4l.conf
    systemctl enable ptp4l
    systemctl start ptp4l
    if [ $? -ne 0 ]; then
        msg="ERROR: Failed to config ptp4l"
        LogMsg $msg
        echo $msg >> summary.log
        UpdateTestState "TestAborted"
        exit 1
    fi
}

InstallChrony()
{
    case $1 in
    "CENTOS" | "RHEL")
        yum install chrony -y
    ;;
    "UBUNTU")
        apt-get install -y chrony
    ;;
    "SLES")
        zypper install -y chrony
    ;;
    *)
        msg="ERROR: Distro '${distro}' not supported"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState "TestAborted"
        exit 1
    ;;
    esac
    
    if [ $? -ne 0]; then
        msg="ERROR: Unable to install chrony"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState "TestAborted"
        exit 1
    fi
}
#######################################################################
#
# Main script body
#
#######################################################################
UpdateTestState $ICA_TESTRUNNING
cd ~
# Delete any old summary.log file
if [ -e ~/summary.log ]; then
    rm -f ~/summary.log
fi

touch ~/summary.log

dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 1
}

#
# Configure ptp - this has distro specific behaviour
#
distro=`LinuxRelease`
CheckPTPSupport
InstallChrony $distro
ConfigChrony
exit 0


