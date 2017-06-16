#!/bin/bash

#######################################################################
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
#######################################################################

LOG_FILE=/tmp/summary.log
function LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1} >> ${LOG_FILE}
}

if [ $# -lt 3 ]; then
    echo -e "\nUsage:\n$0 user master_store slave1, slave2, ..."
    exit 1
fi

USER="$1"
STORE="$2"
declare -a SLAVES=("${@:3}")
LogMsg "slaves are: ${SLAVES}"
teragen_records=500000000
hadoop_version="hadoop-2.7.3"
hadoop_store="/hadoop_store"
hadoop_tmp="${hadoop_store}/hdfs/tmp"
hadoop_namenode="${hadoop_store}/hdfs/namenode"
hadoop_datanode="${hadoop_store}/hdfs/datanode"
hadoop_conf="/tmp/${hadoop_version}/etc/hadoop"

LogMsg "Performing cleanup on master."
sudo pkill -f java
sudo rm -rf /tmp/hadoop*
sudo rm -rf /tmp/hsperfdata*
sudo umount -l ${hadoop_store}
sudo rm -rf ${hadoop_store}

distro="$(head -1 /etc/issue)"

sudo apt-get update && sudo apt-get upgrade -y >> ${LOG_FILE}
sudo apt-get install -y zip maven libssl-dev build-essential rsync pkgconf cmake protobuf-compiler libprotobuf-dev default-jdk openjdk-8-jdk bc >> ${LOG_FILE}

LogMsg "Upgrading procps - Azure issue."
sudo apt-get upgrade -y procps >> ${LOG_FILE}

LogMsg "Setting up hadoop."
cd /tmp
wget http://apache.javapipe.com/hadoop/common/${hadoop_version}/${hadoop_version}.tar.gz
tar -xzf ${hadoop_version}.tar.gz

java_home=$(dirname $(dirname $(readlink -f $(which javac))))

hadoop_exports="# Hadoop exports start\n
export JAVA_HOME=${java_home}\n
export HADOOP_HOME=/tmp/${hadoop_version}\n
export HADOOP_CONF_DIR=${hadoop_conf}\n
export HADOOP_MAPRED_HOME=\${HADOOP_HOME}\n
export HADOOP_COMMON_HOME=\${HADOOP_HOME}\n
export HADOOP_HDFS_HOME=\${HADOOP_HOME}\n
export YARN_HOME=\${HADOOP_HOME}\n
export HADOOP_COMMON_LIB_NATIVE_DIR=\${HADOOP_HOME}/lib/native\n
export PATH=\$PATH:\${HADOOP_HOME}/bin\n
export PATH=\$PATH:\${HADOOP_HOME}/sbin\n
export HADOOP_OPTS=\"-Djava.library.path=\${HADOOP_HOME}/lib\"\n
"
master_ip=`ip route get ${SLAVES[0]} | awk '{print $NF; exit}'`
hostname=`hostname -f`

grep -q "Hadoop exports start" ~/.bashrc
if [ $? -ne 0 ]; then
    echo -e ${hadoop_exports} >> ~/.bashrc
    source ~/.bashrc
fi

LogMsg "Formatting ${STORE} and mounting to ${hadoop_store}"
sudo mkfs.ext4 ${STORE}
sudo mkdir -p ${hadoop_store}
sudo mount ${STORE} ${hadoop_store}
sudo chown ${USER} ${hadoop_store}
mkdir -p ${hadoop_tmp}
mkdir -p ${hadoop_namenode}
mkdir -p ${hadoop_datanode}
mkdir -p /tmp/terasort

LogMsg "Updating hadoop-env.sh"
sed -i "s~export JAVA_HOME=\${JAVA_HOME}~export JAVA_HOME=${java_home}~g" ${hadoop_conf}/hadoop-env.sh

LogMsg "Updating core-site.xml"
sed -i "s~</configuration>~    <property>~g" ${hadoop_conf}/core-site.xml
echo "        <name>fs.default.name</name>" >> ${hadoop_conf}/core-site.xml
echo "        <value>hdfs://${master_ip}:9000</value>" >> ${hadoop_conf}/core-site.xml
echo "    </property>" >> ${hadoop_conf}/core-site.xml
echo "    <property>" >> ${hadoop_conf}/core-site.xml
echo "        <name>hadoop.tmp.dir</name>" >> ${hadoop_conf}/core-site.xml
echo "        <value>${hadoop_tmp}</value>" >> ${hadoop_conf}/core-site.xml
echo "    </property>" >> ${hadoop_conf}/core-site.xml
echo "</configuration>" >> ${hadoop_conf}/core-site.xml

LogMsg "Updating hdfs-site.xml"
sed -i "s~</configuration>~    <property>~g" ${hadoop_conf}/hdfs-site.xml
echo "        <name>dfs.replication</name>" >> ${hadoop_conf}/hdfs-site.xml
echo "        <value>2</value>" >> ${hadoop_conf}/hdfs-site.xml
echo "    </property>" >> ${hadoop_conf}/hdfs-site.xml
echo "    <property>" >> ${hadoop_conf}/hdfs-site.xml
echo "        <name>dfs.namenode.name.dir</name>" >> ${hadoop_conf}/hdfs-site.xml
echo "        <value>file:${hadoop_namenode}</value>" >> ${hadoop_conf}/hdfs-site.xml
echo "    </property>" >> ${hadoop_conf}/hdfs-site.xml
echo "    <property>" >> ${hadoop_conf}/hdfs-site.xml
echo "        <name>dfs.datanode.data.dir</name>" >> ${hadoop_conf}/hdfs-site.xml
echo "        <value>file:${hadoop_datanode}</value>" >> ${hadoop_conf}/hdfs-site.xml
echo "    </property>" >> ${hadoop_conf}/hdfs-site.xml
echo "    <property>" >> ${hadoop_conf}/hdfs-site.xml
echo "        <name>dfs.permissions</name>" >> ${hadoop_conf}/hdfs-site.xml
echo "        <value>false</value>" >> ${hadoop_conf}/hdfs-site.xml
echo "    </property>" >> ${hadoop_conf}/hdfs-site.xml
echo "</configuration>" >> ${hadoop_conf}/hdfs-site.xml

LogMsg "Updating yarn-site.xml"
sed -i "s~</configuration>~    <property>~g" ${hadoop_conf}/yarn-site.xml
echo "        <name>yarn.nodemanager.aux-services</name>" >> ${hadoop_conf}/yarn-site.xml
echo "        <value>mapreduce_shuffle</value>" >> ${hadoop_conf}/yarn-site.xml
echo "    </property>" >> ${hadoop_conf}/yarn-site.xml
echo "    <property>" >> ${hadoop_conf}/yarn-site.xml
echo "        <name>yarn.nodemanager.aux-services.mapreduce.shuffle.class</name>" >> ${hadoop_conf}/yarn-site.xml
echo "        <value>org.apache.hadoop.mapred.ShuffleHandler</value>" >> ${hadoop_conf}/yarn-site.xml
echo "    </property>" >> ${hadoop_conf}/yarn-site.xml
echo "</configuration>" >> ${hadoop_conf}/yarn-site.xml

LogMsg "Creating and updating mapred-site.xml"
cp ${hadoop_conf}/mapred-site.xml.template ${hadoop_conf}/mapred-site.xml
sed -i "s~</configuration>~    <property>~g" ${hadoop_conf}/mapred-site.xml
echo "        <name>mapreduce.framework.name</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>yarn</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}//mapred-site.xml
echo "</configuration>" >> ${hadoop_conf}//mapred-site.xml

echo -e ${master_ip} > ${hadoop_conf}/masters
echo -e ${master_ip} > ${hadoop_conf}/slaves
echo -e > /home/${USER}/.ssh/known_hosts
ssh -o StrictHostKeyChecking=no ${USER}@${hostname} "ls"
ssh -o StrictHostKeyChecking=no ${USER}@0.0.0.0 "ls"

for slave in "${SLAVES[@]}"
do
    LogMsg "Performing cleanup on: ${slave}"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${slave} "sudo pkill -f java" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${slave} "sudo rm -rf /tmp/hadoop*" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${slave} "sudo rm -rf /tmp/hsperfdata*" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${slave} "sudo umount -l ${hadoop_store}" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${slave} "sudo rm -rf ${hadoop_store}" >> ${LOG_FILE}
    LogMsg "Configuring hadoop on: ${slave}"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${slave} "sudo apt-get update && sudo apt-get upgrade -y" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${slave} "sudo apt-get install -y maven libssl-dev rsync build-essential pkgconf cmake protobuf-compiler libprotobuf-dev default-jdk openjdk-8-jdk bc" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${slave} "sudo apt-get upgrade -y procps" >> ${LOG_FILE}
    scp -o StrictHostKeyChecking=no /tmp/${hadoop_version}.tar.gz ${USER}@${slave}:/tmp >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${slave} "cd /tmp;tar -xzf ${hadoop_version}.tar.gz" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${slave} "echo -e '${hadoop_exports}' >> ~/.bashrc" >> ${LOG_FILE}

    LogMsg "Copying hadoop conf files on: ${slave}"
    scp -o StrictHostKeyChecking=no ${hadoop_conf}/hadoop-env.sh ${hadoop_conf}/core-site.xml ${hadoop_conf}/hdfs-site.xml ${hadoop_conf}/mapred-site.xml ${USER}@${slave}:${hadoop_conf}/
    ssh -o StrictHostKeyChecking=no ${USER}@${slave} "echo -e '${master_ip}' >> ${hadoop_conf}/masters" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${slave} "echo -e '${slave}' > ${hadoop_conf}/slaves" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${slave} "echo -e > /home/${USER}/.ssh/known_hosts" >> ${LOG_FILE}
    echo -e ${slave} >> ${hadoop_conf}/slaves

    LogMsg "Setting up hadoop store ${hadoop_store} on ${slave}"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${slave} "sudo mkfs.ext4 ${STORE}" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${slave} "sudo mkdir -p ${hadoop_store}" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${slave} "sudo mount ${STORE} ${hadoop_store}" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${slave} "sudo chown ${USER} ${hadoop_store}" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${slave} "mkdir -p ${hadoop_tmp}" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${slave} "mkdir -p ${hadoop_namenode}" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${slave} "mkdir -p ${hadoop_datanode}" >> ${LOG_FILE}
done

LogMsg "Info : Formatting HDFS"
/tmp/${hadoop_version}/bin/hdfs namenode -format
sleep 10
LogMsg "Info : Starting DFS"
/tmp/${hadoop_version}/sbin/start-dfs.sh >> ${LOG_FILE}
sleep 10
LogMsg "Info : Starting Yarn"
/tmp/${hadoop_version}/sbin/start-yarn.sh >> ${LOG_FILE}
sleep 10
LogMsg "Info : Run TeraGen to create test data"
/tmp/${hadoop_version}/bin/hadoop jar /tmp/${hadoop_version}/share/hadoop/mapreduce/hadoop-*examples*.jar teragen ${teragen_records} ${hadoop_store}/genout
LogMsg "Info : Running TeraSort to sort test data"
sleep 10
# Number of Reduces = ( 1.75 * num-of-nodes * num-of-containers-per-node )
# d2.4xlarge = 1.75 * 4 * 16 = 112
# c4.large = 1.75 * 4 * 2 = 14
/tmp/${hadoop_version}/bin/hadoop jar /tmp/${hadoop_version}/share/hadoop/mapreduce/hadoop-*examples*.jar terasort -Dmapreduce.job.reduces=112 ${hadoop_store}/genout ${hadoop_store}/sortout 2&> /tmp/terasort/terasort.log

LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"
LogMsg "Hadoop Version : ${hadoop_version}"

cd /tmp
zip -r terasort.zip . -i terasort/* >> ${LOG_FILE}
zip -r terasort.zip . -i summary.log >> ${LOG_FILE}
