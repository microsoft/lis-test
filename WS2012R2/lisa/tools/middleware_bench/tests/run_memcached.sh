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

if [ $# -lt 2 ]; then
    echo -e "\nUsage:\n$0 server user"
    exit 1
fi

SERVER="$1"
USER="$2"
THREADS=(1 2 4 8 16 32 64 128 256 512)
max_threads=16

if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi

distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt-get update && sudo apt-get upgrade -y >> ${LOG_FILE}
    sudo apt-get -y install libaio1 sysstat zip memcached libmemcached-tools >> ${LOG_FILE}
    sudo apt-get -y install build-essential autoconf automake libpcre3-dev libevent-dev pkg-config zlib1g-dev >> ${LOG_FILE}

    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt-get update && sudo apt-get upgrade -y" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt-get -y install libaio1 sysstat zip memcached" >> ${LOG_FILE}
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum clean dbcache>> ${LOG_FILE}
    sudo yum -y install sysstat zip memcached autoconf automake git make gcc-c++ >> ${LOG_FILE}
    sudo yum -y install pcre-devel zlib-devel libmemcached-devel libevent-devel >> ${LOG_FILE}

    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo yum -y install sysstat zip memcached" >> ${LOG_FILE}
else
    LogMsg "Unsupported distribution: ${distro}."
fi

cd /tmp
git clone https://github.com/RedisLabs/memtier_benchmark
cd /tmp/memtier_benchmark
sudo autoreconf -ivf; sudo ./configure; sudo make; sudo make install >> ${LOG_FILE}

mkdir -p /tmp/memcached
ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "mkdir -p /tmp/memcached"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f memcached" >> ${LOG_FILE}
LogMsg "Starting memcached server on ${SERVER}"
ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "memcached -u ${USER}" >> ${LOG_FILE}

function run_memcached ()
{
    thread=$1
    num_threads=$2
    num_client_per_thread=$3
    total_request=$4
    
    LogMsg "======================================"
    LogMsg "Running Test: ${thread} = ${num_threads} X ${num_client_per_thread}"
    LogMsg "======================================"

    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "sar -n DEV 1 900   2>&1 > /tmp/memcached/${thread}.sar.netio.log"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "iostat -x -d 1 900 2>&1 > /tmp/memcached/${thread}.iostat.diskio.log"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "vmstat 1 900       2>&1 > /tmp/memcached/${thread}.vmstat.memory.cpu.log"
    sar -n DEV 1 900   2>&1 > /tmp/memcached/${thread}.sar.netio.log &
    iostat -x -d 1 900 2>&1 > /tmp/memcached/${thread}.iostat.netio.log &
    vmstat 1 900       2>&1 > /tmp/memcached/${thread}.vmstat.netio.log &

    memtier_benchmark -s ${SERVER} -p 11211 -P memcache_text -x 3 -n ${total_request} -t ${num_threads} -c ${num_client_per_thread} -d 4000 --ratio 1:1 --key-pattern S:S > /tmp/memcached/${thread}.memtier_benchmark.run.log

    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f sar"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f iostat"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f vmstat"
    sudo pkill -f sar
    sudo pkill -f iostat
    sudo pkill -f vmstat
    
    LogMsg "sleep 60 seconds"
    sleep 60
}

for thread in "${THREADS[@]}"
do
    if [ ${thread} -lt ${max_threads} ]
    then
        num_threads=${thread}
        num_client_per_thread=1
        total_request=1000000
    else
        num_threads=${max_threads}
        num_client_per_thread=$((${thread} / ${num_threads}))
        total_request=100000
    fi
    run_memcached ${thread} ${num_threads} ${num_client_per_thread} ${total_request}
done

LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"

cd /tmp
zip -r memcached.zip . -i memcached/* >> ${LOG_FILE}
zip -r memcached.zip . -i summary.log >> ${LOG_FILE}
