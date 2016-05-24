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
#     and performs read operations .
#
################################################################

UpdateSummary()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

UpdateSummary()
{
    echo $1 >> ~/summary.log
}

cd ~
UpdateTestState "TestRunning"

if [ -e ~/summary.log ]; then
    UpdateSummary "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

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
        UpdateSummary "Unable to load ata_piix module"
        UpdateTestState "TestFailed"
        exit 1
    else
        UpdateSummary "ata_piix module loaded inside the VM"
    fi
fi
umount /mnt
sleep 1
UpdateSummary "Mount the CDROM"
mount /dev/cdrom /mnt
sts=$?
if [ 0 -ne ${sts} ]; then
    UpdateSummary "Mount CDROM failed: ${sts}"
    UpdateSummary "Aborting test."
    UpdateTestState "TestFailed"
    exit 1
else
    UpdateSummary  "CDROM is mounted successfully inside the VM"
fi

UpdateSummary "Perform read operations on the CDROM"
cd /mnt/

if [ "$first_install" == "" ];then
 first_install=0
fi
 
# Deleting old LIS
if [[ "$action" == "install" && "$first_install" == 0 ]]; then
    UpdateSummary "successfully removed LIS"
    rpm -qa | grep microsoft | xargs rpm -e >> ~/LIS_log.log
    chmod +w ~/constants.sh
    echo "first_install=1" >> ~/constants.sh
fi

./$action.sh >> ~/LIS_log.log 2>&1
sts=$?
if [ 0 -eq ${sts} ]; then
    UpdateSummary "Unable to run ${action}"
    UpdateTestState "TestFailed"
    exit 1
else
    UpdateSummary "LIS drivers ${action}ed successfully"
fi

#search for fail
cat ~/LIS_log.log | grep "fail"
sts=$?
if [ 0 -eq ${sts} ]; then
    UpdateSummary "Fail at $action LIS"
    echo "ERROR: Errors at $action LIS. Fail messages." >> LIS_log.log
    UpdateTestState "TestFailed"
    exit 1
fi

#search for warnings
cat ~/LIS_log.log | grep "arning"
sts=$?
if [ 0 -eq ${sts} ]; then
    echo "Warnnin: Errors at $action LIS. Warnning messages." >> LIS_log.log
    UpdateSummary "Warnings at $action LIS"
fi

#search for error
cat ~/LIS_log.log | grep "Error"
sts=$?
if [ 0 -eq ${sts} ]; then
    UpdateSummary "Errors at install LIS"
    echo "ERROR: Errors at $action LIS" >> LIS_log.log
    UpdateTestState "TestFailed"
    exit 1
fi

#search for error
cat ~/LIS_log.log | grep "aborting"
sts=$?
if [ 0 -eq ${sts} ]; then
    UpdateSummary "Errors at $action LIS"
    echo "ERROR: Errors at $action LIS. Abort messages." >> LIS_log.log
    UpdateTestState "TestFailed"
    exit 1
fi

cd ~
umount /mnt/
sts=$?
if [ 0 -ne ${sts} ]; then
    UpdateSummary "Unable to unmount the CDROM"
    UpdateTestState "TestFailed"
    exit 1
else
    UpdateSummary  "CDROM unmounted successfully"
fi

UpdateSummary "CDROM mount & LIS ${action} returned no errors"
UpdateTestState "TestCompleted"
exit 0