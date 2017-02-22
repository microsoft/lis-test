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
#   3. setup_ntttcp - downlload and install ntttcp-for-linux
#   4. setup_lagscope - download an install lagscope to monitoring latency
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

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
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
fi

#Install ntttcp-for-linux
function setup_ntttcp {
    if [ "$(which ntttcp)" == "" ]; then
      rm -rf ntttcp-for-linux
      git clone https://github.com/Microsoft/ntttcp-for-linux
      status=$?
      if [ $status -eq 0 ]; then
        echo "ntttcp-for-linux successfully downloaded."
        cd ntttcp-for-linux/src
      else 
        echo "ERROR: Unable to download ntttcp-for-linux"
        exit 1
      fi
      make && make install
      if [[ $? -ne 0 ]]
      then
        echo "ERROR: Unable to compile ntttcp-for-linux."
        exit 1
      fi
      cd /root/
    fi
}

#Install lagscope
function setup_lagscope {
    if [[ "$(which lagscope)" == "" ]]; then
      rm -rf lagscope
      git clone https://github.com/Microsoft/lagscope
      status=$?
      if [ $status -eq 0 ]; then
        echo "Lagscope successfully downloaded."
        cd lagscope/src
      else
        echo "ERROR: Unable to download lagscope."
        exit 1
      fi
      make && make install
      if [[ $? -ne 0 ]]
      then
        echo "ERROR: Unable to compile ntttcp-for-linux."
        exit 1
      fi
      cd /root/
    fi        
}

#Upgrade gcc to 4.8.1
function upgrade_gcc {
# Import CERN's GPG key
    rpm --import http://ftp.scientificlinux.org/linux/scientific/5x/x86_64/RPM-GPG-KEYs/RPM-GPG-KEY-cern
    if [ $? -ne 0 ]; then
        echo "Error: Failed to import CERN's GPG key."
        exit 1
    fi
# Save repository information
    wget -O /etc/yum.repos.d/slc6-devtoolset.repo http://linuxsoft.cern.ch/cern/devtoolset/slc6-devtoolset.repo
    if [ $? -ne 0 ]; then
        echo "Error: Failed to save repository information."
        exit 1
    fi

# The below will also install all the required dependencies
    yum install -y devtoolset-2-gcc-c++
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to install the new version of gcc."
        exit 1
    fi
    echo "source /opt/rh/devtoolset-2/enable" >> /root/.bashrc
    source /root/.bashrc
}

#Function for TX Bytes
function get_tx_bytes(){
    # RX bytes:66132495566 (66.1 GB)  TX bytes:3067606320236 (3.0 TB)
    Tx_bytes=`ifconfig $1 | grep "TX bytes"   | awk -F':' '{print $3}' | awk -F' ' ' {print $1}'`
    
    if [ "x$Tx_bytes" == "x" ]
    then
        #TX packets 223558709  bytes 15463202847 (14.4 GiB)
        Tx_bytes=`ifconfig $1| grep "TX packets"| awk '{print $5}'`
    fi
    echo $Tx_bytes

}

#Function for TX packets
function get_tx_pkts(){
    # TX packets:543924452 errors:0 dropped:0 overruns:0 carrier:0
    Tx_pkts=`ifconfig $1 | grep "TX packets" | awk -F':' '{print $2}' | awk -F' ' ' {print $1}'`

    if [ "x$Tx_pkts" == "x" ]
    then
        #TX packets 223558709  bytes 15463202847 (14.4 GiB)
        Tx_pkts=`ifconfig $1 | grep "TX packets"| awk '{print $3}'`        
    fi
    echo $Tx_pkts   
}

#Firewall and iptables for Ubuntu/CentOS6.x/RHEL6.x
function disable_firewall {
    service ufw status | grep inactive
    if [[ $? -ne 0 ]]; then 
      echo "WARN: Service firewall active. Will disable it ..."
      service ufw stop
    else
      echo "Firewall is disabled."
    fi
    service iptables status | grep inactive
    if [[ $? -ne 0 ]]; then 
      echo "WARN: Service iptables active. Will disable it ..."
      service iptables stop
    else
      echo "Iptables is disabled."
    fi
    service ip6tables status | grep inactive
    if [[ $? -ne 0 ]]; then 
      echo "WARN: Service ip6tables active. Will disable it ..."
      service ip6tables stop
    else
      echo "Ip6tables is disabled."
    fi
    echo "Iptables and ip6tables disabled."
}

# Set static IPs for test interfaces
function config_staticip {  
    declare -i __iterator=0
    while [ $__iterator -lt ${#SYNTH_NET_INTERFACES[@]} ]; do
        LogMsg "Trying to set an IP Address via static on interface ${SYNTH_NET_INTERFACES[$__iterator]}"
        CreateIfupConfigFile "${SYNTH_NET_INTERFACES[$__iterator]}" "static" $1 $2
        if [ 0 -ne $? ]; then
            msg="ERROR: Unable to set address for ${SYNTH_NET_INTERFACES[$__iterator]} through static"
            LogMsg "$msg"
            UpdateSummary "$msg"            
            exit 10
        fi
        : $((__iterator++))
    done
}