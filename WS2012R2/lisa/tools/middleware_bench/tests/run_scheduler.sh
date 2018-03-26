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
#######################################################################
# Description:
#       This script tests the cpu scheduler on a Ubuntu machine
#
#       Steps:
#       1. Runs hackbench
#       2. Run schbench
#
#######################################################################

LOG_FILE=/tmp/summary.log
function LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1} >> ${LOG_FILE}
}

if [ $# -lt 1 ]; then
    echo -e "\nUsage:\n$0 test_type"
    exit 1
fi

TEST_TYPE="$1"
#Schbench
MSG_THREADS=(6 12)
THREADS=$(grep -c ^processor /proc/cpuinfo)
RUNTIME=300
SLEEPTIME=30000
CPUTIME=30000
PIPE=0
RPS=0
# hackbench
DATASIZE=512
LOOPS=200
SEN_REC_GROUPS=(15 30)
FDS=25

distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt update
    sudo apt -y install rt-tests sysstat zip >> ${LOG_FILE}
    cd /tmp
    git clone https://git.kernel.org/pub/scm/linux/kernel/git/mason/schbench.git
    cd /tmp/schbench; make; cd /tmp
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum clean dbcache>> ${LOG_FILE}
    sudo yum -y install rt-tests sysstat zip >> ${LOG_FILE}
else
    LogMsg "Unsupported distribution: ${distro}."
fi

run_hackbench()
{
#   -p, --pipe Sends the data via a pipe instead of the socket (default)
#   -s, --datasize=<size in bytes> Sets the amount of data to send in each message
#   -l, --loops=<number of loops> How many messages each sender/receiver pair should send
#   -g, --groups=<number of groups> Defines how many groups  of  senders  and  receivers  should  be started
#   -f, --fds=<number of file descriptors> Defines  how  many file descriptors each child should use
#   -T, --threads Each sender/receiver child will be a POSIX thread of the parent.
#   -P, --process Hackbench will use fork() on all children (default behaviour
    current_group=$1
    LogMsg "hackbench start running with $current_group sender and receiver groups."
    vmstat 1 2>&1 > /tmp/scheduler/hackbench.${current_group}.vmstat.log &
    sar -P ALL 1 2>&1 > /tmp/scheduler/hackbench.${current_group}.sar.cpu.log &
    iostat -x -d 1 2>&1 > /tmp/scheduler/hackbench.${current_group}.iostat.log &

    hackbench -s ${DATASIZE} -l ${LOOPS} -g ${current_group} -f ${FDS} -P > /tmp/scheduler/hackbench.${current_group}.log 2>&1

    sudo pkill -f vmstat >> ${LOG_FILE}
    sudo pkill -f sar >> ${LOG_FILE}
    sudo pkill -f iostat >> ${LOG_FILE}
    sleep 5
}

run_schbench()
{
#    -m (--message-threads): number of message threads (def: 2)
#    -t (--threads): worker threads per message thread (def: 16)
#    -r (--runtime): How long to run before exiting (seconds, def: 30)
#    -s (--sleeptime): Message thread latency (usec, def: 10000
#    -c (--cputime): How long to think during loop (usec, def: 10000
#    -a (--auto): grow thread count until latencies hurt (def: off)
#    -p (--pipe): transfer size bytes to simulate a pipe test (def: 0)
#    -R (--rps): requests per second mode (count, def: 0)
    current_msg_threads=$1
    LogMsg "schbench start running with $current_msg_threads message threads."
    vmstat 1 2>&1 > /tmp/scheduler/schbench.${current_msg_threads}.vmstat.log &
    sar -P ALL 1 2>&1 > /tmp/scheduler/schbench.${current_msg_threads}.sar.cpu.log &
    iostat -x -d 1 2>&1 > /tmp/scheduler/schbench.${current_msg_threads}.iostat.log &

    /tmp/schbench/schbench -c ${CPUTIME} -s ${SLEEPTIME} -m ${current_msg_threads} -t ${THREADS} -r ${RUNTIME} > /tmp/scheduler/schbench.${current_msg_threads}.log 2>&1

    sudo pkill -f vmstat >> ${LOG_FILE}
    sudo pkill -f sar >> ${LOG_FILE}
    sudo pkill -f iostat >> ${LOG_FILE}
    sleep 5
}

mkdir -p /tmp/scheduler

if [[ ${TEST_TYPE} == "hackbench" ]]
then
    for grp in "${SEN_REC_GROUPS[@]}"
    do
        run_hackbench ${grp}
    done
elif [[ ${TEST_TYPE} == "schbench" ]]
then
    for msg in "${MSG_THREADS[@]}"
    do
        run_schbench ${msg}
    done
elif [[ ${TEST_TYPE} == "all" ]]
then
    for msg in "${MSG_THREADS[@]}"
    do
        run_schbench ${msg}
    done
    sleep 60
    for grp in "${SEN_REC_GROUPS[@]}"
    do
        run_hackbench ${grp}
    done
else
    LogMsg "Unsupported test type: ${TEST_TYPE}."
fi

LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"

cd /tmp
zip -r scheduler.zip . -i scheduler/* >> ${LOG_FILE}
zip -r scheduler.zip . -i summary.log >> ${LOG_FILE}
