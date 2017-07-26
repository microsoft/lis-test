#!/bin/bash

########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the nginx License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.nginx.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABILITY OR NON-INFRINGEMENT.
#
# See the nginx Version 2.0 License for specific language governing
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
TEST_CONCURRENCY_THREADS=(1 2 4 8 16 32 64 128 256 512 1024)
max_concurrency_per_ab=4
max_ab_instances=16

if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi

distro="$(head -1 /etc/issue)"
web_server="nginx"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -yq >> ${LOG_FILE}
    sudo apt-get -y install libaio1 sysstat zip nginx apache2-utils >> ${LOG_FILE}

    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -yq" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt-get -y install sysstat zip nginx apache2-utils" >> ${LOG_FILE}
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum clean dbcache>> ${LOG_FILE}
    sudo yum -y install sysstat zip nginx httpd-tools >> ${LOG_FILE}

    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo yum clean dbcache" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo yum -y install sysstat zip nginx httpd-tools" >> ${LOG_FILE}
else
    LogMsg "Unsupported distribution: ${distro}."
fi

sudo pkill -f ab
mkdir -p /tmp/nginx_bench
LogMsg "Info: Generate test data file on the nginx server /var/www/html/test.dat"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo dd if=/dev/urandom of=/var/www/html/test.dat bs=1K count=200"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo service ${web_server} stop" >> ${LOG_FILE}
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo service ${web_server} start" >> ${LOG_FILE}
ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "mkdir -p /tmp/nginx_bench"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f ab" >> ${LOG_FILE}

function run_ab ()
{
    current_concurrency=$1

    if [ ${current_concurrency} -le 2 ]
    then
        total_requests=50000
    elif [ ${current_concurrency} -le 128 ]
    then
        total_requests=100000
    else
        total_requests=200000
    fi

    ab_instances=$(($current_concurrency / $max_concurrency_per_ab))
    if [ ${ab_instances} -eq 0 ]
    then
        ab_instances=1
    fi
    if [ ${ab_instances} -gt ${max_ab_instances} ]
    then
        ab_instances=${max_ab_instances}
    fi

    total_request_per_ab=$(($total_requests / $ab_instances))
    concurrency_per_ab=$(($current_concurrency / $ab_instances))
    concurrency_left=${current_concurrency}
    requests_left=${total_requests}
    while [ ${concurrency_left} -gt ${max_concurrency_per_ab} ]; do
        concurrency_left=$(($concurrency_left - $concurrency_per_ab))
        requests_left=$(($requests_left - $total_request_per_ab))
        LogMsg "Running parallel ab command for: ${total_request_per_ab} X ${concurrency_per_ab}"
        ab -n ${total_request_per_ab} -r -c ${concurrency_per_ab} http://${SERVER}/test.dat & pid=$!
        PID_LIST+=" $pid"
    done

    if [ ${concurrency_left} -gt 0 ]
    then
        LogMsg "Running parallel ab command left for: ${requests_left} X ${concurrency_left}"
        ab -n ${requests_left} -r -c ${concurrency_left} http://${SERVER}/test.dat & pid=$!
        PID_LIST+=" $pid";
    fi
    trap "sudo kill ${PID_LIST}" SIGINT
    wait ${PID_LIST}
}

function run_nginx_bench ()
{
    current_concurrency=$1

    LogMsg "======================================"
    LogMsg "Running nginx_bench test with current concurrency: ${current_concurrency}"
    LogMsg "======================================"

    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "sar -n DEV 1 900   2>&1 > /tmp/nginx_bench/${current_concurrency}.sar.netio.log"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "iostat -x -d 1 900 2>&1 > /tmp/nginx_bench/${current_concurrency}.iostat.diskio.log"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "vmstat 1 900       2>&1 > /tmp/nginx_bench/${current_concurrency}.vmstat.memory.cpu.log"
    sar -n DEV 1 900   2>&1 > /tmp/nginx_bench/${current_concurrency}.sar.netio.log &
    iostat -x -d 1 900 2>&1 > /tmp/nginx_bench/${current_concurrency}.iostat.netio.log &
    vmstat 1 900       2>&1 > /tmp/nginx_bench/${current_concurrency}.vmstat.netio.log &

    run_ab ${current_concurrency} > /tmp/nginx_bench/${current_concurrency}.apache.bench.log

    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f sar"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f iostat"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f vmstat"
    sudo pkill -f sar
    sudo pkill -f iostat
    sudo pkill -f vmstat
    sudo pkill -f ab

    LogMsg "sleep 60 seconds"
    sleep 60
}

for threads in "${TEST_CONCURRENCY_THREADS[@]}"
do
    run_nginx_bench ${threads}
done

LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"

cd /tmp
zip -r nginx_bench.zip . -i nginx_bench/* >> ${LOG_FILE}
zip -r nginx_bench.zip . -i summary.log >> ${LOG_FILE}
