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
# PURPOSE, MERCHANTABILITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################
LOG_FILE=/tmp/perf_tuning.log
function LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1} >> ${LOG_FILE}
}

if [ $# -lt 1 ]; then
    echo -e "\nUsage:\n$0 provider kernel"
    exit 1
fi

PROVIDER="$1"
if [ ! -z "$2" ]; then
    KERNEL="$2"
fi

declare -A sysctl_params=( ["net.core.netdev_max_backlog"]="30000"
                           ["net.core.rmem_default"]="134217728"
                           ["net.core.rmem_max"]="134217728"
                           ["net.core.wem_default"]="134217728"
                           ["net.core.wmem_max"]="134217728"
                           ["net.ipv4.tcp_wmem"]="4096 87380 67108864"
                           ["net.ipv4.tcp_rmem"]="4096 87380 67108864"
                           ["net.ipv4.tcp_congestion_control"]="htcp"
                           ["net.ipv4.tcp_max_syn_backlog"]="80960"
                           ["net.ipv4.tcp_slow_start_after_idle"]="0"
                           ["net.ipv4.tcp_tw_reuse"]="1"
                           ["net.ipv4.ip_local_port_range"]="10240 65535"
                           ["net.ipv4.tcp_abort_on_overflow"]="1"
                           ["vm.overcommit_memory"]="2"
                          )
sysctl_file="/etc/sysctl.conf"

distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt update
    if [ -z ${KERNEL} ]; then
        sudo DEBIAN_FRONTEND='noninteractive' apt full-upgrade -yq >> ${LOG_FILE}
    fi
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum -y update kernel>> ${LOG_FILE}
else
    LogMsg "Unsupported distribution: ${distro}."
fi

function setup_sysctl {
    for param in "${!sysctl_params[@]}"; do
        sudo grep -q "$param" ${sysctl_file} &&
        sudo sed -i 's/^'"$param"'.*/'"$param"' = '"${sysctl_params[$param]}"'/' ${sysctl_file} ||
        echo "$param = ${sysctl_params[$param]}" | sudo tee --append ${sysctl_file} || return 1
    done
    sudo sysctl -p ${sysctl_file}
}

function setup_cpu_sched_domain {
    total_cpus=`grep -c '^processor' /proc/cpuinfo`
    for (( i=0; i<${total_cpus}; i++ ))
    do
        echo '0' | sudo tee /proc/sys/kernel/sched_domain/cpu${i}/domain0/idle_idx
        echo '4655' | sudo tee /proc/sys/kernel/sched_domain/cpu${i}/domain0/flags
    done
}

function install_kernel {
    sudo apt install -y dpkg
    sudo dpkg -i ${KERNEL}
    sudo update-grub
}

setup_sysctl
if [[ ${PROVIDER} == "azure" ]]; then
    setup_cpu_sched_domain
fi
if [ ! -z ${KERNEL} ]; then
    install_kernel
fi
