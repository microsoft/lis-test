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

dos2unix utils.sh

#
# Source utils.sh to get more utils
# Get $DISTRO, LogMsg directly from utils.sh
#
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    exit 1
}

#
# Source constants file and initialize most common variables
#
UtilsInit
vm2ipv4=$1

#######################################################################
#
# CheckVmcore()
#
#######################################################################
CheckVmcore()
{
    if ! [[ $(find /var/crash/*/vmcore -type f -size +10M) ]]; then
        LogMsg "Test Failed. No file was found in /var/crash of size greater than 10M."
        UpdateSummary "Test Failed. No file was found in /var/crash of size greater than 10M."
        SetTestStateFailed
        exit 1
    else
        LogMsg "Test Successful. Proper file was found."
        UpdateSummary "Test Successful. Proper file was found."
        SetTestStateCompleted
    fi
}

VerifyRemoteStatus()
{
    array_status=( $status )
    exit_code=${array_status[1]}
    if [ $exit_code -eq 0 ]; then
        LogMsg "Test Successful. Proper file was found on nfs server."
        UpdateSummary "Test Successful. Proper file was found on nfs server."
        SetTestStateCompleted
    else
        LogMsg "Test Failed. No file was found on nfs server of size greater than 10M."
        UpdateSummary "Test Failed. No file was found on nfs server of size greater than 10M."
        SetTestStateFailed
        exit 1
    fi
}

#######################################################################
#
# Main script body
#
#######################################################################

#
# As $DISTRO from utils.sh get the DETAILED Disro. eg. redhat_6, redhat_7, ubuntu_13, ubuntu_14
# So, redhat* / ubuntu* / suse*
#
GetDistro
case $DISTRO in
    centos* | redhat*)
        if [[ $vm2ipv4 != "" ]]; then
            status=`ssh -i /root/.ssh/${ssh_key} -o StrictHostKeyChecking=no root@${vm2ipv4} "find /mnt/var/crash/*/vmcore -type f -size +10M; echo $?"`
            VerifyRemoteStatus
        else
            CheckVmcore
        fi
    ;;
    ubuntu*)
        if [[ $vm2ipv4 != "" ]]; then
            status=`ssh -i /root/.ssh/${ssh_key} -o StrictHostKeyChecking=no root@${vm2ipv4} "find /mnt/* -type f -size +10M; echo $?"`
            VerifyRemoteStatus
        else
            if ! [[ $(find /var/crash/2* -type f -size +10M) ]]; then
                LogMsg "Test Failed. No file was found in /var/crash of size greater than 10M."
                UpdateSummary "Test Failed. No file was found in /var/crash of size greater than 10M."
                SetTestStateFailed
                exit 1
            else
                LogMsg "Test Successful. Proper file was found."
                UpdateSummary "Test Successful. Proper file was found."
                SetTestStateCompleted
            fi
        fi
    ;;
  suse*)
        if [[ $vm2ipv4 != "" ]]; then
            status=`ssh -i /root/.ssh/${ssh_key} -o StrictHostKeyChecking=no root@${vm2ipv4} "find /mnt/* -type f -size +10M; echo $?"`
            VerifyRemoteStatus
        else
            CheckVmcore
        fi
    ;;
     *)
        LogMsg "Test Failed. Unknown DISTRO: $DISTRO."
        UpdateSummary "Test Failed. Unknown DISTRO: $DISTRO."
        SetTestStateFailed
        exit 1
    ;;
esac
