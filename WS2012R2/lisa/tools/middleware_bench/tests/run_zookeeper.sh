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
    echo -e "\nUsage:\n$0 user server1, server2, server3, ..."
    exit 1
fi

USER="$1"
declare -a SERVERS=("${@:2}")
client_threads_collection=(1 2 4 8 12 16 20)
watch_multiple=5
znode_size=100
znode_count=10000
zk_version="zookeeper-3.4.9"
zk_data="/zk/data"

if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi

distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt -y install libaio1 sysstat zip default-jdk git python-dev libzookeeper-mt-dev python-pip >> ${LOG_FILE}
    sudo -H pip install zkpython >> ${LOG_FILE}
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum clean dbcache>> ${LOG_FILE}
    sudo yum -y install sysstat zip java git python-devel python-pip gcc libtool autoconf automake >> ${LOG_FILE}
    cd /tmp
    wget ftp://rpmfind.net/linux/centos/6/os/x86_64/Packages/cppunit-1.12.1-3.1.el6.x86_64.rpm
    sudo yum localinstall -y /tmp/cppunit-1.12.1-3.1.el6.x86_64.rpm
    wget ftp://rpmfind.net/linux/centos/6/os/x86_64/Packages/cppunit-devel-1.12.1-3.1.el6.x86_64.rpm
    sudo yum localinstall -y /tmp/cppunit-devel-1.12.1-3.1.el6.x86_64.rpm
    wget http://apache.spinellicreations.com/zookeeper/${zk_version}/${zk_version}.tar.gz
    tar -xzf ${zk_version}.tar.gz
    cd ${zk_version}/src/c; sudo autoreconf -if; ./configure; sudo make install
    sudo -H pip install zkpython >> ${LOG_FILE}
else
    LogMsg "Unsupported distribution: ${distro}."
fi

cd /tmp
git clone https://github.com/phunt/zk-smoketest >> ${LOG_FILE}

function run_zk ()
{
    parallel_clients=$1
    for (( client_id=1; client_id<=${parallel_clients}; client_id++ ))
    do
        LogMsg  "Running zk-latency client with: --cluster=${cluster_string} --znode_size=${znode_size} --znode_count=${znode_count} --timeout=5000 --watch_multiple=${watch_multiple} --root_znode=/TESTNODE${client_id}"
        sudo PYTHONPATH="/tmp/zk-smoketest/lib.linux-x86_64-2.6" LD_LIBRARY_PATH="/tmp/zk-smoketest/lib.linux-x86_64-2.6" python /tmp/zk-smoketest/zk-latencies.py --cluster=${cluster_string} --znode_size=${znode_size} --znode_count=${znode_count} --timeout=5000 --watch_multiple=${watch_multiple} --root_znode=/TESTNODE${client_id} --force & pid=$!
        PID_LIST+=" $pid"
    done

    trap "sudo kill ${PID_LIST}" SIGINT
    wait ${PID_LIST}
}

for server in "${SERVERS[@]}"
do
    LogMsg "Configuring zookeeper server on: ${server}"
    if [[ ${distro} == *"Ubuntu"* ]]
    then
        ssh -T -o StrictHostKeyChecking=no ${USER}@${server} "sudo apt update" >> ${LOG_FILE}
        ssh -T -o StrictHostKeyChecking=no ${USER}@${server} "sudo apt -y install libaio1 sysstat default-jdk" >> ${LOG_FILE}
    elif [[ ${distro} == *"Amazon"* ]]
    then
        ssh -T -o StrictHostKeyChecking=no ${USER}@${server} "sudo yum clean dbcache" >> ${LOG_FILE}
        ssh -T -o StrictHostKeyChecking=no ${USER}@${server} "sudo yum -y install sysstat zip java libtool" >> ${LOG_FILE}
        ssh -T -o StrictHostKeyChecking=no ${USER}@${server} "cd /tmp; wget ftp://rpmfind.net/linux/centos/6/os/x86_64/Packages/cppunit-1.12.1-3.1.el6.x86_64.rpm" >> ${LOG_FILE}
        ssh -T -o StrictHostKeyChecking=no ${USER}@${server} "sudo yum localinstall -y /tmp/cppunit-1.12.1-3.1.el6.x86_64.rpm" >> ${LOG_FILE}
        ssh -T -o StrictHostKeyChecking=no ${USER}@${server} "cd /tmp; wget ftp://rpmfind.net/linux/centos/6/os/x86_64/Packages/cppunit-devel-1.12.1-3.1.el6.x86_64.rpm" >> ${LOG_FILE}
        ssh -T -o StrictHostKeyChecking=no ${USER}@${server} "sudo yum localinstall -y /tmp/cppunit-devel-1.12.1-3.1.el6.x86_64.rpm" >> ${LOG_FILE}
    else
        LogMsg "Unsupported distribution: ${distro}."
    fi
    ssh -o StrictHostKeyChecking=no ${USER}@${server} "cd /tmp;wget http://apache.spinellicreations.com/zookeeper/${zk_version}/${zk_version}.tar.gz" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${server} "cd /tmp;tar -xzf ${zk_version}.tar.gz"
    ssh -o StrictHostKeyChecking=no ${USER}@${server} "cp /tmp/${zk_version}/conf/zoo_sample.cfg /tmp/${zk_version}/conf/zoo.cfg" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${server} "sed -i '/tickTime/c\tickTime=2000' /tmp/${zk_version}/conf/zoo.cfg" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${server} "sed -i '/dataDir/c\dataDir=${zk_data}' /tmp/${zk_version}/conf/zoo.cfg" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${server} "sed -i '/clientPort/c\clientPort=2181' /tmp/${zk_version}/conf/zoo.cfg" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${server} "sed -i '/initLimit/c\initLimit=5' /tmp/${zk_version}/conf/zoo.cfg" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${server} "sed -i '/syncLimit/c\syncLimit=2' /tmp/${zk_version}/conf/zoo.cfg" >> ${LOG_FILE}
    for temp_server in "${SERVERS[@]}"
    do
        i=1
        ssh -o StrictHostKeyChecking=no ${USER}@${server} "echo -e 'server.${i}=${temp_server}:2888:3888' >> /tmp/${zk_version}/conf/zoo.cfg" >> ${LOG_FILE}
        if [ ${temp_server} == ${server} ]
        then
            ssh -T -o StrictHostKeyChecking=no ${USER}@${server} "sudo mkdir -p ${zk_data}" >> ${LOG_FILE}
            ssh -T -o StrictHostKeyChecking=no ${USER}@${server} "sudo chown ${USER} ${zk_data}" >> ${LOG_FILE}
            ssh -o StrictHostKeyChecking=no ${USER}@${server} "echo -e ${i} > ${zk_data}/myid" >> ${LOG_FILE}
        fi
        i=$(($i + 1))
    done
    cluster_string=$cluster_string$","${server}":2181"
