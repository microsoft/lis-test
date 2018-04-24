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
LogMsg "slaves are: ${SLAVES[*]}"
teragen_records=500000000
hadoop_version="hadoop-2.8.3"
hadoop_store="/hadoop_store"
hadoop_tmp="${hadoop_store}/hdfs/tmp"
hadoop_namenode="${hadoop_store}/hdfs/namenode"
hadoop_datanode="${hadoop_store}/hdfs/datanode"
hadoop_conf="/tmp/${hadoop_version}/etc/hadoop"
history_tmp="${hadoop_store}/job_history_tmp"
history_done="${hadoop_store}/job_history_done"

LogMsg "Performing cleanup on master."
sudo pkill -f java
sudo rm -rf /tmp/hadoop*
sudo rm -rf /tmp/hsperfdata*
sudo umount -l ${hadoop_store}
sudo rm -rf ${hadoop_store}

distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt update
    sudo apt install -y zip maven libssl-dev build-essential rsync pkgconf cmake protobuf-compiler libprotobuf-dev default-jdk openjdk-8-jdk-headless bc
    sudo sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade
    if [ $? != 0 ]; then
        LogMsg "ERROR: Dependencies install failed."
    fi
    LogMsg "Upgrading procps - Azure issue."
    sudo apt upgrade -y procps >> ${LOG_FILE}
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum clean dbcache
    sudo yum -y install sysstat zip java java-devel automake autoconf rsync cmake gcc libtool* protobuf-compiler bc
else
    LogMsg "Unsupported distribution: ${distro}."
fi

LogMsg "Setting up hadoop."
cd /tmp
wget http://apache.javapipe.com/hadoop/common/${hadoop_version}/${hadoop_version}.tar.gz
tar -xzf ${hadoop_version}.tar.gz

java_home=$(dirname $(dirname $(readlink -f $(which java))))

hadoop_exports="# Hadoop exports start\n
export JAVA_HOME=${java_home}\n
export HADOOP_PREFIX=/tmp/${hadoop_version}\n
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

master_ip=$(hostname -I)
master_ip=`echo ${master_ip//[[:blank:]]/}`

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

# for DataNodes and NodeManagers
datanode_config="/tmp/datanode"
mkdir -p ${datanode_config}
cp ${hadoop_conf}/hdfs-site.xml ${datanode_config}/
LogMsg "Configuring DataNodes and NodeManagers hdfs-site.xml"
sed -i "s~</configuration>~    <property>~g" ${datanode_config}/hdfs-site.xml
echo "        <name>dfs.datanode.data.dir</name>" >> ${datanode_config}/hdfs-site.xml
echo "        <value>file://${hadoop_datanode}</value>" >> ${datanode_config}/hdfs-site.xml
echo "    </property>" >> ${datanode_config}/hdfs-site.xml
echo "</configuration>" >> ${datanode_config}/hdfs-site.xml
cp ${hadoop_conf}/yarn-site.xml ${datanode_config}/
LogMsg "Configuring DataNodes and NodeManagers yarn-site.xml"
sed -i "s~</configuration>~    <property>~g" ${datanode_config}/yarn-site.xml
echo "        <name>yarn.resourcemanager.hostname</name>" >> ${datanode_config}/yarn-site.xml
echo "        <value>master</value>" >> ${datanode_config}/yarn-site.xml
echo "    </property>" >> ${datanode_config}/yarn-site.xml
echo "    <property>" >> ${datanode_config}/yarn-site.xml
echo "        <name>yarn.nodemanager.aux-services</name>" >> ${datanode_config}/yarn-site.xml
echo "        <value>mapreduce_shuffle</value>" >> ${datanode_config}/yarn-site.xml
echo "    </property>" >> ${datanode_config}/yarn-site.xml
echo "    <property>" >> ${datanode_config}/yarn-site.xml
echo "        <name>yarn.nodemanager.aux-services.mapreduce_shuffle.class</name>" >> ${datanode_config}/yarn-site.xml
echo "        <value>org.apache.hadoop.mapred.ShuffleHandler</value>" >> ${datanode_config}/yarn-site.xml
echo "    </property>" >> ${datanode_config}/yarn-site.xml
echo "    <property>" >> ${datanode_config}/yarn-site.xml
echo "        <name>yarn.nodemanager.resource.detect-hardware-capabilities</name>" >> ${datanode_config}/yarn-site.xml
echo "        <value>true</value>" >> ${datanode_config}/yarn-site.xml
echo "    </property>" >> ${datanode_config}/yarn-site.xml
echo "</configuration>" >> ${datanode_config}/yarn-site.xml

