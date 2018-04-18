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
    echo -e "\nUsage:\n$0 server user disk"
    exit 1
fi

SERVER="$1"
USER="$2"
DISK="$3"
POSTGRES_VERSION="9.6"
DB_PASS="someTempP@22"
DURATION=600

if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi


if [[ ${DISK} == *"xvd"* || ${DISK} == *"sd"* ]]
then
    db_path="/postgres/db"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mkdir -p ${db_path}"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mkfs.ext4 ${DISK}" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mount ${DISK} ${db_path}" >> ${LOG_FILE}
elif [[ ${DISK} == *"md"* ]]
then
    db_path="/raid/postgres/db"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mkdir -p ${db_path}"
else
    LogMsg "Failed to identify disk type for ${DISK}."
    exit 70
fi

escaped_path=$(echo "${db_path}" | sed 's/\//\\\//g')
client_ip=`ip route get ${SERVER} | awk '{print $NF; exit}'`
cd /tmp
mkdir -p /tmp/postgresql
ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "mkdir -p /tmp/postgresql"

distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    echo -e "deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main" | sudo tee --append /etc/apt/sources.list
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
    sudo apt-get update 
    sudo apt -y install bc sysstat zip postgresql-client-${POSTGRES_VERSION} postgresql-contrib-${POSTGRES_VERSION} >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt -y install sysstat zip"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "echo -e 'deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main' | sudo tee --append /etc/apt/sources.list"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt update; sudo apt install -y postgresql-${POSTGRES_VERSION}" >> ${LOG_FILE}
    db_conf="/etc/postgresql/${POSTGRES_VERSION}/main/postgresql.conf"
    db_service="postgresql"
    db_user="postgres"
    path_var="data_directory"
    db_utils="/usr/lib/postgresql/${POSTGRES_VERSION}/bin"
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum clean dbcache
    sudo yum install -y https://download.postgresql.org/pub/repos/yum/${POSTGRES_VERSION}/redhat/rhel-6-x86_64/pgdg-ami201503-96-9.6-2.noarch.rpm
    sudo yum -y install bc sysstat zip postgresql96 postgresql96-contrib >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo yum clean dbcache"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo yum install -y https://download.postgresql.org/pub/repos/yum/${POSTGRES_VERSION}/redhat/rhel-6-x86_64/pgdg-ami201503-96-9.6-2.noarch.rpm"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo yum -y install sysstat zip postgresql96-server postgresql96-contrib" >> ${LOG_FILE}

    db_conf="/postgres/db/data/postgresql.conf"
    db_service="postgresql96"
    db_user="postgres"
    path_var="PGDATA"
    db_utils="/usr/lib64/pgsql96/bin"
else
    LogMsg "Unsupported distribution: ${distro}."
fi


ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo service ${db_service} stop" >> ${LOG_FILE}
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo chown -R ${db_user}:${db_user} ${db_path}"

newDBUser='testuser'

if [[ ${distro} == *"Ubuntu"* ]]
then
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mv /var/lib/postgresql/${POSTGRES_VERSION}/main ${db_path}"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/${path_var}/c\\${path_var} = \x27${escaped_path}/main\x27' ${db_conf}"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "echo -e 'host    all    ${USER}    ${client_ip}/32    trust' | sudo tee --append /etc/postgresql/${POSTGRES_VERSION}/main/pg_hba.conf"
elif [[ ${distro} == *"Amazon"* ]]
then
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo mv /var/lib/pgsql96/data ${db_path}"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i 's/^${path_var}.*/${path_var}=${escaped_path}\/data/g' /etc/init.d/postgresql96"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo service ${db_service} initdb -D ${db_path}"
    client_ip=$(hostname -I)
    client_ip=`echo ${client_ip//[[:blank:]]/}`
    LogMsg  ${client_ip}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "echo -e 'host    all    ${newDBUser}    ${client_ip}/32    trust' | sudo tee --append ${escaped_path}/data/pg_hba.conf"
fi

#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/stats_temp_directory/c\stats_temp_directory = \x27${escaped_path}\x27' ${db_conf}"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/listen_addresses/c\listen_addresses = \x27*\x27' ${db_conf}"

# PostgreSQL tuning
shared_buffers=$(printf '%.*f\n' 0 $(free -m | grep Mem | awk '{print $2 * 0.25}'))MB
cache_size=$(printf '%.*f\n' 0 $(free -m | grep Mem | awk '{print $2 * 0.75}'))MB
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/shared_buffers/c\shared_buffers = ${shared_buffers}' ${db_conf}"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/work_mem/c\work_mem = 32MB' ${db_conf}"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/effective_cache_size/c\effective_cache_size = ${cache_size}' ${db_conf}"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/wal_buffers/c\wal_buffers  = 64MB' ${db_conf}"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/maintenance_work_mem/c\maintenance_work_mem  = 512MB' ${db_conf}"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/temp_buffers/c\temp_buffers = 32MB' ${db_conf}"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/random_page_cost/c\random_page_cost = 1.0' ${db_conf}"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/effective_io_concurrency/c\effective_io_concurrency = 4' ${db_conf}"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/max_wal_size/c\max_wal_size = 300GB' ${db_conf}"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/min_wal_size/c\min_wal_size = 100GB' ${db_conf}"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo sed -i '/checkpoint_timeout/c\checkpoint_timeout = 50min' ${db_conf}"


ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo service ${db_service} start" >> ${LOG_FILE}