done

cluster_string=$(echo ${cluster_string} | cut -b 2-)
mkdir -p /tmp/zookeeper

for threads in "${client_threads_collection[@]}"
do
    for server in "${SERVERS[@]}"
    do
        ssh -T -o StrictHostKeyChecking=no ${USER}@${server} "sudo /tmp/${zk_version}/bin/zkServer.sh start" >> ${LOG_FILE}
        LogMsg "Waiting zookeeper to start on server ${server}"
        sleep 20
        ssh -o StrictHostKeyChecking=no ${USER}@${server} "mkdir -p /tmp/zookeeper"
        ssh -f -o StrictHostKeyChecking=no ${USER}@${server} "sar -n DEV 1 2>&1 > /tmp/zookeeper/${threads}.sar.netio.log"
        ssh -f -o StrictHostKeyChecking=no ${USER}@${server} "iostat -x -d 1 2>&1 > /tmp/zookeeper/${threads}.iostat.diskio.log"
        ssh -f -o StrictHostKeyChecking=no ${USER}@${server} "vmstat 1 2>&1 > /tmp/zookeeper/${threads}.vmstat.memory.cpu.log"
        ssh -f -o StrictHostKeyChecking=no ${USER}@${server} "mpstat -P ALL 1 2>&1 > /tmp/zookeeper/${threads}.mpstat.cpu.log"
    done

    sar -n DEV 1 2>&1 > /tmp/zookeeper/${threads}.sar.netio.log &
    iostat -x -d 1 2>&1 > /tmp/zookeeper/${threads}.iostat.netio.log &
    vmstat 1 2>&1 > /tmp/zookeeper/${threads}.vmstat.netio.log &
    mpstat -P ALL 1 2>&1 > /tmp/zookeeper/${threads}.mpstat.cpu.log &
    LogMsg  "Running zookeeper with ${threads} parallel client(s)."
    run_zk ${threads} > /tmp/zookeeper/${threads}.zookeeper.latency.log
    sudo pkill -f sar
    sudo pkill -f iostat
    sudo pkill -f vmstat
    sudo pkill -f mpstat

    for server in "${SERVERS[@]}"
    do
        LogMsg  "Cleaning up zookeeper server ${server} for ${threads} parallel clients."
        ssh -T -o StrictHostKeyChecking=no ${USER}@${server} "sudo pkill -f sar"
        ssh -T -o StrictHostKeyChecking=no ${USER}@${server} "sudo pkill -f iostat"
        ssh -T -o StrictHostKeyChecking=no ${USER}@${server} "sudo pkill -f vmstat"
        ssh -T -o StrictHostKeyChecking=no ${USER}@${server} "sudo pkill -f mpstat"
        ssh -T -o StrictHostKeyChecking=no ${USER}@${server} "sudo /tmp/${zk_version}/bin/zkServer.sh stop"
        ssh -T -o StrictHostKeyChecking=no ${USER}@${server} "sudo rm -rf ${zk_data}/version-2"
    done
    sleep 20
done

LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"

cd /tmp
zip -r zookeeper.zip . -i zookeeper/* >> ${LOG_FILE}
zip -r zookeeper.zip . -i summary.log >> ${LOG_FILE}
