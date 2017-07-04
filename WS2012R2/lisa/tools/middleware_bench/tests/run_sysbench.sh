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
########################################################################
#
# Description:
#       This script installs and runs Sysbench tests on a Ubuntu machine
#
#       Steps:
#       1. Installs dependencies
#       2. Compiles and installs sysbench
#       3. Runs sysbench
#       4. Prepares results
#
########################################################################
LOG_FILE=/tmp/summary.log
function LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1} >> ${LOG_FILE}
}

if [ $# -lt 1 ]; then
    echo -e "\nUsage:\n$0 device"
    exit 1
fi

DISK="$1"
MODES=(seqwr seqrewr seqrd rndrd rndwr rndrw)
THREADS=(1 2 4 8 16 32 64)
IOS=(4 8 32)
EXTRA="--file-total-size=84G --max-requests=0 --max-time=300 --file-extra-flags=dsync --file-fsync-freq=0"

if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi

distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -yq >> ${LOG_FILE}
    sudo apt-get -y install libaio1 sysstat zip sysbench >> ${LOG_FILE}
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum clean dbcache>> ${LOG_FILE}
    sudo yum -y install sysstat zip sysstat zip gcc libtool wget >> ${LOG_FILE}
    cd /tmp
    wget http://downloads.mysql.com/source/sysbench-0.4.12.5.tar.gz >> ${LOG_FILE}
    gunzip -c sysbench-0.4.12.5.tar.gz |tar zx >> ${LOG_FILE}
    cd /tmp/sysbench-0.4.12.5; ./configure --without-mysql; make; sudo make install >> ${LOG_FILE}
    sudo cp /usr/local/bin/sysbench /usr/bin/sysbench
    cd /tmp
else
    LogMsg "Unsupported distribution: ${distro}."
fi

function fileio ()
{
    LogMsg " Testing sysbench fileio mode=$1 ios=$2"K" threads=$3."
    iostat -x -d 1 900 2>&1 > /tmp/sysbench_fileio/$1_$2"K"_$3_iostat.diskio.log &
    vmstat 1 900       2>&1 > /tmp/sysbench_fileio/$1_$2"K"_$3_vmstat.memory.cpu.log &

    sudo sysbench --test=fileio --file-test-mode=$1 --file-block-size=$2"K" --num-threads=$3 ${EXTRA} run > /tmp/sysbench_fileio/$1_$2"K"_$3_sysbench.log

    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Unable to execute sysbench fileio mode $1_$2"K"_$3. Aborting..."
    fi

    sudo pkill -f iostat
    sudo pkill -f vmstat
}

mkdir -p /tmp/sysbench_fileio

if [[ ${DISK} == *"xvd"* || ${DISK} == *"sd"* ]]
then
    sudo mkfs.ext4 ${DISK}
    sudo mkdir /stor
    sudo mount ${DISK} /stor
    sudo chmod 777 /stor
    cd /stor
elif [[ ${DISK} == *"md"* ]]
then
    sudo chmod 777 /raid
    cd /raid
else
    LogMsg "Failed to identify disk type for ${DISK}."
    exit 70
fi

sudo sysbench --test=fileio --file-total-size=84G prepare >> ${LOG_FILE}
for mode in "${MODES[@]}"
do
    for io in "${IOS[@]}"
    do
        for thread in "${THREADS[@]}"
        do
            fileio ${mode} ${io} ${thread}
        done
        sleep 10
    done
    sleep 10
done
sudo sysbench --test=fileio --file-total-size=84G cleanup >> ${LOG_FILE}

LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"

cd /tmp
zip -r sysbench.zip . -i sysbench_fileio/* >> ${LOG_FILE}
zip -r sysbench.zip . -i summary.log >> ${LOG_FILE}