# Wait for postgres server to create its artifacts at the new location
sleep 30
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/createuser ${newDBUser}"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} psql -c \"alter user ${newDBUser} with encrypted password '${DB_PASS}';\""
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/createdb -O ${newDBUser} test_db"

if [[ ${distro} == *"Ubuntu"* ]]
then
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} pg_lsclusters" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} pg_conftool show all" >> ${LOG_FILE}
fi

#disk required scale / 75 = 1GB database
scale=$((1 * 75))
if [[ ${distro} == *"Ubuntu"* ]]
then
    buffer_scale=$(printf '%.*f\n' 0 $(echo "$(free -h | grep Mem | awk '{print $2 * 0.1}') * ${scale}" | bc))
    conn_scale=$(printf '%.*f\n' 0 $(echo "$(free -h | grep Mem | awk '{print $2 * 0.4}') * ${scale}" | bc))
    cache_scale=$(printf '%.*f\n' 0 $(echo "$(free -h | grep Mem | awk '{print $2 * 0.9}') * ${scale}" | bc))
    disk_scale=$(printf '%.*f\n' 0 $(echo "$(free -h | grep Mem | awk '{print $2 * 4}') * ${scale}" | bc))
elif [[ ${distro} == *"Amazon"* ]]
then
    buffer_scale=$(printf '%.*f\n' 0 $(echo "$(free -o -g | grep Mem | awk '{print $2 * 0.1}') * ${scale}" | bc))
    conn_scale=$(printf '%.*f\n' 0 $(echo "$(free -o -g | grep Mem | awk '{print $2 * 0.4}') * ${scale}" | bc))
    cache_scale=$(printf '%.*f\n' 0 $(echo "$(free -o -g | grep Mem | awk '{print $2 * 0.9}') * ${scale}" | bc))
    disk_scale=$(printf '%.*f\n' 0 $(echo "$(free -o -g | grep Mem | awk '{print $2 * 4}') * ${scale}" | bc))
fi
# For each core available on the database server, it is suggested to use 1 thread and 2 clients
threads=$(grep -c ^processor /proc/cpuinfo)
clients=$((2 * $threads))

# TODO review the rest of the tests cases
# Memory vs. Disk Performance
LogMsg "Running Memory vs. Disk Performance"
LogMsg "Running In Buffer Test"
pgbench --host=${SERVER} --username=${newDBUser} -i -s ${buffer_scale} test_db
pgbench --host=${SERVER} --username=${newDBUser} -c ${clients} -j ${threads} -T ${DURATION} test_db > /tmp/postgresql/mem_disk.in_buffer.log
sleep 20
LogMsg "Running Mostly Cache Test"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/dropdb test_db"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/createdb -O ${newDBUser} test_db"
sleep 10
pgbench --host=${SERVER} --username=${newDBUser} -i -s ${cache_scale} test_db
pgbench --host=${SERVER} --username=${newDBUser} -c ${clients} -j ${threads} -T ${DURATION} test_db > /tmp/postgresql/mem_disk.mostly_cache.log
sleep 20
#LogMsg "Running On-Disk Test"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/dropdb test_db"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/createdb -O ${USER} test_db"
#pgbench --host=${SERVER} --username=${USER} -i -s ${disk_scale} test_db
#pgbench --host=${SERVER} --username=${USER} -c ${clients} -j ${threads} -T ${DURATION} test_db > /tmp/postgresql/mem_disk.disk.log
#sleep 20

#Read vs. Write Performance
LogMsg "Running Read vs. Write Performance"
#LogMsg "Running Read-Write Test - same with Mostly Cache Test mem_disk.cache"
#LogMsg "Running Read-Only Test"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/dropdb test_db"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/createdb -O ${USER} test_db"
#sleep 10
#pgbench --host=${SERVER} --username=${USER} -i -s ${cache_scale} test_db
#pgbench --host=${SERVER} --username=${USER} -c ${clients} -j ${threads} -T ${DURATION} -S test_db > /tmp/postgresql/rw_perf.read_only.log
#sleep 20
LogMsg "Running Simple Write Test"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/dropdb test_db"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/createdb -O ${newDBUser} test_db"
sleep 10
pgbench --host=${SERVER} --username=${newDBUser} -i -s ${cache_scale} test_db
pgbench --host=${SERVER} --username=${newDBUser} -c ${clients} -j ${threads} -T ${DURATION} -N test_db > /tmp/postgresql/rw_perf.simple_write.log
sleep 20

