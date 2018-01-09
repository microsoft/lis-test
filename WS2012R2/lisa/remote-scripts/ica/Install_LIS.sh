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

###############################################################
#
# Description:
#     This script was created to automate the testing of a Linux
#     Integration services. This script detects the CDROM
#     and performs various LIS installation methods.
#
################################################################

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

UpdateSummary()
{
    echo $1 >> ~/summary_scenario_$scenario.log
}

cd ~

UpdateTestState "TestRunning"

if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
else
    UpdateSummary "ERROR: Unable to source the constants file."
    UpdateTestState "TestAborted"
    exit 1
fi

#
# Check if the CDROM module is loaded
#
CD=`lsmod | grep 'ata_piix\|isofs'`
if [[ $CD != "" ]] ; then
    module=`echo $CD | cut -d ' ' -f1`
    UpdateSummary "${module} module is present."
else
    UpdateSummary "ata_piix module is not present in VM"
    UpdateSummary "Loading ata_piix module "
    insmod /lib/modules/`uname -r`/kernel/drivers/ata/ata_piix.ko
    sts=$?
    if [ 0 -ne ${sts} ]; then
        UpdateSummary "Warning: Unable to load the ata_piix module!"
    else
        UpdateSummary "ata_piix module loaded inside the VM"
    fi
fi

# Get the mounting point
mounting_point=$(ls /dev/sr* | tail -1)
umount $mounting_point
UpdateSummary "Mount the CDROM"

mount $mounting_point /mnt
sts=$?
if [ 0 -ne ${sts} ]; then
    UpdateSummary "Error: The ISO file was not mounted"
    UpdateTestState "TestFailed"
    exit 1
fi

UpdateSummary "Info: Perform read operations on the CDROM"
cd /mnt/

if [ "$first_install" == "" ];then
    first_install=0
fi

# Deleting old LIS
if [[ "$action" == "install" && "$first_install" == 0 ]]; then
    UpdateSummary "successfully removed LIS"
    rpm -qa | grep microsoft | xargs rpm -e >> ~/LIS_log_scenario_$scenario.log
    chmod +w ~/constants.sh
    echo "first_install=1" >> ~/constants.sh
fi

./${action}.sh >> ~/LIS_log_scenario_$scenario.log 2>&1
sts=$?
if [ 0 -ne ${sts} ]; then
    UpdateSummary "Unable to run ${action}"
    UpdateTestState "TestFailed"
    exit 1
fi

# Do a double check to see if script finished running
is_finished=false
while [ $is_finished == false ]; do
    cat ~/LIS_log_scenario_$scenario.log | tail -2 | grep reboot
    if [ $? -eq 0 ]; then
        is_finished=true
    else
        sleep 2
    fi
done
sleep 60

#search for warnings
cat ~/LIS_log_scenario_$scenario.log | grep -i "Warning"
sts=$?
if [ 0 -eq ${sts} ]; then
    echo "Warning: Errors at $action LIS. Warning messages." >> LIS_log_scenario_$scenario.log
    UpdateSummary "Warnings at $action LIS"
    UpdateTestState "TestAborted"
    exit 1
fi

#search for errors
cat ~/LIS_log_scenario_$scenario.log | grep -i "Error"
sts=$?
if [ 0 -eq ${sts} ]; then
    UpdateSummary "Errors at install LIS"
    echo "ERROR: Errors at $action LIS" >> LIS_log_scenario_$scenario.log
    UpdateTestState "TestFailed"
    exit 1
fi

#search for aborts
cat ~/LIS_log_scenario_$scenario.log | grep -i "aborting"
sts=$?
if [ 0 -eq ${sts} ]; then
    UpdateSummary "Errors at $action LIS"
    echo "ERROR: Errors at $action LIS. Abort messages." >> LIS_log_scenario_$scenario.log
    UpdateTestState "TestFailed"
    exit 1
fi
UpdateSummary "LIS drivers ${action}ed successfully"

cd ~
sleep 5
umount /mnt/
if [ $? -ne 0 ]; then
    UpdateSummary "Unable to unmount the CDROM"
    UpdateTestState "TestFailed"
    exit 1
else
    UpdateSummary  "Info: CDROM unmounted successfully"
fi
UpdateSummary "CDROM mount & LIS ${action} returned no errors"

# Apply selinux policy
if [[ "$action" == "install" && ! -f hyperv-daemons.te ]]; then
    release_versions=("6.6" "6.7" "6.8" "7.1" "7.2")
    for release in ${release_versions[*]}; do
        grep $release /etc/redhat-release
        if [ $? -eq 0 ]; then
            UpdateSummary "Release version is ${release}. Applying SELinux policies"
            echo "module hyperv-daemons 1.0;
            require {
             type hypervkvp_t;
             type device_t;
             type hypervvssd_t;
             class chr_file { read write open };
            }
            allow hypervkvp_t device_t:chr_file { read write open };
            allow hypervvssd_t device_t:chr_file { read write open };" >> hyperv-daemons.te
            make -f /usr/share/selinux/devel/Makefile hyperv-daemons.pp
            if [ $? -ne 0 ]; then
                UpdateSummary "WARNING: could not compile hyperv-daemons.pp"
            fi
            semodule -s targeted -i hyperv-daemons.pp
            if [ $? -ne 0 ]; then
                UpdateSummary "WARNING: could not add module to SELinux"
            fi
        fi
    done
fi
sync
sleep 10

UpdateTestState "TestCompleted"
exit 0