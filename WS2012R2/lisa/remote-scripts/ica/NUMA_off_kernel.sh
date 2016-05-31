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
#   This script appends "numa=off" to kernel boot params
#   RHEL-6.x and 7.x are supported, and both generation 1 and 2
#   are supported as well.
#
################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

UpdateTestState() {
    echo $1 > $HOME/state.txt
}

UpdateSummary() {
    # To add the timestamp to the log file
    echo `date "+%a %b %d %T %Y"` : ${1} >> ~/summary.log
}

cd ~
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

UpdateTestState $ICA_TESTRUNNING

if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
else
    echo "ERROR: Unable to source the constants file!"
    UpdateSummary "ERROR: Unable to source the constants file!"
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    UpdateSummary "Error: unable to source utils.sh!"
    UpdateTestState $ICA_TESTABORTED
    exit 1
}

# Source constants file and initialize most common variables
UtilsInit

#
# Start the testing
#
UpdateSummary "KernelRelease=${LINUX_VERSION}"
UpdateSummary "$(uname -a)"

LinuxRelease()
{
    DISTRO=$(grep -ihs "buntu\|Suse\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux" /etc/{issue,*release,*version})

    case $DISTRO in
        *buntu*)
            echo "UBUNTU";;
        Fedora*)
            echo "FEDORA";;
        Cent??*6*)
            echo "CENTOS6";;
        Cent??*7*)
            echo "CENTOS7";;
        *SUSE*)
            echo "SLES";;
        *Red*Hat*)
            echo "RHEL";;
        *Red*6.*)
            echo "RHEL6";;
        Debian*)
            echo "DEBIAN";;
        *)
            echo "Error: Distro not supported!";;
    esac
}

ConfigRhel()
{
    if [ $VmGeneration -eq 1 ]; then
            LogMsg "Updating RHEL7 Gen$VmGeneration grub confiuration"
            sed -i '/^GRUB_CMDLINE_LINUX=/ s/"$/numa=off"/' /etc/default/grub
            if [ $? -ne 0 ]; then
                LogMsg "FAILED: Could not set the 'numa=off' value in /etc/default/grub."
                UpdateSummary "FAILED: Could not set the 'numa=off' value in /etc/default/grub."
                UpdateTestState $ICA_TESTABORTED
                exit 2
            else
                LogMsg "Success: added the 'numa=off' value."
                UpdateSummary "Success: added the 'numa=off' value."
            fi
            grub2-mkconfig -o /boot/grub2/grub.cfg
        elif [ $VmGeneration -eq 2 ]; then
            LogMsg "Update RHEL7 Gen$VmGeneration grub"
            sed -i '/^GRUB_CMDLINE_LINUX=/ s/"$/numa=off"/' /etc/default/grub
            if [ $? -ne 0 ]; then
                LogMsg "FAILED: Could not set the 'numa=off' value in /etc/default/grub."
                UpdateSummary "FAILED: Could not set the 'numa=off' value in /etc/default/grub."
                UpdateTestState $ICA_TESTABORTED
                exit 2
            else
                LogMsg "Success: added the 'numa=off' value."
                UpdateSummary "Success: added the 'numa=off' value."
            fi
            grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg
        else
            LogMsg "FAILED: Could not find VmGeneration variable."
            UpdateSummary "FAILED: Could not find VmGeneration variable."
            UpdateTestState $ICA_TESTABORTED
            exit 2
        fi
}

ConfigRhel6()
{

     if [ $VmGeneration -eq 1 ]; then
            LogMsg "Update RHEL6 Gen$VmGeneration grub"
            sed -i '/^\tkernel/ s/$/ numa=off/' /boot/grub/grub.conf
            if [ $? -ne 0 ]; then
                LogMsg "FAILED: Could not set the 'numa=off' value in /boot/grub/grub.conf."
                UpdateSummary "FAILED: Could not set the 'numa=off' value in /boot/grub/grub.conf."
                UpdateTestState $ICA_TESTABORTED
                exit 2
            else
                LogMsg "Success: added the 'numa=off' value."
                UpdateSummary "Success: added the 'numa=off' value." >> ~/summary.log
            fi
        elif [ $VmGeneration -eq 2 ]; then
            LogMsg "Update RHEL6 Gen$VmGeneration grub"
            sed -i '/^\tkernel/ s/$/ numa=off/' /boot/efi/EFI/redhat/grub.conf
            if [ $? -ne 0 ]; then
                LogMsg "FAILED: Could not set the 'numa=off' value in /boot/efi/EFI/redhat/grub.conf."
                UpdateSummary "FAILED: Could not set the 'numa=off' value in /boot/efi/EFI/redhat/grub.conf."
                UpdateTestState $ICA_TESTABORTED
                exit 2
            else
                LogMsg "Success: added the 'numa=off' value."
                UpdateSummary "Success: added the 'numa=off' value."
            fi
        else
            LogMsg "FAILED: Could not find VmGeneration variable."
            UpdateSummary "FAILED: Could not find VmGeneration variable."
            UpdateTestState $ICA_TESTABORTED
            exit 2
        fi    
}

