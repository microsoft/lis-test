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

sudo apt-get update >> ${LOG_FILE}
sudo apt-get -y install libaio1 sysstat zip redis-tools>> ${LOG_FILE}

sudo pkill -f redis-benchmark
mkdir -p /tmp/redis

ssh -T -oStrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt-get update" >> ${LOG_FILE}
ssh -T -oStrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt-get -y install libaio1 sysstat zip redis-server" >> ${LOG_FILE}
ssh -oStrictHostKeyChecking=no ${USER}@${SERVER} "mkdir -p /tmp/redis"
ssh -T -oStrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i 's/bind 127\.0\.0\.1/bind 0\.0\.0\.0/' /etc/redis/redis.conf" >> ${LOG_FILE}
ssh -T -oStrictHostKeyChecking=no ${USER}@${SERVER} "sudo service redis-server restart" >> ${LOG_FILE}
ssh -T -oStrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f redis-server" >> ${LOG_FILE}

function run_redis ()
{
    pipeline=$1

    LogMsg "======================================"
    LogMsg "Running Redis Test with pipelines: ${pipeline}"
    LogMsg "======================================"

    ssh -f -oStrictHostKeyChecking=no ${USER}@${SERVER} "sar -n DEV 1 900   2>&1 > /tmp/redis/${pipeline}.sar.netio.log"
    ssh -f -oStrictHostKeyChecking=no ${USER}@${SERVER} "iostat -x -d 1 900 2>&1 > /tmp/redis/${pipeline}.iostat.diskio.log"
    ssh -f -oStrictHostKeyChecking=no ${USER}@${SERVER} "vmstat 1 900       2>&1 > /tmp/redis/${pipeline}.vmstat.memory.cpu.log"
    LogMsg "Starting redis server on ${SERVER}"
    ssh -f -oStrictHostKeyChecking=no ${USER}@${SERVER} "sudo redis-server > /dev/null"
    sar -n DEV 1 900   2>&1 > /tmp/redis/${pipeline}.sar.netio.log &
    iostat -x -d 1 900 2>&1 > /tmp/redis/${pipeline}.iostat.netio.log &
    vmstat 1 900       2>&1 > /tmp/redis/${pipeline}.vmstat.netio.log &

    sleep 20
    redis-benchmark -h ${SERVER} -c 1000 -P ${pipeline} -t ${redis_test_suites} -d 4000 -n 10000000 > /tmp/redis/${pipeline}.redis.set.get.log

    ssh -T -oStrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f sar"
    ssh -T -oStrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f iostat"
    ssh -T -oStrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f vmstat"
    ssh -T -oStrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f redis-server"
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

LogMsg "Kernel Version : `uname -r` "

cd /tmp
zip -r redis.zip . -i redis/* >> ${LOG_FILE}
zip -r redis.zip . -i summary.log >> ${LOG_FILE}
