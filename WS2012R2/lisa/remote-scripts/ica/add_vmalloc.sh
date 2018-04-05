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
# Description:
#   This script appends "vmalloc=<value>" to kernel boot params
#   RHEL-6.x and 7.x are supported, and both generation 1 and 2
#   are supported as well.
#
################################################################
ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
declare os_VENDOR os_RELEASE os_UPDATE os_PACKAGE os_CODENAME

#######################################################################
# Adds a timestamp to the log file
#######################################################################
LogMsg() {
    echo `date "+%a %b %d %T %Y"` : ${1}
}

#######################################################################
# Updates the summary.log file
#######################################################################
UpdateSummary() {
    echo $1 >> ~/summary.log
}

#######################################################################
# Keeps track of the state of the test
#######################################################################
UpdateTestState() {
    echo $1 > ~/state.txt
}

####################################################################### 
#
# Main script body 
#
#######################################################################
# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

# Create the state.txt file so ICA knows we are running
UpdateTestState $ICA_TESTRUNNING

# Source the constants file
if [ -e constants.sh ]; then
    . constants.sh
else
    LogMsg "WARN: Unable to source the constants file."
fi

dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    UpdateTestState $ICA_TESTABORTED
    exit 2
}

uname -a | grep i686
if [ $? -eq 0 ]; then
    msg="32 bit architecture was detected."
    LogMsg "$msg"
    UpdateSummary $msg
else 
    msg="64 bit architecture was detected."
    LogMsg "$msg"
    UpdateSummary $msg
    UpdateTestState $ICA_TESTCOMPLETED
    return True
fi

# Source constants file and initialize most common variables
UtilsInit

ConfigRhel6() {
     if [ $VmGeneration -eq 1 ]; then
            LogMsg "Update RHEL6 Gen$VmGeneration grub"
            grep -i vmalloc /boot/grub/grub.conf
            if [ $? -eq 0 ]; then
                sed -r -i "s/vmalloc=[0-9]+MB/vmalloc=$value/g" /boot/grub/grub.conf
            else
                sed -i "/^\tkernel/ s/$/ vmalloc=$value/" /boot/grub/grub.conf
            fi
            if [ $? -ne 0 ]; then
                LogMsg "FAILED: Could not set the 'vmalloc=$value' value in /boot/grub/grub.conf."
                UpdateSummary "FAILED: Could not set the 'vmalloc=$value' value in /boot/grub/grub.conf."
                UpdateTestState $ICA_TESTABORTED
                exit 2
            else
                LogMsg "Success: added the 'vmalloc=$value' value."
                UpdateSummary "Success: added the 'vmalloc=$value' value."
            fi
        elif [ $VmGeneration -eq 2 ]; then
            LogMsg "Update RHEL6 Gen$VmGeneration grub"
            grep -i vmalloc /boot/efi/EFI/redhat/grub.conf
            if [ $? -eq 0 ]; then
                sed -r -i "s/vmalloc=[0-9]+MB/vmalloc=$value/g" /boot/efi/EFI/redhat/grub.conf
            else
                sed -i "/^\tkernel/ s/$/ vmalloc=$value/" / /boot/efi/EFI/redhat/grub.conf
            fi
            if [ $? -ne 0 ]; then
                LogMsg "FAILED: Could not set the 'vmalloc=$value' value in /boot/efi/EFI/redhat/grub.conf."
                UpdateSummary "FAILED: Could not set the 'vmalloc=$value' value in /boot/efi/EFI/redhat/grub.conf."
                UpdateTestState $ICA_TESTABORTED
                exit 2
            else
                LogMsg "Success: added the 'vmalloc=$value' value."
                UpdateSummary "Success: added the 'vmalloc=$value' value."
            fi
        else
            LogMsg "FAILED: Could not find VmGeneration variable."
            UpdateSummary "FAILED: Could not find VmGeneration variable."
            UpdateTestState $ICA_TESTABORTED
            exit 2
        fi
}

ConfigCentos() {
    if [[ $VmGeneration -eq 1 ]]; then
            LogMsg "Update CentOS6 Gen$VmGeneration grub"
            grep -i vmalloc /boot/grub/grub.conf
            if [ $? -eq 0 ]; then
                sed -r -i "s/vmalloc=[0-9]+MB/vmalloc=$value/g" /boot/grub/grub.conf
            else
                sed -i "/^\tkernel/ s/$/ vmalloc=$value/" /boot/grub/grub.conf
            fi
            if [ $? -ne 0 ]; then
                LogMsg "FAILED: Could not set the 'vmalloc=$value' value in /boot/grub/grub.conf."
                UpdateSummary "FAILED: Could not set the 'vmalloc=$value' value in /boot/grub/grub.conf."
                UpdateTestState $ICA_TESTABORTED
                exit 2
            else
                LogMsg "Success: added the 'vmalloc=$value' value."
                UpdateSummary "Success: added the 'vmalloc=$value' value."
            fi
        elif [[ $VmGeneration -eq 2 ]]; then
            LogMsg "Update CentOS6 Gen$VmGeneration grub"
            grep -i vmalloc /boot/efi/EFI/redhat/grub.conf
            if [ $? -eq 0 ]; then
                sed -r -i "s/vmalloc=[0-9]+MB/vmalloc=$value/g" /boot/efi/EFI/redhat/grub.conf
            else
                sed -i "/^\tkernel/ s/$/ vmalloc=$value/" /boot/efi/EFI/redhat/grub.conf
            fi
            if [ $? -ne 0 ]; then
                LogMsg "FAILED: Could not set the 'vmalloc=$value' value in /boot/efi/EFI/redhat/grub.conf."
                UpdateSummary "FAILED: Could not set the 'vmalloc=$value' value in /boot/efi/EFI/redhat/grub.conf."
                UpdateTestState $ICA_TESTABORTED
                exit 2
            else
                LogMsg "Success: added the 'vmalloc=$value' value."
                UpdateSummary "Success: added the 'vmalloc=$value' value."
            fi
        else
            LogMsg "FAILED: Could not find VmGeneration variable."
            UpdateSummary "FAILED: Could not find VmGeneration variable."
            UpdateTestState $ICA_TESTABORTED
            exit 2
        fi
}

case $DISTRO in
    "centos_6")
        ConfigCentos
    ;;

    "redhat_6")
        ConfigRhel6
    ;;

    *)
       UpdateSummary "Warning: Distro '${DISTRO}' not supported."
    ;;
esac

LogMsg "vmalloc=$value setup Completed Successfully"
UpdateSummary "vmalloc=$value setup Completed Successfully"
UpdateTestState $ICA_TESTCOMPLETED