# for all
LogMsg "Updating default hadoop-env.sh"
sed -i "s~export JAVA_HOME=\${JAVA_HOME}~export JAVA_HOME=${java_home}~g" ${hadoop_conf}/hadoop-env.sh
LogMsg "Updating default core-site.xml"
sed -i "s~</configuration>~    <property>~g" ${hadoop_conf}/core-site.xml
echo "        <name>fs.defaultFS</name>" >> ${hadoop_conf}/core-site.xml
echo "        <value>hdfs://master:9000/</value>" >> ${hadoop_conf}/core-site.xml
echo "    </property>" >> ${hadoop_conf}/core-site.xml
echo "    <property>" >> ${hadoop_conf}/core-site.xml
echo "        <name>io.file.buffer.size</name>" >> ${hadoop_conf}/core-site.xml
echo "        <value>131072</value>" >> ${hadoop_conf}/core-site.xml
echo "    </property>" >> ${hadoop_conf}/core-site.xml
echo "    <property>" >> ${hadoop_conf}/core-site.xml
echo "        <name>hadoop.tmp.dir</name>" >> ${hadoop_conf}/core-site.xml
echo "        <value>${hadoop_tmp}</value>" >> ${hadoop_conf}/core-site.xml
echo "    </property>" >> ${hadoop_conf}/core-site.xml
echo "</configuration>" >> ${hadoop_conf}/core-site.xml

