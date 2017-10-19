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
    echo -e "\nUsage:\n$0 sql_pass disk"
    exit 1
fi

SQL_PASS="$1"
DISK="$2"
MEM_LIMIT=103424

if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi

db_path="/mssql/db"
if [[ ${DISK} == *"xvd"* || ${DISK} == *"sd"* ]]
then
    sudo mkdir -p ${db_path}
    sudo mkfs.ext4 ${DISK}
    sudo mount ${DISK} ${db_path}
elif [[ ${DISK} == *"md"* ]]
then
    sudo mkdir -p ${db_path}
else
    LogMsg "Failed to identify disk type for ${DISK}."
    exit 70
fi

escaped_path=$(echo "${db_path}" | sed 's/\//\\\//g')
distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt install -y zip
    sudo curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
    repoargs="$(curl https://packages.microsoft.com/config/ubuntu/16.04/mssql-server-2017.list)"
    sudo add-apt-repository "${repoargs}"
    repoargs="$(curl https://packages.microsoft.com/config/ubuntu/16.04/prod.list)"
    sudo add-apt-repository "${repoargs}"
    sudo apt update
    sudo apt install -y mssql-server >> ${LOG_FILE}
    sudo MSSQL_SA_PASSWORD=${SQL_PASS} MSSQL_PID='evaluation' /opt/mssql/bin/mssql-conf -n setup accept-eula >> ${LOG_FILE}
    sudo ACCEPT_EULA=Y apt install -y mssql-tools unixodbc-dev >> ${LOG_FILE}
    sudo apt install -y mssql-server-agent >> ${LOG_FILE}
    sudo ufw allow 1433/tcp
    sudo ufw reload
else
    LogMsg "Unsupported distribution: ${distro}."
fi

sudo chown mssql ${db_path}
sudo chgrp mssql ${db_path}
sudo /opt/mssql/bin/mssql-conf set filelocation.defaultbackupdir ${db_path} >> ${LOG_FILE}
sudo /opt/mssql/bin/mssql-conf set filelocation.defaultdatadir ${db_path} >> ${LOG_FILE}
sudo /opt/mssql/bin/mssql-conf set filelocation.defaultdumpdir ${db_path} >> ${LOG_FILE}
sudo /opt/mssql/bin/mssql-conf set filelocation.defaultlogdir ${db_path} >> ${LOG_FILE}
sudo /opt/mssql/bin/mssql-conf set memory.memorylimitmb ${MEM_LIMIT} >> ${LOG_FILE}
sudo systemctl restart mssql-server >> ${LOG_FILE}
systemctl status mssql-server >> ${LOG_FILE}

sql_version=`/opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P ${SQL_PASS} -Q 'SELECT @@VERSION'`
LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"
LogMsg "SQLServer Version : ${sql_version}"

cd /tmp
zip -r sqlserver.zip . -i summary.log >> ${LOG_FILE}