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
EBS_VOL="$3"
TEST_THREADS=(1 2 4 8 16 32 64 128 256)
client_ip=`ip route get ${SERVER} | awk '{print $NF; exit}'`

if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi

sudo apt-get update >> ${LOG_FILE}
sudo apt-get -y install libaio1 sysstat zip sysbench mysql-client* >> ${LOG_FILE}

mkdir -p /tmp/mariadb
if [[ ${EBS_VOL} == *"xvd"* ]]
then
    db_path="/maria/db"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mkdir -p ${db_path}"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mkfs.ext4 ${EBS_VOL}" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mount ${EBS_VOL} ${db_path}" >> ${LOG_FILE}
elif [[ ${EBS_VOL} == *"md"* ]]
then
    db_path="/raid/maria/db"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mkdir -p ${db_path}"
else
    LogMsg "Failed to identify disk type for ${EBS_VOL}."
    exit 70
fi

ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt-get update" >> ${LOG_FILE}
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt-get -y install libaio1 sysstat zip mariadb-server" >> ${LOG_FILE}
ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "mkdir -p /tmp/mariadb"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo service mysql stop" >> ${LOG_FILE}

escaped_path=$(echo "${db_path}" | sed 's/\//\\\//g')
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/datadir/c\datadir = ${escaped_path}' /etc/mysql/mariadb.conf.d/50-server.cnf" >> ${LOG_FILE}
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/bind-address/c\bind-address = 0\.0\.0\.0' /etc/mysql/mariadb.conf.d/50-server.cnf" >> ${LOG_FILE}
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/max_connections/c\max_connections = 1024' /etc/mysql/mariadb.conf.d/50-server.cnf" >> ${LOG_FILE}

ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo cp -rf /var/lib/mysql/* ${db_path}" >> ${LOG_FILE}
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo chmod 700 -R ${db_path}"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo chown -R mysql:adm ${db_path}"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo service mysql start" >> ${LOG_FILE}
sleep 30
mysql_pid=$(ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} pidof mysqld)

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
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "pidstat -h -r -u -v -p ${mysql_pid} 1 900 2>&1 > /tmp/mariadb/${threads}.pidstat.cpu.log"
    sar -n DEV 1 900   2>&1 > /tmp/mariadb/${threads}.sar.netio.log &
    iostat -x -d 1 900 2>&1 > /tmp/mariadb/${threads}.iostat.netio.log &
    vmstat 1 900       2>&1 > /tmp/mariadb/${threads}.vmstat.netio.log &
    mpstat -P ALL 1 900 2>&1 > /tmp/mariadb/${threads}.mpstat.cpu.log &
    ( sleep 5 ; pidstat -h -r -u -v -p $(pidof sysbench) 1 900 2>&1 > /tmp/mariadb/${threads}.pidstat.cpu.log ) &

    sudo sysbench --test=oltp --mysql-host=${SERVER} --mysql-user=${USER} --mysql-password=lisapassword --mysql-db=sbtest --max-time=300 --oltp-test-mode=complex --mysql-table-engine=innodb --oltp-read-only=off --max-requests=100000000 --num-threads=${threads} run > /tmp/mariadb/${threads}.sysbench.mariadb.run.log

    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f sar"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f iostat"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f vmstat"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f mpstat"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f pidstat"
    sudo pkill -f sar
    sudo pkill -f iostat
    sudo pkill -f vmstat
    sudo pkill -f mpstat
    sudo pkill -f pidstat

    LogMsg "sleep 60 seconds"
    sleep 60
}

for threads in "${TEST_THREADS[@]}"
do
    run_mariadb ${threads}
done

sudo sysbench --test=oltp --mysql-host=${SERVER} --mysql-user=${USER} --mysql-password=lisapassword --mysql-db=sbtest cleanup >> ${LOG_FILE}

LogMsg "Kernel Version : `uname -r`"

cd /tmp
zip -r mariadb.zip . -i mariadb/* >> ${LOG_FILE}
zip -r mariadb.zip . -i summary.log >> ${LOG_FILE}
