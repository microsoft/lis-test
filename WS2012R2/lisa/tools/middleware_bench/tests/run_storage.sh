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

if [ $# -lt 1 ]; then
    echo -e "\nUsage:\n$0 disk"
    exit 1
fi

DISK="$1"

QDEPTH=(1 2 4 8 16 32 64 128 256 512 1024)
IO_SIZE=(4 8 128 1024)
FILE_SIZE=(16)
IO_MODE=(read randread write randwrite)

if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi

distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt-get update && sudo apt-get upgrade -y >> ${LOG_FILE}
    sudo apt-get -y install sysstat zip fio blktrace bc libaio1 >> ${LOG_FILE}
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum clean dbcache>> ${LOG_FILE}
    sudo yum -y install sysstat zip blktrace bc libaio* wget gcc automake autoconf >> ${LOG_FILE}
    cd /tmp; wget http://brick.kernel.dk/snaps/fio-2.21.tar.gz
    tar -xzf fio-2.21.tar.gz
    cd fio-2.21; ./configure; sudo make; sudo make install
    sudo cp /usr/local/bin/fio /usr/bin/fio
else
    LogMsg "Unsupported distribution: ${distro}."
fi

if [[ ${DISK} == *"xvd"* || ${DISK} == *"sd"* ]]
then
    sudo mkfs.ext4 ${DISK}
    sudo mkdir /stor
    sudo mount ${DISK} /stor
    sudo chmod 777 /stor
    MNT="/stor"
elif [[ ${DISK} == *"md"* ]]
then
    sudo chmod 777 /raid
    MNT="/raid"
else
    LogMsg "Failed to identify disk type for ${DISK}."
    exit 70
fi

cd /tmp
mkdir -p /tmp/storage

function run_storage ()
{
    qdepth=$1
    io_size=$2
    file_size=$3
    io_mode=$4

    if [[ ${qdepth} -gt 8 ]]
    then
        actual_q_depth=$((${qdepth} / 8))
        num_jobs=8
    else
        actual_q_depth=${qdepth}
        num_jobs=1
    fi

    LogMsg "======================================"
    LogMsg "Running Test qdepth= ${qdepth} io_size=${io_size} io_mode=${io_mode} file_size=${file_size}"
    LogMsg "======================================"

    iostat -x -d 1 900 2>&1 > /tmp/storage/${qdepth}.iostat.netio.log &
    vmstat 1 900       2>&1 > /tmp/storage/${qdepth}.vmstat.netio.log &

    sudo fio --name=${io_mode} --bs=${io_size}k --ioengine=libaio --iodepth=${actual_q_depth} --size=${file_size}G --direct=1 --runtime=120 --numjobs=${num_jobs} --rw=${io_mode} --group_reporting --directory ${MNT} > /tmp/storage/${io_size}K-${qdepth}-${io_mode}.fio.log

    sudo pkill -f iostat
    sudo pkill -f vmstat

    LogMsg "sleep 10 seconds"
    sleep 10
}

for qdepth in "${QDEPTH[@]}"
do
    for io_size in "${IO_SIZE[@]}"
    do
        for file_size in "${FILE_SIZE[@]}"
        do
            for io_mode in "${IO_MODE[@]}"
            do
                run_storage ${qdepth} ${io_size} ${file_size} ${io_mode}
            done
        done
    done
done

LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"

cd /tmp
zip -r storage.zip . -i storage/* >> ${LOG_FILE}
zip -r storage.zip . -i summary.log >> ${LOG_FILE}