#Connections and Contention
LogMsg "Running Connections and Contention"
LogMsg "Running Single-Threaded"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/dropdb test_db"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/createdb -O ${newDBUser} test_db"
sleep 10
pgbench --host=${SERVER} --username=${newDBUser} -i -s ${conn_scale} test_db
pgbench --host=${SERVER} --username=${newDBUser} -c 1 -T ${DURATION} test_db > /tmp/postgresql/conn.single_connection.log
sleep 20
LogMsg "Running Normal Load"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/dropdb test_db"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/createdb -O ${newDBUser} test_db"
sleep 10
pgbench --host=${SERVER} --username=${newDBUser} -i -s ${conn_scale} test_db
pgbench --host=${SERVER} --username=${newDBUser} -c $((${clients} * 2)) -j ${threads} -T ${DURATION} test_db > /tmp/postgresql/conn.normal_load.log
sleep 20
#LogMsg "Running Heavy Contention"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/dropdb test_db"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/createdb -O ${USER} test_db"
#sleep 10
#pgbench --host=${SERVER} --username=${USER} -i -s ${conn_scale} test_db
#pgbench --host=${SERVER} --username=${USER} -c $((${clients} * 21)) -j $((${threads} * 2)) -T ${DURATION} test_db > /tmp/postgresql/conn.h_cont.log
#sleep 20
#LogMsg "Running Heavy Connections without Contention"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/dropdb test_db"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/createdb -O ${USER} test_db"
#sleep 10
#pgbench --host=${SERVER} --username=${USER} -i -s ${conn_scale} test_db
#pgbench --host=${SERVER} --username=${USER} -c $((${clients} * 21)) -j $((${threads} * 2)) -T ${DURATION} -N test_db > /tmp/postgresql/conn.h_conn.log
#sleep 20
#LogMsg "Running Heavy Re-connection (simulates no connection pooling)"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/dropdb test_db"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/createdb -O ${USER} test_db"
#sleep 10
#pgbench --host=${SERVER} --username=${USER} -i -s ${conn_scale} test_db
#pgbench --host=${SERVER} --username=${USER} -c $((${clients} * 2)) -j ${threads} -T ${DURATION} -C test_db > /tmp/postgresql/conn.h_reconn.log
#sleep 20

#Prepared vs. Ah-hoc Queries
#LogMsg "Running Prepared vs. Ah-hoc Queries"
#LogMsg "Running Unprepared, Read-Write - same with Mostly Cache Test mem_disk.cache"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/dropdb test_db"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/createdb -O ${USER} test_db"
#sleep 10
#pgbench --host=${SERVER} --username=${USER} -i -s ${cache_scale} test_db
#pgbench --host=${SERVER} --username=${USER} -c ${clients} -j ${threads} -T ${DURATION} test_db > /tmp/postgresql/queries.rw_unprepared.log
#sleep 20
#LogMsg "Running Prepared, Read-Write"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/dropdb test_db"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/createdb -O ${USER} test_db"
#sleep 10
#pgbench --host=${SERVER} --username=${USER} -i -s ${cache_scale} test_db
#pgbench --host=${SERVER} --username=${USER} -c ${clients} -j ${threads} -T ${DURATION} -M prepared test_db > /tmp/postgresql/queries.rw_prepared.log
#sleep 20
#LogMsg "Running Unprepared, Read-Only"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/dropdb test_db"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/createdb -O ${USER} test_db"
#sleep 10
#pgbench --host=${SERVER} --username=${USER} -i -s ${cache_scale} test_db
#pgbench --host=${SERVER} --username=${USER} -c ${clients} -j ${threads} -T ${DURATION} -S test_db > /tmp/postgresql/queries.ro_unprepared.log
#sleep 20
#LogMsg "Running Prepared, Read-Only"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/dropdb test_db"
#ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} ${db_utils}/createdb -O ${USER} test_db"
#sleep 10
#pgbench --host=${SERVER} --username=${USER} -i -s ${cache_scale} test_db
#pgbench --host=${SERVER} --username=${USER} -c ${clients} -j ${threads} -T ${DURATION} -M prepared -S test_db > /tmp/postgresql/queries.ro_prepared.log
#sleep 20

LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"
LogMsg "Pgbench Version : $(pgbench -V)"
psql_ver=$(ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo -u ${db_user} psql -c \"select version();\"")
LogMsg "PostgreSQL Version : ${psql_ver}"

cd /tmp
zip -r postgresql.zip . -i postgresql/* >> ${LOG_FILE}
zip -r postgresql.zip . -i summary.log >> ${LOG_FILE}