# for NameNode and ResourceManager
LogMsg "Configuring NameNode hdfs-site.xml"
sed -i "s~</configuration>~    <property>~g" ${hadoop_conf}/hdfs-site.xml
echo "        <name>dfs.namenode.name.dir</name>" >> ${hadoop_conf}/hdfs-site.xml
echo "        <value>file://${hadoop_namenode}</value>" >> ${hadoop_conf}/hdfs-site.xml
echo "    </property>" >> ${hadoop_conf}/hdfs-site.xml
echo "    <property>" >> ${hadoop_conf}/hdfs-site.xml
echo "        <name>dfs.blocksize</name>" >> ${hadoop_conf}/hdfs-site.xml
echo "        <value>268435456</value>" >> ${hadoop_conf}/hdfs-site.xml
echo "    </property>" >> ${hadoop_conf}/hdfs-site.xml
echo "    <property>" >> ${hadoop_conf}/hdfs-site.xml
echo "        <name>dfs.namenode.handler.count</name>" >> ${hadoop_conf}/hdfs-site.xml
echo "        <value>100</value>" >> ${hadoop_conf}/hdfs-site.xml
echo "    </property>" >> ${hadoop_conf}/hdfs-site.xml
echo "</configuration>" >> ${hadoop_conf}/hdfs-site.xml
LogMsg "Configuring ResourceManager yarn-site.xml"
sed -i "s~</configuration>~    <property>~g" ${hadoop_conf}/yarn-site.xml
echo "        <name>yarn.resourcemanager.hostname</name>" >> ${hadoop_conf}/yarn-site.xml
echo "        <value>master</value>" >> ${hadoop_conf}/yarn-site.xml
echo "    </property>" >> ${hadoop_conf}/yarn-site.xml
echo "    <property>" >> ${hadoop_conf}/yarn-site.xml
echo "        <name>yarn.resourcemanager.scheduler.class</name>" >> ${hadoop_conf}/yarn-site.xml
echo "        <value>org.apache.hadoop.yarn.server.resourcemanager.scheduler.capacity.CapacityScheduler</value>" >> ${hadoop_conf}/yarn-site.xml
echo "    </property>" >> ${hadoop_conf}/yarn-site.xml
echo "</configuration>" >> ${hadoop_conf}/yarn-site.xml
LogMsg "Configuring NameNode mapred-site.xml"
cp ${hadoop_conf}/mapred-site.xml.template ${hadoop_conf}/mapred-site.xml
sed -i "s~</configuration>~    <property>~g" ${hadoop_conf}/mapred-site.xml
echo "        <name>mapreduce.framework.name</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>yarn</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "    <property>" >> ${hadoop_conf}/mapred-site.xml
echo "        <name>mapreduce.map.memory.mb</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>1536</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "    <property>" >> ${hadoop_conf}/mapred-site.xml
echo "        <name>mapreduce.map.java.opts</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>-Xmx1024M</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "    <property>" >> ${hadoop_conf}/mapred-site.xml
echo "        <name>mapreduce.reduce.memory.mb</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>3072</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "    <property>" >> ${hadoop_conf}/mapred-site.xml
echo "        <name>mapreduce.reduce.java.opts</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>-Xmx2560M</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "    <property>" >> ${hadoop_conf}/mapred-site.xml
echo "        <name>mapred.maxthreads.generate.mapoutput</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>2</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "    <property>" >> ${hadoop_conf}/mapred-site.xml
echo "        <name>mapreduce.tasktracker.reserved.physicalmemory.mb.low</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>0.95</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "    <property>" >> ${hadoop_conf}/mapred-site.xml
echo "        <name>mapred.maxthreads.partition.closer</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>2</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "    <property>" >> ${hadoop_conf}/mapred-site.xml
echo "        <name>mapreduce.map.sort.spill.percent</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>0.99</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "    <property>" >> ${hadoop_conf}/mapred-site.xml
echo "        <name>mapreduce.reduce.merge.inmem.threshold</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>0</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "    <property>" >> ${hadoop_conf}/mapred-site.xml
echo "        <name>mapreduce.job.reduce.slowstart.completedmaps</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>1</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "    <property>" >> ${hadoop_conf}/mapred-site.xml
echo "        <name>mapreduce.map.speculative</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>false</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "    <property>" >> ${hadoop_conf}/mapred-site.xml
echo "        <name>mapreduce.reduce.speculative</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>false</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "    <property>" >> ${hadoop_conf}/mapred-site.xml
echo "        <name>mapreduce.map.output.compress</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>false</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "    <property>" >> ${hadoop_conf}/mapred-site.xml
echo "        <name>mapreduce.job.reduces</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>160</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "    <property>" >> ${hadoop_conf}/mapred-site.xml
echo "        <name>mapreduce.task.io.sort.mb</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>512</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "    <property>" >> ${hadoop_conf}/mapred-site.xml
echo "        <name>mapreduce.task.io.sort.factor</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>400</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "    <property>" >> ${hadoop_conf}/mapred-site.xml
echo "        <name>mapreduce.reduce.shuffle.parallelcopies</name>" >> ${hadoop_conf}/mapred-site.xml
echo "        <value>50</value>" >> ${hadoop_conf}/mapred-site.xml
echo "    </property>" >> ${hadoop_conf}/mapred-site.xml
echo "</configuration>" >> ${hadoop_conf}/mapred-site.xml

# for MapReduce JobHistory Server
jh_config="/tmp/jobhistory"
mkdir -p ${jh_config}
LogMsg "Configuring JobHistory Server mapred-site.xml"
cp ${hadoop_conf}/mapred-site.xml.template ${jh_config}/mapred-site.xml
sed -i "s~</configuration>~    <property>~g" ${jh_config}/mapred-site.xml
echo "        <name>mapreduce.jobhistory.address</name>" >> ${jh_config}/mapred-site.xml
echo "        <value>127.0.0.1:10020</value>" >> ${jh_config}/mapred-site.xml
echo "    </property>" >> ${jh_config}/mapred-site.xml
echo "    <property>" >> ${jh_config}/mapred-site.xml
echo "        <name>mapreduce.jobhistory.webapp.address</name>" >> ${jh_config}/mapred-site.xml
echo "        <value>127.0.0.1:19888</value>" >> ${jh_config}/mapred-site.xml
echo "    </property>" >> ${jh_config}/mapred-site.xml
echo "    <property>" >> ${jh_config}/mapred-site.xml
echo "        <name>mapreduce.jobhistory.intermediate-done-dir</name>" >> ${jh_config}/mapred-site.xml
echo "        <value>${history_tmp}</value>" >> ${jh_config}/mapred-site.xml
echo "    </property>" >> ${jh_config}/mapred-site.xml
echo "    <property>" >> ${jh_config}/mapred-site.xml
echo "        <name>mapreduce.jobhistory.done-dir</name>" >> ${jh_config}/mapred-site.xml
echo "        <value>${history_done}</value>" >> ${jh_config}/mapred-site.xml
echo "    </property>" >> ${jh_config}/mapred-site.xml
echo "</configuration>" >> ${jh_config}/mapred-site.xml

