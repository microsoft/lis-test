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

LOG_FILE=/tmp/summary.log
function LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1} >> ${LOG_FILE}
}

if [ $# -lt 3 ]; then
    echo -e "\nUsage:\n$0 server user test_type"
    exit 1
fi

SERVER="$1"
USER="$2"
PROTO="$3"
TEST_THREADS=

if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi

distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt-get update && sudo apt-get upgrade -y >> ${LOG_FILE}
    sudo apt-get -y install sysstat zip bc build-essential >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt-get update && sudo apt-get upgrade -y" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt-get -y install sysstat zip bc build-essential" >> ${LOG_FILE}
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum clean dbcache >> ${LOG_FILE}
    sudo yum -y install sysstat zip bc git gcc automake autoconf rpm >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo yum clean dbcache" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo yum -y install sysstat zip bc git gcc automake autoconf rpm" >> ${LOG_FILE}
else
    LogMsg "Unsupported distribution: ${distro}."
fi
sudo iptables -F >> ${LOG_FILE}
ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo iptables -F" >> ${LOG_FILE}
mkdir -p /tmp/network${PROTO}
cd /tmp
if [[ ${PROTO} == "TCP" ]]
then
    TEST_THREADS=(1 2 4 8 16 32 64 128 256 512 1024 2048 3072 6144 10240)
    cd /tmp; git clone https://github.com/Microsoft/ntttcp-for-linux
    cd /tmp/ntttcp-for-linux/src; sudo make && sudo make install
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp; git clone https://github.com/Microsoft/ntttcp-for-linux" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp/ntttcp-for-linux/src; sudo make && sudo make install" >> ${LOG_FILE}
    cd /tmp; git clone https://github.com/Microsoft/lagscope
    cd /tmp/lagscope/src; sudo make && sudo make install
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp; git clone https://github.com/Microsoft/lagscope" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp/lagscope/src; sudo make && sudo make install" >> ${LOG_FILE}
elif [[ ${PROTO} == "latency" ]]
then
    cd /tmp; git clone https://github.com/Microsoft/lagscope
    cd /tmp/lagscope/src; sudo make && sudo make install
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp; git clone https://github.com/Microsoft/lagscope" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp/lagscope/src; sudo make && sudo make install" >> ${LOG_FILE}
elif [[ ${PROTO} == "UDP" ]]
then
    TEST_THREADS=(1 2 4 8 16 32 64 128 256 512 1024)
    if [[ ${distro} == *"Ubuntu"* ]]
    then
        sudo apt-get -y install iperf3 >> ${LOG_FILE}
        ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt-get -y install iperf3" >> ${LOG_FILE}
    elif [[ ${distro} == *"Amazon"* ]]
    then
        cd /tmp; wget https://iperf.fr/download/fedora/iperf3-3.1.3-1.fc24.x86_64.rpm; sudo rpm -ivh iperf3-3.1.3-1.fc24.x86_64.rpm >> ${LOG_FILE}
        ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp; wget https://iperf.fr/download/fedora/iperf3-3.1.3-1.fc24.x86_64.rpm; sudo rpm -ivh iperf3-3.1.3-1.fc24.x86_64.rpm" >> ${LOG_FILE}
    else
        LogMsg "Unsupported distribution: ${distro}."
    fi
else
    LogMsg "Unsupported test type: ${PROTO}."
fi

function get_tx_bytes(){
    # RX bytes:66132495566 (66.1 GB)  TX bytes:3067606320236 (3.0 TB)
    local Tx_bytes=`ifconfig eth0 | grep "TX bytes"   | awk -F':' '{print $3}' | awk -F' ' ' {print $1}'`

    if [ "x$Tx_bytes" == "x" ]
    then
        #TX packets 223558709  bytes 15463202847 (14.4 GiB)
        Tx_bytes=`ifconfig eth0| grep "TX packets"| awk '{print $5}'`
    fi
    echo ${Tx_bytes}
}

function get_tx_pkts(){
    # TX packets:543924452 errors:0 dropped:0 overruns:0 carrier:0
    local Tx_pkts=`ifconfig eth0 | grep "TX packets" | awk -F':' '{print $2}' | awk -F' ' ' {print $1}'`

    if [ "x$Tx_pkts" == "x" ]
    then
        #TX packets 223558709  bytes 15463202847 (14.4 GiB)
        Tx_pkts=`ifconfig eth0| grep "TX packets"| awk '{print $3}'`
    fi
    echo ${Tx_pkts}
}

ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "mkdir /tmp/network${PROTO}"

function run_lagscope()
{
    LogMsg "======================================"
    LogMsg "Running lagscope "
    LogMsg "======================================"
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f lagscope"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo lagscope -r${SERVER}"
    sleep 5
    sudo lagscope -s${SERVER} -n1000000 -i0 -V > "/tmp/network${PROTO}/lagscope.log"
    sleep 5
    sudo pkill -f lagscope
}

function run_ntttcp ()
{
    current_test_threads=$1
    LogMsg "======================================"
    LogMsg "Running NTTTCP thread= ${current_test_threads}"
    LogMsg "======================================"
    if [ ${current_test_threads} -lt 64 ]
    then
        num_threads_P=${current_test_threads}
        num_threads_n=1
    else
        num_threads_P=64
        num_threads_n=$(($current_test_threads / $num_threads_P))
    fi
    sudo pkill -f ntttcp
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f ntttcp"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo ntttcp -r${SERVER} -P $num_threads_P -t 60 -e > /tmp/network${PROTO}/${current_test_threads}_ntttcp-receiver.log"
    sudo pkill -f lagscope
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f lagscope"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo lagscope -r${SERVER}"
    sleep 5
    previous_tx_bytes=$(get_tx_bytes)
    previous_tx_pkts=$(get_tx_pkts)
    sudo lagscope -s${SERVER} -t 60 -V 4 > "/tmp/network${PROTO}/${current_test_threads}_lagscope.log"
    sudo ntttcp -s${SERVER} -P ${num_threads_P} -n ${num_threads_n} -t 60  > "/tmp/network${PROTO}/${current_test_threads}_ntttcp-sender.log"
    current_tx_bytes=$(get_tx_bytes)
    current_tx_pkts=$(get_tx_pkts)
    bytes_new=`(expr ${current_tx_bytes} - ${previous_tx_bytes})`
    pkts_new=`(expr ${current_tx_pkts} - ${previous_tx_pkts})`
    avg_pkt_size=$(echo "scale=2;${bytes_new}/${pkts_new}/1024" | bc)
    echo "Average Package Size: ${avg_pkt_size}" >> /tmp/network${PROTO}/${current_test_threads}_ntttcp-sender.log
    sleep 10
    sudo pkill -f ntttcp
    sudo pkill -f lagscope
    previous_tx_bytes=${current_tx_bytes}
    previous_tx_pkts=${current_tx_pkts}
}

function run_iperf()
{
    current_test_threads=$1
    LogMsg "======================================"
    LogMsg "Running iPerf3 thread= ${current_test_threads}"
    LogMsg "======================================"
    port=8001
    sudo pkill -f iperf3
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f iperf3" >> ${LOG_FILE}

    server_iperf_instances=$((current_test_threads/4+port))
    for ((i=port; i<=server_iperf_instances; i++))
    do
        ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo iperf3 -s 4 -p $i -i 60 -D" >> ${LOG_FILE}
        sleep 1
    done

    while [ ${current_test_threads} -gt 64 ]; do
        number_of_connections=$(($number_of_connections-64))
        sudo iperf3 -u -c ${SERVER} -p ${port} -4 -b 0 -l 1k -P 64 -t 60 --get-server-output -i 60 > /tmp/network${PROTO}/${current_test_threads}-iperf3.log
        port=$(($port + 1))
    done
    if [ ${number_of_connections} -gt 0 ]
    then
        sudo iperf3 -u -c ${SERVER} -p ${port} -4 -b 0 -l 1k -P ${number_of_connections} -t 60 --get-server-output -i 60 > /tmp/network${PROTO}/${current_test_threads}-iperf3.log
    fi
    sleep 10
    sudo pkill -f iperf3
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f iperf3" >> ${LOG_FILE}
}

if [[ ${PROTO} == "TCP" ]]
then
    for thread in "${TEST_THREADS[@]}"
    do
        run_ntttcp ${thread}
    done
elif [[ ${PROTO} == "latency" ]]
then
    run_lagscope
elif [[ ${PROTO} == "UDP" ]]
then
    for thread in "${TEST_THREADS[@]}"
    do
        run_iperf ${thread}
    done
else
    LogMsg "Unsupported test type: ${PROTO}."
fi

LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"

cd /tmp
zip -r network.zip . -i network${PROTO}/* >> ${LOG_FILE}
zip -r network.zip . -i summary.log >> ${LOG_FILE}
