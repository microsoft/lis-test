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
DISK="$2"
Zookeeper_Node="$3"
Broker_Node="$4"
declare -a All_Nodes=("${@:3}")
declare -a Broker_Nodes=("${@:4}")
record_sizes=(100 500 1000)
batch_sizes=(8192 16384)
buffer_mem=67108864
Partition_Num=12
kfaka_version='1.0.0'


if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi

distro="$(head -1 /etc/issue)"
web_server=
#common configuration start
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt-get -y update >> ${LOG_FILE}
    sudo apt-get -y install default-jdk sysstat zip >> ${LOG_FILE}
    curl -O http://www-eu.apache.org/dist/kafka/1.0.0/kafka_2.12-1.0.0.tgz
    tar xzvf kafka_2.12-1.0.0.tgz
    for Node in "${All_Nodes[@]}"
    do
        LogMsg "-------start common configuration on ${Node}-----------------"
        ssh -T -o StrictHostKeyChecking=no ${USER}@${Node} "sudo apt-get -y update" >> ${LOG_FILE}
        ssh -T -o StrictHostKeyChecking=no ${USER}@${Node} "sudo apt -y install default-jdk sysstat zip" >> ${LOG_FILE}
        ssh -T -o StrictHostKeyChecking=no ${USER}@${Node} "curl -O http://www-eu.apache.org/dist/kafka/1.0.0/kafka_2.12-1.0.0.tgz"
        ssh -T -o StrictHostKeyChecking=no ${USER}@${Node} "tar xzvf kafka_2.12-1.0.0.tgz"
    done
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum clean dbcache>> ${LOG_FILE}
    sudo yum -y remove java
    sudo yum -y install java-1.8.0-openjdk sysstat zip >> ${LOG_FILE}
    curl -O http://www-eu.apache.org/dist/kafka/1.0.0/kafka_2.12-1.0.0.tgz
    tar xzvf kafka_2.12-1.0.0.tgz
    for Node in "${All_Nodes[@]}"
    do
        LogMsg "-------start common configuration on ${Node}-----------------"
        ssh -T -o StrictHostKeyChecking=no ${USER}@${Node} "sudo yum clean dbcache" >> ${LOG_FILE}
        ssh -T -o StrictHostKeyChecking=no ${USER}@${Node} "sudo yum -y remove java"
        ssh -T -o StrictHostKeyChecking=no ${USER}@${Node} "sudo yum -y install java-1.8.0-openjdk sysstat zip" >> ${LOG_FILE}
        ssh -T -o StrictHostKeyChecking=no ${USER}@${Node} "curl -O http://www-eu.apache.org/dist/kafka/1.0.0/kafka_2.12-1.0.0.tgz"
        ssh -T -o StrictHostKeyChecking=no ${USER}@${Node} "tar xzvf kafka_2.12-1.0.0.tgz"
    done
else
    LogMsg "Unsupported distribution: ${distro}."
fi
#common configuration end


LogMsg "Start zookeeper on Zookeeper Node ${Zookeeper_Node}"
ssh -T -o StrictHostKeyChecking=no ${USER}@${Zookeeper_Node} "cd kafka_2.12-1.0.0;bin/zookeeper-server-start.sh -daemon config/zookeeper.properties" >> ${LOG_FILE}

LogMsg "Configure for each Broker Node"
BrokerID=0
for Broker_Node in "${Broker_Nodes[@]}"
do
    ssh -T -o StrictHostKeyChecking=no ${USER}@${Broker_Node} "(echo n;echo p;echo 1;echo;echo;echo w)|sudo fdisk ${DISK}" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${Broker_Node} "sleep 10"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${Broker_Node} "sudo mkdir /data" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${Broker_Node} "sudo mkfs.ext4 ${DISK}1" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${Broker_Node} "sudo mount ${DISK}1 /data" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${Broker_Node} "sudo chmod a+w /data"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${Broker_Node} "sudo rm -rf /data/*"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${Broker_Node} "sed -i 's/broker.id=0/broker.id='${BrokerID}'/' kafka_2.12-1.0.0/config/server.properties"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${Broker_Node} "sed -i '\$i\listeners=PLAINTEXT://'${Broker_Node}':9092' kafka_2.12-1.0.0/config/server.properties"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${Broker_Node} "sed -i 's/zookeeper.connect=localhost:2181/zookeeper.connect='${Zookeeper_Node}':2181/' kafka_2.12-1.0.0/config/server.properties"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${Broker_Node} "sed -i '/log.dirs=/d' kafka_2.12-1.0.0/config/server.properties"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${Broker_Node} "sed -i '\$a\log.dirs=/data' kafka_2.12-1.0.0/config/server.properties"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${Broker_Node} "cd kafka_2.12-1.0.0;bin/kafka-server-start.sh -daemon config/server.properties" >> ${LOG_FILE}
    BrokerID=$[BrokerID+1]
done



LogMsg "start kafka testing"
mkdir -p /tmp/kafka
cd kafka_2.12-1.0.0
# Create topics
# no replication
bin/kafka-topics.sh --zookeeper ${Zookeeper_Node}:2181 --create --topic test-rep-one --partitions ${Partition_Num} --replication-factor 1
# 3x replication
bin/kafka-topics.sh --zookeeper ${Zookeeper_Node}:2181 --create --topic test-rep-three --partitions ${Partition_Num} --replication-factor 3
for record_size in "${record_sizes[@]}"
do
    for batch_size in "${batch_sizes[@]}"
    do
        LogMsg "======================================"
        LogMsg "Runn kafka test with record_size: ${record_size}, batch_size: ${batch_size}"
        LogMsg "======================================"
        bin/kafka-run-class.sh org.apache.kafka.tools.ProducerPerformance --topic test-rep-one \
        --num-records 50000000 --record-size ${record_size}  --throughput -1 --producer-props acks=1 \
        bootstrap.servers=${Broker_Node}:9092 buffer.memory=${buffer_mem} \
        batch.size=${batch_size} > /tmp/kafka/kafka${kfaka_version}_1_${Partition_Num}_${buffer_mem}_${record_size}_${batch_size}.log

        bin/kafka-run-class.sh org.apache.kafka.tools.ProducerPerformance --topic test-rep-three \
        --num-records 50000000 --record-size ${record_size}  --throughput -1 --producer-props acks=1 \
        bootstrap.servers=${Broker_Node}:9092 buffer.memory=${buffer_mem} \
        batch.size=${batch_size} > /tmp/kafka/kafka${kfaka_version}_3_${Partition_Num}_${buffer_mem}_${record_size}_${batch_size}.log
    done
done

LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"

cd /tmp
zip -r kafka.zip . -i kafka/* >> ${LOG_FILE}
zip -r kafka.zip . -i summary.log >> ${LOG_FILE}

