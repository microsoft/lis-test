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
    echo -e "\nUsage:\n$0 user server1, server2 ..."
    exit 1
fi

USER="$1"
declare -a SERVERS=("${@:2}")
watch_multiple=5
num_zk_client=10
znode_size=10
znode_count=1000000

if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi

sudo apt-get update >> ${LOG_FILE}
sudo apt-get -y install libaio1 sysstat zip default-jdk wget python-dev libzookeeper-mt-dev python-pip>> ${LOG_FILE}
sudo pip install zkpython

cd /tmp
wget http://apache.spinellicreations.com/zookeeper/zookeeper-3.4.9/zookeeper-3.4.9.tar.gz
ssh root@${SERVER} "tar -xzf ./${ZK_ARCHIVE}"
ssh root@${SERVER} "cp zookeeper-${ZK_VERSION}/conf/zoo_sample.cfg zookeeper-${ZK_VERSION}/conf/zoo.cfg"
ssh root@${SERVER} "zookeeper-${ZK_VERSION}/bin/zkServer.sh start"

for server in "${SERVERS[@]}"
do
    sudo apt-get update >> ${LOG_FILE}
    #sudo apt-get upgrade -y >> ${LOG_FILE}
    sudo apt-get -y install libaio1 sysstat java >> ${LOG_FILE}
    LogMsg "configure logging on: $server"
    java_pid=$(ssh ${USER}@${server} pidof java)
    LogMsg "Java pid: $java_pid"

    ssh -oStrictHostKeyChecking=no ${USER}@${server} "mkdir -p /tmp/zookeeper"
    ssh -f -oStrictHostKeyChecking=no ${USER}@${server} "sar -n DEV 1 900   2>&1 > /tmp/zookeeper/sar.netio.log"
    ssh -f -oStrictHostKeyChecking=no ${USER}@${server} "iostat -x -d 1 900 2>&1 > /tmp/zookeeper/iostat.diskio.log"
    ssh -f -oStrictHostKeyChecking=no ${USER}@${server} "vmstat 1 900       2>&1 > /tmp/zookeeper/vmstat.memory.cpu.log"
    ssh -f -oStrictHostKeyChecking=no ${USER}@${server} "mpstat -P ALL 1 900 2>&1 > /tmp/zookeeper/mpstat.cpu.log"
    #we need to  get the pid from server side before executing this ssh command,
    #otherwise $(pidof mysql) will be evaluated on client side which returns NULL
    ssh -f -oStrictHostKeyChecking=no ${USER}@${server} "pidstat -h -r -u -v -p $java_pid 1 900 2>&1 > /tmp/zookeeper/pidstat.cpu.log"
    cluster_string=$cluster_string$","${server}":2181"
done

# testing
cluster_string=$(echo ${cluster_string} | cut -b 2-)
mkdir -p /tmp/zookeeper
sar -n DEV 1 900   2>&1 > /tmp/zookeeper/sar.netio.log &
iostat -x -d 1 900 2>&1 > /tmp/zookeeper/iostat.netio.log &
vmstat 1 900       2>&1 > /tmp/zookeeper/vmstat.netio.log &
mpstat -P ALL 1 900 2>&1 > /tmp/zookeeper/mpstat.cpu.log &

for (( client_id=1; client_id<=${num_zk_client}; client_id++ ))
do
    LogMsg  "Run Test on ${client_id}: --cluster=${cluster_string} --znode_size=${znode_size} --znode_count=${znode_count} --timeout=5000 --watch_multiple=${watch_multiple} --root_znode=/TESTNODE${client_id}"
    ./zk-smoketest/zk-latencies.py --cluster=${cluster_string} --znode_size=${znode_size} --znode_count=${znode_count} --timeout=5000 --watch_multiple=${watch_multiple} --root_znode=/TESTNODE${client_id} > /tmp/zookeeper/${client_id}.zookeeper.latency.log &
done

read -p "Press [Enter] key to start tearing down the test if all threads finished ..."

sudo pkill -f sar
sudo pkill -f iostat
sudo pkill -f vmstat
sudo pkill -f mpstat

for server in "${SERVERS[@]}"
do
    #cleanup processes
    ssh -T -oStrictHostKeyChecking=no ${USER}@${server} "sudo pkill -f sar"
    ssh -T -oStrictHostKeyChecking=no ${USER}@${server} "sudo pkill -f iostat"
    ssh -T -oStrictHostKeyChecking=no ${USER}@${server} "sudo pkill -f vmstat"
    ssh -T -oStrictHostKeyChecking=no ${USER}@${server} "sudo pkill -f mpstat"
    ssh -T -oStrictHostKeyChecking=no ${USER}@${server} "sudo pkill -f pidstat"
done

LogMsg "Kernel Version : `uname -r`"

cd /tmp
zip -r zookeeper.zip . -i zookeeper/* >> ${LOG_FILE}
zip -r zookeeper.zip . -i summary.log >> ${LOG_FILE}
