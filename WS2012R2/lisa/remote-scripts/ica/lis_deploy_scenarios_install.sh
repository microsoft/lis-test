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
# The following versions support selinux and can handle custom LIS policy
release_versions=("6.6" "6.7" "6.8" "7.0" "7.1" "7.2" "7.3" "7.4" "7.5")

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}
# Source constants file and initialize most common variables
UtilsInit

if [ "$first_install" == "" ];then
    first_install=0
fi

# Deleting old LIS
if [[ "$action" == "install" && "$first_install" == 0 ]]; then
    UpdateSummary "successfully removed LIS"
    rpm -qa | grep microsoft | xargs rpm -e | tee ~/LIS_scenario_${scenario}.log
    chmod +w ~/constants.sh
    echo "first_install=1" >> ~/constants.sh
fi

pushd $lis_folder
# Install LIS
bash ${action}.sh 2>&1 | tee ~/LIS_scenario_${scenario}.log
if [ $? -ne 0 ]; then
    msg="Unable to run ${action}.sh"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi
popd
# Do a double check to see if script finished running
is_finished=false
while [ $is_finished == false ]; do
    cat ~/LIS_scenario_${scenario}.log | tail -2 | grep "reboot\|aborting"
    if [ $? -eq 0 ]; then
        is_finished=true
    else
        sleep 2
    fi
done
sleep 60

# Search for install issues
cat ~/LIS_scenario_${scenario}.log | grep -i "error\|aborting"
if [ $? -eq 0 ]; then
    msg="ERROR: abort/error detected while installing LIS"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 1
fi

cat ~/LIS_scenario_${scenario}.log | grep -i "warning"
if [ $? -eq 0 ]; then
    msg="Warning detected. Will verify if it's expected"
    LogMsg "$msg"

    cat ~/LIS_scenario_${scenario}.log | grep -i "warning" | grep $(uname -r)
    if [ $? -eq 0 ]; then
        msg="ERROR: Warning is not expected"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    fi
fi

UpdateSummary "LIS drivers ${action}ed successfully"

# Apply selinux policy
if [[ "$action" == "install" && ! -f hyperv-daemons.te ]]; then
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

# Allow time for all installation related background processes to finish
sync
sleep 15

SetTestStateCompleted
exit 0
