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
ICA_TESTFAILED="TestFailed"

unsupported_msg="INFO: OS version too old for PHC refclock support, skipped config step"

UpdateTestState() {
    echo $1 >> ~/state.txt
}

dos2unix utils.sh
#
# Source utils.sh to get more utils
#
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    exit 1
}

#
# Source constants file and initialize most common variables
#
. constants.sh || {
    echo "Error: unable to source constants.sh!"
    exit 1
}

UtilsInit

CheckPTPSupport()
{
    # Check for ptp support
    ptp=$(cat /sys/class/ptp/ptp0/clock_name)
    if [ "$ptp" != "hyperv" ]; then
        LogMsg "PTP not supported for current distro."
        UpdateSummary "PTP not supported for current distro."
        ptp="off"
    fi
}

ConfigRhel()
{
    chronyd -v
    if [ $? -ne 0 ]; then
        yum install chrony -y
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Failed to install chrony"
            UpdateSummary "ERROR: Failed to install chrony"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi
    
    CheckPTPSupport
    if [[ $ptp == "hyperv" ]]; then
        grep "refclock PHC /dev/ptp0 poll 3 dpoll -2 offset 0" /etc/chrony.conf
        if [ $? -ne 0 ]; then
            echo "refclock PHC /dev/ptp0 poll 3 dpoll -2 offset 0" >> /etc/chrony.conf
        fi
    fi

    service chronyd restart
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Chronyd service failed to restart"
        UpdateSummary "ERROR: Chronyd service failed to restart"
    fi
    
    if [[ $Chrony == "off" ]]; then
        service chronyd stop
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Unable to stop chronyd"
            UpdateSummary "ERROR: Unable to stop chronyd"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        service ntpd stop
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Unable to stop NTPD"
            UpdateSummary "ERROR: Unable to stop NTPD"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi
}

ConfigSles()
{
    chronyd -v
    if [ $? -ne 0 ]; then
        zypper install -y chrony
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Failed to install chrony"
            UpdateSummary "ERROR: Failed to install chrony"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi

    CheckPTPSupport
    if [[ $ptp == "hyperv" ]]; then
        grep "refclock PHC /dev/ptp0 poll 3 dpoll -2 offset 0" /etc/chrony.conf
        if [ $? -ne 0 ]; then
            echo "refclock PHC /dev/ptp0 poll 3 dpoll -2 offset 0" >> /etc/chrony.conf
        fi
    fi

    systemctl restart chronyd
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Chronyd service failed to restart"
        UpdateSummary "ERROR: Chronyd service failed to restart"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    if [[ $Chrony == "off" ]]; then
        service chronyd stop
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Unable to stop chronyd"
            UpdateSummary "ERROR: Unable to stop chronyd"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        service ntpd stop
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Unable to stop NTPD"
            UpdateSummary "ERROR: Unable to stop NTPD"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi
}

ConfigUbuntu()
{
    chronyd -v
    if [ $? -ne 0 ]; then
        apt update
        apt install chrony -y
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Failed to install chrony"
            UpdateSummary "ERROR: Failed to install chrony"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi

    CheckPTPSupport
    if [[ $ptp == "hyperv" ]]; then
        grep "refclock PHC /dev/ptp0 poll 3 dpoll -2 offset 0" /etc/chrony/chrony.conf
        if [ $? -ne 0 ]; then
            echo "refclock PHC /dev/ptp0 poll 3 dpoll -2 offset 0" >> /etc/chrony/chrony.conf
        fi
    fi

    systemctl restart chrony
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Chronyd service failed to restart"
        UpdateSummary "ERROR: Chronyd service failed to restart"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    if [[ $Chrony == "off" ]]; then
        service chrony stop
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Unable to stop chrony"
            UpdateSummary "ERROR: Unable to stop chrony"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi

        service ntp stop
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Unable to stop NTP"
            UpdateSummary "ERROR: Unable to stop NTP"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi
}

#
# Main script body
#
GetDistro
GetOSVersion
case $DISTRO in
    centos* | redhat* | fedora*)
        if [[ $os_RELEASE.$os_UPDATE =~ ^5.* ]] || [[ $os_RELEASE.$os_UPDATE =~ ^6.* ]] ; then
            LogMsg "$unsupported_msg"
            UpdateSummary "$unsupported_msg"
        else
            ConfigRhel
        fi
    ;;
    ubuntu* | debian*)
        if [[ $os_RELEASE =~ ^14.04* ]] ; then
            LogMsg "$unsupported_msg"
            UpdateSummary "$unsupported_msg"
        else
            ConfigUbuntu
        fi
    ;;
    suse*)
        ConfigSles
    ;;
     *)
        LogMsg "WARNING: Distro not supported."
        UpdateSummary "WARNING: Distro not supported."
    ;;
esac

UpdateTestState $ICA_TESTCOMPLETED
