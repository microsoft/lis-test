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

if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi

sudo apt-get update >> ${LOG_FILE}
sudo apt-get -y install libaio1 sysstat zip sysbench >> ${LOG_FILE}

cd /tmp
mkdir -p /tmp/sysbench_fileio
sudo sysbench --test=fileio cleanup >> ${LOG_FILE}
sudo sysbench --test=fileio prepare >> ${LOG_FILE}

function fileio ()
{
    LogMsg " Testing sysbench fileio mode=$1 ios=$2"K" threads=$3."
    EXTRA="--file-total-size=134G --file-extra-flags=dsync --file-fsync-freq=0 --max-requests=0 --max-time=300"
    iostat -x -d 1 900 2>&1 > /tmp/sysbench_fileio/$1_$2"K"_$3_iostat.diskio.log &
    vmstat 1 900       2>&1 > /tmp/sysbench_fileio/$1_$2"K"_$3_vmstat.memory.cpu.log &

    sudo sysbench --test=fileio --file-test-mode=$1 --file-block-size=$2"K" --num-threads=$3 ${EXTRA} run > /tmp/sysbench_fileio/$1_$2"K"_$3_sysbench.log

    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Unable to execute sysbench fileio mode $1_$2"K"_$3. Aborting..."
    fi

    sudo pkill -f iostat
    sudo pkill -f vmstat
}

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

sudo sysbench --test=fileio cleanup

LogMsg "Kernel Version : `uname -r` "

cd /tmp
zip -r sysbench.zip . -i sysbench_fileio/* >> ${LOG_FILE}
zip -r sysbench.zip . -i summary.log >> ${LOG_FILE}

function finish {
  LogMsg "Execution ended with exit code $?"
}
trap finish EXIT