ConfigSles()
{
   if [ $VmGeneration -eq 1 ]; then
            LogMsg "Updating SLES Gen$VmGeneration grub confiuration"
            sed -i '/^GRUB_CMDLINE_LINUX=/ s/"$/numa=off"/' /etc/default/grub
            if [ $? -ne 0 ]; then
                LogMsg "FAILED: Could not set the 'numa=off' value in /etc/default/grub."
                UpdateSummary "FAILED: Could not set the 'numa=off' value in /etc/default/grub."
                UpdateTestState $ICA_TESTABORTED
                exit 2
            else
                LogMsg "Success: added the 'numa=off' value."
                UpdateSummary "Success: added the 'numa=off' value."
            fi
            grub2-mkconfig -o /boot/grub2/grub.cfg
        elif [ $VmGeneration -eq 2 ]; then
            LogMsg "Update SLES Gen$VmGeneration grub"
            sed -i '/^GRUB_CMDLINE_LINUX=/ s/"$/numa=off"/' /etc/default/grub
            if [ $? -ne 0 ]; then
                LogMsg "FAILED: Could not set the 'numa=off' value in /etc/default/grub."
                UpdateSummary "FAILED: Could not set the 'numa=off' value in /etc/default/grub."
                UpdateTestState $ICA_TESTABORTED
                exit 2
            else
                LogMsg "Success: added the 'numa=off' value."
                UpdateSummary "Success: added the 'numa=off' value."
            fi
            grub2-mkconfig -o /boot/efi/EFI/sles12/grub.cfg
        else
            LogMsg "FAILED: Could not find VmGeneration variable."
            UpdateSummary "FAILED: Could not find VmGeneration variable."
            UpdateTestState $ICA_TESTABORTED
            exit 2
        fi
}

ConfigCentos()
{
    if [ $VmGeneration -eq 1 ]; then
            LogMsg "Update CentOS6 Gen$VmGeneration grub"
            sed -i '/^\tkernel/ s/$/numa=off/' /boot/grub/grub.conf
            if [ $? -ne 0 ]; then
                LogMsg "FAILED: Could not set the 'numa=off' value in /boot/grub/grub.conf."
                UpdateSummary "FAILED: Could not set the 'numa=off' value in /boot/grub/grub.conf."
                UpdateTestState $ICA_TESTABORTED
                exit 2
            else
                LogMsg "Success: added the 'numa=off' value."
                UpdateSummary "Success: added the 'numa=off' value." >> ~/summary.log
            fi
        elif [ $VmGeneration -eq 2 ]; then
            LogMsg "Update CentOS6 Gen$VmGeneration grub"
            sed -i '/^\tkernel/ s/$/numa=off/' /boot/efi/EFI/redhat/grub.conf
            if [ $? -ne 0 ]; then
                LogMsg "FAILED: Could not set the 'numa=off' value in /boot/efi/EFI/redhat/grub.conf."
                UpdateSummary "FAILED: Could not set the 'numa=off' value in /boot/efi/EFI/redhat/grub.conf."
                UpdateTestState $ICA_TESTABORTED
                exit 2
            else
                LogMsg "Success: added the 'numa=off' value."
                UpdateSummary "Success: added the 'numa=off' value."
            fi
        else
            LogMsg "FAILED: Could not find VmGeneration variable."
            UpdateSummary "FAILED: Could not find VmGeneration variable."
            UpdateTestState $ICA_TESTABORTED
            exit 2
        fi
}

ConfigUbuntu()
{
    if [ $VmGeneration -eq 1 ]; then
            LogMsg "Updating Ubuntu Gen$VmGeneration grub confiuration"
            sed -i '/^GRUB_CMDLINE_LINUX=/ s/"$/ numa=off"/' /etc/default/grub
            if [ $? -ne 0 ]; then
                LogMsg "FAILED: Could not set the 'numa=off' value in /etc/default/grub."
                UpdateSummary "FAILED: Could not set the 'numa=off' value in /etc/default/grub."
                UpdateTestState $ICA_TESTABORTED
                exit 2
            else
                LogMsg "Success: added the 'numa=off' value."
                UpdateSummary "Success: added the 'numa=off' value."
            fi
            grub-mkconfig -o /boot/grub/grub.cfg
        elif [ $VmGeneration -eq 2 ]; then
            LogMsg "Update Ubuntu Gen$VmGeneration grub"
            sed -i '/^GRUB_CMDLINE_LINUX=/ s/"$/numa=off"/' /etc/default/grub
            if [ $? -ne 0 ]; then
                LogMsg "FAILED: Could not set the 'numa=off' value in /etc/default/grub."
                UpdateSummary "FAILED: Could not set the 'numa=off' value in /etc/default/grub."
                UpdateTestState $ICA_TESTABORTED
                exit 2
            else
                LogMsg "Success: added the 'numa=off' value."
                UpdateSummary "Success: added the 'numa=off' value."
            fi
            grub-mkconfig -o /boot/efi/EFI/ubuntu/grub.cfg
        else
            LogMsg "FAILED: Could not find VmGeneration variable."
            UpdateSummary "FAILED: Could not find VmGeneration variable."
            UpdateTestState $ICA_TESTABORTED
            exit 2
        fi
}

case $(LinuxRelease) in
    "DEBIAN" | "UBUNTU")
        ConfigUbuntu
    ;;

    "CENTOS6")
        ConfigCentos
    ;;

    "RHEL" | "CENTOS7")
        ConfigRhel
    ;;

    "RHEL6")
        ConfigRhel6
    ;;

    "SLES")
        ConfigSles
    ;;

    *)
       echo "Error: Distro '${distro}' not supported." >> ~/summary.log
       UpdateTestState "TestAborted"
       UpdateSummary "Error: Distro '${distro}' not supported."
       exit 1
    ;;
esac

LogMsg "NUMA off setup Completed Successfully"
UpdateSummary "NUMA off setup Completed Successfully"
UpdateTestState $ICA_TESTCOMPLETED