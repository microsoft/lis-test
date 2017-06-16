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
TEST_PIPELINES=(1 8 16 32 64 128)
redis_test_suites="set,get"

if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi

distro="$(head -1 /etc/issue)"
redis_conf=
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt-get update && sudo apt-get upgrade -y >> ${LOG_FILE}
    sudo apt-get -y install libaio1 sysstat zip redis-tools>> ${LOG_FILE}

    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt-get update && sudo apt-get upgrade -y" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt-get -y install libaio1 sysstat zip redis-server" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i 's/bind 127\.0\.0\.1/bind 0\.0\.0\.0/' /etc/redis/redis.conf" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo service redis-server restart" >> ${LOG_FILE}
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum clean dbcache>> ${LOG_FILE}
    sudo yum -y install sysstat zip gcc make wget >> ${LOG_FILE}
    cd /tmp
    wget http://download.redis.io/releases/redis-3.2.9.tar.gz
    tar -zxf redis-3.2.9.tar.gz
    cd /tmp/redis-3.2.9; make
    cd /tmp/redis-3.2.9/src; sudo cp redis-benchmark /usr/local/bin

    redis_conf="/etc/redis/6379.conf"
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo yum clean dbcache" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo yum -y install sysstat zip gcc make wget" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp; wget http://download.redis.io/releases/redis-3.2.9.tar.gz" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp; tar -zxf redis-3.2.9.tar.gz" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp/redis-3.2.9; make" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp/redis-3.2.9/src; sudo cp redis-server /usr/bin" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mkdir /etc/redis; sudo mkdir -p /var/lib/redis/6379" >> ${LOG_FILE}
    # redis tuning
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sysctl -w net.core.somaxconn=512" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sysctl -w vm.overcommit_memory=1" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled" >> ${LOG_FILE}

    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo cp /tmp/redis-3.2.9/redis.conf ${redis_conf}" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo cp /tmp/redis-3.2.9/utils/redis_init_script /etc/init.d/redis" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i 's/bind 127\.0\.0\.1/bind 0\.0\.0\.0/' ${redis_conf}" >> ${LOG_FILE}
else
    LogMsg "Unsupported distribution: ${distro}."
fi

cd /tmp
sudo pkill -f redis-benchmark
mkdir -p /tmp/redis
ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "mkdir -p /tmp/redis"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f redis-server" >> ${LOG_FILE}

function run_redis ()
{
    pipeline=$1

    LogMsg "======================================"
    LogMsg "Running Redis Test with pipelines: ${pipeline}"
    LogMsg "======================================"

    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "sar -n DEV 1 900   2>&1 > /tmp/redis/${pipeline}.sar.netio.log"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "iostat -x -d 1 900 2>&1 > /tmp/redis/${pipeline}.iostat.diskio.log"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "vmstat 1 900       2>&1 > /tmp/redis/${pipeline}.vmstat.memory.cpu.log"
    LogMsg "Starting redis server on ${SERVER}"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo redis-server ${redis_conf} > /dev/null"

    sar -n DEV 1 900   2>&1 > /tmp/redis/${pipeline}.sar.netio.log &
    iostat -x -d 1 900 2>&1 > /tmp/redis/${pipeline}.iostat.netio.log &
    vmstat 1 900       2>&1 > /tmp/redis/${pipeline}.vmstat.netio.log &

    sleep 20
    redis-benchmark -h ${SERVER} -c 1000 -P ${pipeline} -t ${redis_test_suites} -d 4000 -n 10000000 > /tmp/redis/${pipeline}.redis.set.get.log

    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f sar"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f iostat"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f vmstat"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f redis-server"
    sudo pkill -f sar
    sudo pkill -f iostat
    sudo pkill -f vmstat
    sudo pkill -f redis-benchmark

    LogMsg "sleep 60 seconds"
    sleep 60
}

for pipe in "${TEST_PIPELINES[@]}"
do
    run_redis ${pipe}
done

LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"

cd /tmp
zip -r redis.zip . -i redis/* >> ${LOG_FILE}
zip -r redis.zip . -i summary.log >> ${LOG_FILE}
