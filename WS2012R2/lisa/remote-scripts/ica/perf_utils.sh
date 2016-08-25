#!/usr/bin/env bash

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

########################################################################
#
# perf_utils.sh
#
# Description:
#   Handle VM preparations for running performance tests
#
#   Steps:
#   1. setup_sysctl - setting and applying sysctl parameters
#   2. setup_io_scheduler - setting noop i/o scheduler on all disk type devices
# (this is not a permanent change - on reboot it needs to be reapplied)
#
########################################################################

declare -A sysctl_params=( ["net.core.netdev_max_backlog"]="30000"
                           ["net.core.rmem_max"]="67108864"
                           ["net.core.wmem_max"]="67108864"
                           ["net.ipv4.tcp_wmem"]="4096 12582912 33554432"
                           ["net.ipv4.tcp_rmem"]="4096 12582912 33554432"
                           ["net.ipv4.tcp_max_syn_backlog"]="80960"
                           ["net.ipv4.tcp_slow_start_after_idle"]="0"
                           ["net.ipv4.tcp_tw_reuse"]="1"
                           ["net.ipv4.ip_local_port_range"]="10240 65535"
                           ["net.ipv4.tcp_abort_on_overflow"]="1"
                          )
sysctl_file="/etc/sysctl.conf"

function setup_sysctl {
    for param in "${!sysctl_params[@]}"; do
        grep -q "$param" ${sysctl_file} && \
        sed -i 's/^'"$param"'.*/'"$param"' = '"${sysctl_params[$param]}"'/' \
            ${sysctl_file} || \
        echo "$param = ${sysctl_params[$param]}" >> ${sysctl_file} || return 1
    done
    sysctl -p ${sysctl_file}
    return $?
}

# change i/o scheduler to noop on each disk - does not persist after reboot
function setup_io_scheduler {
    sys_disks=( $(lsblk -o KNAME,TYPE -dn | grep disk | awk '{ print $1 }') )
    for disk in "${sys_disks[@]}"; do
        current_scheduler=$(cat /sys/block/${disk}/queue/scheduler)
        if [[ ${current_scheduler} != *"[noop]"* ]]; then
          echo noop > /sys/block/${disk}/queue/scheduler
        fi
    done
    # allow current I/O ops to be executed before the new scheduler is applied
    sleep 5
}

echo "###Setting sysctl params###"
setup_sysctl
if [[ $? -ne 0 ]]
then
    echo "ERROR: Unable to set sysctl params"
    exit 1
fi
echo "###Setting elevator to noop###"
setup_io_scheduler
if [[ $? -ne 0 ]]
then
    echo "ERROR: Unable to set elevator to noop."
    exit 1
fi
echo "Done."
