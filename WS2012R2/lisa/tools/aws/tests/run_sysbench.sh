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
#       This script installs and runs Sysbench tests on a guest VM
#
#       Steps:
#       1. Installs dependencies
#       2. Compiles and installs sysbench
#       3. Runs sysbench
#       4. Prepares results
#
#       No optional parameters needed
#
########################################################################
LOG_FILE=/tmp/summary.log
function LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1} >> ${LOG_FILE}
}

MODES=(seqwr seqrewr seqrd rndrd rndwr rndrw)
THREADS=(1 2 4 8 16 32 64 128 256 512 1024)
IOS=(4 8 16 32)

sudo yum upgrade
sudo yum install zip libaio sysstat git automake libtool -y

echo "Cloning sysbench"
cd /tmp
rm -rf sysbench/
git clone https://github.com/akopytov/sysbench.git
cd /tmp/sysbench
bash ./autogen.sh
bash ./configure --without-mysql
make
sudo make install
if [ $? -gt 0 ]; then
    echo "Failed to installing sysbench."
    exit 10
fi

cd ~
mkdir -p /tmp/benchmark/sysbench
sysbench --test=fileio cleanup

# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi
echo "This script tests sysbench on VM."

function fileio ()
{
    EXTRA="--file-total-size=134G --file-extra-flags=dsync --file-fsync-freq=0 --max-requests=0 --max-time=300"
    iostat -x -d 1 900 2>&1 > /tmp/benchmark/sysbench/$1_$2"K"_$3_iostat.diskio.log &
    vmstat 1 900       2>&1 > /tmp/benchmark/sysbench/$1_$2"K"_$3_vmstat.memory.cpu.log &

    sudo sysbench --test=fileio --file-test-mode=$1 --file-block-size=$2"K" --num-threads=$3 ${EXTRA} run > /tmp/benchmark/sysbench/$1_$2"K"_$3_sysbench.log

    if [ $? -ne 0 ]; then
        echo "ERROR: Unable to execute sysbench fileio mode $1_$2"K"_$3. Aborting..."
    fi

    sudo pkill -f iostat
    sudo pkill -f vmstat
}

echo " Testing fileio. Writing to fileio.log."
for mode in "${MODES[@]}"
do
    for io in "${IOS[@]}"
    do
        for thread in "${THREADS[@]}"
        do
            fileio ${mode} ${io} ${thread}
        done
    done
done
sysbench --test=fileio cleanup

cd /tmp
zip -r sysbench.zip . -i benchmark/sysbench/*
zip -r sysbench.zip . -i summary.log