echo -e ${master_ip} > ${hadoop_conf}/masters
> ${hadoop_conf}/slaves

echo -e "${master_ip} master" | sudo tee --append /etc/hosts
echo -e > /home/${USER}/.ssh/known_hosts
ssh-keyscan localhost,0.0.0.0,master >> ~/.ssh/known_hosts

for ((i = 0; i < ${#SLAVES[@]}; ++i))
do
    LogMsg "Performing cleanup on: ${SLAVES[$i]}"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "sudo pkill -f java"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "sudo rm -rf /tmp/hadoop*"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "sudo rm -rf /tmp/hsperfdata*"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "sudo umount -l ${hadoop_store}"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "sudo rm -rf ${hadoop_store}"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "sudo rm -rf ${hadoop_store}"

    LogMsg "Configuring hadoop on: ${SLAVES[$i]}"
    if [[ ${distro} == *"Ubuntu"* ]]
    then
        ssh -T -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "sudo apt update"
        ssh -T -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "sudo apt install -y maven libssl-dev rsync build-essential pkgconf cmake protobuf-compiler libprotobuf-dev default-jdk openjdk-8-jdk-headless bc"
        if [ $? != 0 ]; then
            LogMsg "ERROR: Dependencies install failed."
        fi
        ssh -T -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "sudo sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' dist-upgrade" >> ${LOG_FILE}
        ssh -T -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "sudo apt upgrade -y procps" >> ${LOG_FILE}
    elif [[ ${distro} == *"Amazon"* ]]
    then
        ssh -T -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "sudo yum clean dbcache"
        ssh -T -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "sudo yum -y install sysstat zip java java-devel automake autoconf rsync cmake gcc libtool* protobuf-compiler bc"
        if [ $? != 0 ]; then
            LogMsg "ERROR: Dependencies install failed."
        fi
    else
        LogMsg "Unsupported distribution: ${distro}."
    fi
    scp -o StrictHostKeyChecking=no /tmp/${hadoop_version}.tar.gz ${USER}@${SLAVES[$i]}:/tmp >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "cd /tmp;tar -xzf ${hadoop_version}.tar.gz" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "echo -e '${hadoop_exports}' >> ~/.bashrc" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "echo -e > /home/${USER}/.ssh/known_hosts" >> ${LOG_FILE}
    LogMsg "Setting up hadoop store ${hadoop_store} on ${SLAVES[$i]}"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "sudo mkfs.ext4 ${STORE}" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "sudo mkdir -p ${hadoop_store}" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "sudo mount ${STORE} ${hadoop_store}" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "sudo chown ${USER} ${hadoop_store}" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "mkdir -p ${hadoop_tmp}" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "mkdir -p ${hadoop_datanode}" >> ${LOG_FILE}
    LogMsg "Copying default hadoop-env.sh and core-site.xml on: ${SLAVES[$i]}"
    scp -o StrictHostKeyChecking=no ${hadoop_conf}/hadoop-env.sh ${USER}@${SLAVES[$i]}:${hadoop_conf}/
    scp -o StrictHostKeyChecking=no ${hadoop_conf}/core-site.xml ${USER}@${SLAVES[$i]}:${hadoop_conf}/
    ssh -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "echo -e ${master_ip} > ${hadoop_conf}/masters"
    echo -e ${SLAVES[$i]} >> ${hadoop_conf}/slaves
    LogMsg "Configuring hostnames and keys on: ${SLAVES[$i]}"
    ssh -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "echo -e '${master_ip} master' | sudo tee --append /etc/hosts"
    ssh -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "ssh-keyscan master > ~/.ssh/known_hosts"
    for ((j = 0; j < ${#SLAVES[@]}; ++j))
    do
        ssh -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "echo -e "${SLAVES[$j]} slave${j}" | sudo tee --append /etc/hosts"
        ssh -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "ssh-keyscan slave${j} > ~/.ssh/known_hosts"
    done
    echo -e "${SLAVES[$i]} slave${i}" | sudo tee --append /etc/hosts
    ssh-keyscan slave${i} >> ~/.ssh/known_hosts
    # Moving the resource manager to a separate server can be done bellow (check doc for required configs)
    if [ ${i} -eq 1 ]
    then
        LogMsg "Configuring DataNode, NodeManager and JobHistory Server on: ${SLAVES[$i]}"
        scp -o StrictHostKeyChecking=no ${datanode_config}/hdfs-site.xml ${USER}@${SLAVES[$i]}:${hadoop_conf}/
        scp -o StrictHostKeyChecking=no ${datanode_config}/yarn-site.xml ${USER}@${SLAVES[$i]}:${hadoop_conf}/
        scp -o StrictHostKeyChecking=no ${jh_config}/mapred-site.xml ${USER}@${SLAVES[$i]}:${hadoop_conf}/
        ssh -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "mkdir -p ${history_tmp}" >> ${LOG_FILE}
        ssh -o StrictHostKeyChecking=no ${USER}@${SLAVES[$i]} "mkdir -p ${history_done}" >> ${LOG_FILE}
    else
        LogMsg "Configuring slave with DataNode and NodeManager on: ${SLAVES[$i]}"
        scp -o StrictHostKeyChecking=no ${datanode_config}/hdfs-site.xml ${USER}@${SLAVES[$i]}:${hadoop_conf}/
        scp -o StrictHostKeyChecking=no ${datanode_config}/yarn-site.xml ${USER}@${SLAVES[$i]}:${hadoop_conf}/
    fi
done

LogMsg "Info : Formatting HDFS"
/tmp/${hadoop_version}/bin/hdfs namenode -format
sleep 10
LogMsg "Info : Starting DFS"
if [[ ${distro} == *"Ubuntu"* ]]
then
    /tmp/${hadoop_version}/sbin/start-dfs.sh >> ${LOG_FILE}
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo sed -i 1,2d /etc/hosts
    sudo sed -i '1 i\127.0.0.1   localhost' /etc/hosts
    echo -ne 'yes\nyes\n' | /tmp/${hadoop_version}/sbin/start-dfs.sh >> ${LOG_FILE}
fi
sleep 10
LogMsg "Info : Starting Yarn"
/tmp/${hadoop_version}/sbin/start-yarn.sh >> ${LOG_FILE}
sleep 10
LogMsg "Info : Starting jobhistory"
ssh -o StrictHostKeyChecking=no ${USER}@${SLAVES[1]} "/tmp/${hadoop_version}/sbin/mr-jobhistory-daemon.sh start historyserver" >> ${LOG_FILE}
sleep 10
LogMsg "Info : Run TeraGen to create test data"
/tmp/${hadoop_version}/bin/hadoop jar /tmp/${hadoop_version}/share/hadoop/mapreduce/hadoop-*examples*.jar teragen ${teragen_records} ${hadoop_store}/genout > /tmp/terasort/teragen.log 2>&1
LogMsg "Info : Running TeraSort to sort test data"
sleep 10
/tmp/${hadoop_version}/bin/hadoop jar /tmp/${hadoop_version}/share/hadoop/mapreduce/hadoop-*examples*.jar terasort ${hadoop_store}/genout ${hadoop_store}/sortout > /tmp/terasort/terasort.log 2>&1

LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"
LogMsg "Hadoop Version : ${hadoop_version}"

cd /tmp
zip -r terasort.zip . -i terasort/* >> ${LOG_FILE}
zip -r terasort.zip . -i summary.log >> ${LOG_FILE}
