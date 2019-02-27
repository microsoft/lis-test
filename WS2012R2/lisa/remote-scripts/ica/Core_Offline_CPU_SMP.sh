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

UpdateTestState(){
    echo $1 > ~/state.txt
}

#Source utils.sh
dos2unix utils.sh
. utils.sh || {
    UpdateTestState "TestAborted"
    UpdateSummary "Error: unable to source utils.sh!"
    exit 2
}

# Source constants.sh
dos2unix constants.sh
. constants.sh || {
    UpdateTestState "TestAborted"
    UpdateSummary "Error: unable to source constants.sh!"
    exit 2
}

# Change kernel parameter for rhel
set_rhel(){
    cpu_num=`grep processor /proc/cpuinfo | wc -l`
    if [ $cpu_num -eq $VCPU ]; then
        LogMsg "CPU Number : ${cpu_num}"
    else
        LogMsg "ERROR: CPU Number : ${cpu_num}, expect ${VCPU}"
        UpdateSummary "Error: CPU Number ${cpu_num} not equal to ${VCPU}"
        UpdateTestState "TestFailed"
        exit 1
    fi

    #Change kernel parameter in /etc/default/grub
    sed -i "s/quiet/quiet nr_cpus=${NR_CPU}/g" /etc/default/grub
    GetGuestGeneration
    if [ $os_GENERATION -eq 1 ]; then
        grub2-mkconfig -o /boot/grub2/grub.cfg
    else
        grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg
    fi

    LogMsg "Set kernel parameter sucessfully"
}

# Change kernel parameter
setCPUNum(){
    Version=0
    GetDistro
    case "$DISTRO" in

        redhat*)
            set_rhel
            exit 0
        ;;

        *)
        echo "Error: Distro '$DISTRO' not supported." >> ~/summary.log
        UpdateTestState "TestAborted"
        UpdateSummary "Error: Distro '$DISTRO' not supported."
        exit 1
        ;;
    esac
    exit 0
}

# Check cpu number by /proc/cpuinfo
checkCPUNum(){
    cpunum=`grep processor /proc/cpuinfo | wc -l`
    if [ $cpunum -eq $NR_CPU ]; then
        LogMsg "Passed: CPU number is ${NR_CPU}"
    else
        LogMsg "Failed: CPU number is not ${NR_CPU}"
        UpdateSummary "Failed: CPU number is not ${NR_CPU}. (actual ${cpunum})"
        UpdateTestState "TestFailed"
        exit 2
    fi

    # check CPUs attached should not go offline
    for ((i=0; i<${cpunum}; i++))
    do
        echo 0 > /sys/devices/system/cpu/cpu${i}/online
        if [ $? -ne 0 ]; then
            LogMsg "Passed: CPU ${i} cannot offline."
        else
            LogMsg "Failed: CPU ${i} offline unexpectedly."
            UpdateSummary "Failed: CPU ${i} offline unexpectedly."
            UpdateTestState "TestFailed"
            exit 2
        fi
    done
    exit 0
}

if [ $1 = "checkCPUNum" ]; then
    checkCPUNum
elif [ $1 = "setCPUNum" ]; then
    setCPUNum
fi