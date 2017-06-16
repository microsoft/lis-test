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
    echo -e "\nUsage:\n$0 server user ebs_vol"
    exit 1
fi

SERVER="$1"
USER="$2"
DISK="$3"
TEST_THREADS=(1 2 4 8 16 32 64 128 256)
client_ip=`ip route get ${SERVER} | awk '{print $NF; exit}'`

if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi

if [[ ${DISK} == *"xvd"* || ${DISK} == *"sd"* ]]
then
    db_path="/maria/db"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mkdir -p ${db_path}"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mkfs.ext4 ${DISK}" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mount ${DISK} ${db_path}" >> ${LOG_FILE}
elif [[ ${DISK} == *"md"* ]]
then
    db_path="/raid/maria/db"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mkdir -p ${db_path}"
else
    LogMsg "Failed to identify disk type for ${DISK}."
    exit 70
fi

escaped_path=$(echo "${db_path}" | sed 's/\//\\\//g')
distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt-get update && sudo apt-get upgrade -y >> ${LOG_FILE}
    sudo apt-get -y install libaio1 sysstat zip sysbench mysql-client* >> ${LOG_FILE}

    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt-get update && sudo apt-get upgrade -y" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt-get -y install libaio1 sysstat zip mariadb-server" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo service mysql stop" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/datadir/c\datadir = ${escaped_path}' /etc/mysql/mariadb.conf.d/50-server.cnf" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/bind-address/c\bind-address = 0\.0\.0\.0' /etc/mysql/mariadb.conf.d/50-server.cnf" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/max_connections/c\max_connections = 1024' /etc/mysql/mariadb.conf.d/50-server.cnf" >> ${LOG_FILE}
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum clean dbcache >> ${LOG_FILE}
    sudo yum -y install sysstat zip sysstat zip gcc automake openssl-devel libtool wget >> ${LOG_FILE}
    maria_repo_server="[mariadb-main]\
                  \nname = MariaDB Server\
                  \nbaseurl = https://downloads.mariadb.com/MariaDB/mariadb-10.0/yum/centos/6/x86_64\
                  \ngpgcheck = 0\
                  \nenabled = 1"
    echo -e ${maria_repo_server} | sudo tee /etc/yum.repos.d/mariadb.repo >> ${LOG_FILE}
    sudo yum -y install MariaDB-client MariaDB-devel >> ${LOG_FILE}
    cd /tmp
    wget http://downloads.mysql.com/source/sysbench-0.4.12.5.tar.gz
    gunzip -c sysbench-0.4.12.5.tar.gz |tar zx
    cd /tmp/sysbench-0.4.12.5; ./configure; make; sudo make install >> ${LOG_FILE}
    sudo cp /usr/local/bin/sysbench /usr/bin/sysbench

    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "echo -e '${maria_repo_server}' | sudo tee /etc/yum.repos.d/mariadb.repo" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo yum -y install sysstat zip openssl-devel MariaDB-server" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo service mysql stop" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "echo datadir = ${db_path} | sudo tee --append /etc/my.cnf.d/server.cnf" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "echo bind-address = 0.0.0.0 | sudo tee --append /etc/my.cnf.d/server.cnf" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "echo max_connections = 1024 | sudo tee --append /etc/my.cnf.d/server.cnf" >> ${LOG_FILE}
else
    LogMsg "Unsupported distribution: ${distro}."
fi

cd /tmp
mkdir -p /tmp/mariadb
ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "mkdir -p /tmp/mariadb"

ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo cp -rf /var/lib/mysql/* ${db_path}" >> ${LOG_FILE}
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo chmod 700 -R ${db_path}"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo chown -R mysql:adm ${db_path}"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo service mysql start" >> ${LOG_FILE}
sleep 30

ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mysql -e \"GRANT ALL PRIVILEGES ON *.* TO '${USER}'@'${client_ip}' IDENTIFIED BY 'lisapassword' WITH GRANT OPTION;\"" >> ${LOG_FILE}
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mysql -e \"DROP DATABASE sbtest;\"" >> ${LOG_FILE}
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mysql -e \"CREATE DATABASE sbtest;\"" >> ${LOG_FILE}
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mysql -e \"SET GLOBAL max_connections = 5000;\"" >> ${LOG_FILE}
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mysql -e \"FLUSH PRIVILEGES;\"" >> ${LOG_FILE}

sudo sysbench --test=oltp --mysql-host=${SERVER} --mysql-user=${USER} --mysql-password=lisapassword --mysql-db=sbtest --oltp-table-size=100000000 prepare >> ${LOG_FILE}

function run_mariadb ()
{
    threads=$1

    LogMsg "======================================"
    LogMsg "Running mariadb test with current threads: ${threads}"
    LogMsg "======================================"

    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "sar -n DEV 1 900   2>&1 > /tmp/mariadb/${threads}.sar.netio.log"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "iostat -x -d 1 900 2>&1 > /tmp/mariadb/${threads}.iostat.diskio.log"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "vmstat 1 900       2>&1 > /tmp/mariadb/${threads}.vmstat.memory.cpu.log"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "mpstat -P ALL 1 900 2>&1 > /tmp/mariadb/${threads}.mpstat.cpu.log"
    sar -n DEV 1 900   2>&1 > /tmp/mariadb/${threads}.sar.netio.log &
    iostat -x -d 1 900 2>&1 > /tmp/mariadb/${threads}.iostat.netio.log &
    vmstat 1 900       2>&1 > /tmp/mariadb/${threads}.vmstat.netio.log &
    mpstat -P ALL 1 900 2>&1 > /tmp/mariadb/${threads}.mpstat.cpu.log &

    sudo sysbench --test=oltp --mysql-host=${SERVER} --mysql-user=${USER} --mysql-password=lisapassword --mysql-db=sbtest --max-time=300 --oltp-test-mode=complex --mysql-table-engine=innodb --oltp-read-only=off --max-requests=100000000 --num-threads=${threads} run > /tmp/mariadb/${threads}.sysbench.mariadb.run.log

    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f sar"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f iostat"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f vmstat"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f mpstat"
    sudo pkill -f sar
    sudo pkill -f iostat
    sudo pkill -f vmstat
    sudo pkill -f mpstat

    LogMsg "sleep 60 seconds"
    sleep 60
}

for threads in "${TEST_THREADS[@]}"
do
    run_mariadb ${threads}
done

sudo sysbench --test=oltp --mysql-host=${SERVER} --mysql-user=${USER} --mysql-password=lisapassword --mysql-db=sbtest cleanup >> ${LOG_FILE}

LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"

cd /tmp
zip -r mariadb.zip . -i mariadb/* >> ${LOG_FILE}
zip -r mariadb.zip . -i summary.log >> ${LOG_FILE}
