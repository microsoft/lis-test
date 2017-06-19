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
#       This script Orion tests on a Ubuntu machine
#
#       Steps:
#       1. Runs orion
#       4. Prepares results
#
#######################################################################

LOG_FILE=/tmp/summary.log
function LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1} >> ${LOG_FILE}
}

if [ $# -lt 1 ]; then
    echo -e "\nUsage:\n$0 device1, device2, ..."
    exit 1
fi


declare -a DISKS=("${@:1}")
ORION_SCENARIO_FILE="orion"
FILE_NAME="orion_linux_x86-64.gz"
TEST_MODES=(oltp dss simple normal)
ORION=${FILE_NAME}

if [ ${#DISKS[@]} -gt 1 ]
then
    LogMsg "Using multiple disks."
fi

distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt-get update && sudo apt-get upgrade -y >> ${LOG_FILE}
    sudo apt-get -y install libaio1 sysstat zip >> ${LOG_FILE}
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum clean dbcache>> ${LOG_FILE}
    sudo yum -y install sysstat zip >> ${LOG_FILE}
else
    LogMsg "Unsupported distribution: ${distro}."
fi

run_orion()
{
    LogMsg "Orion start running in $1 mode."
    for i in "${!DISKS[@]}"
    do
        iostat -x -d 1 4000 `basename ${DISKS[$i]}`  2>&1 > /tmp/orion/$1.iostat.diskio.log &
    done

    vmstat       1 4000      2>&1 > /tmp/orion/$1.vmstat.memory.cpu.log &

    sudo /tmp/orion_linux_x86-64 -run $1 -testname ${ORION_SCENARIO_FILE} $2 2>&1 | tee -a ${LOG_FILE}
    sts=$?
    sudo pkill -f iostat >> ${LOG_FILE}
    sudo pkill -f vmstat >> ${LOG_FILE}
    if [ ${sts} -eq 0 ]; then
        sudo mv /tmp/*_iops.csv /tmp/orion/$1_iops.csv
        sudo mv /tmp/*_lat.csv /tmp/orion/$1_lat.csv
        sudo mv /tmp/*_mbps.csv /tmp/orion/$1_mbps.csv
        sudo mv /tmp/*_summary.txt /tmp/orion/$1_summary.txt
        sudo mv /tmp/*_trace.txt /tmp/orion/$1_trace.txt
        LogMsg "$1 test completed. Sleep 60 seconds."
        sleep 60
    else
        LogMsg "$1 test failed."
    fi
}

cd /tmp
gunzip -f /tmp/${ORION}
chmod 755 /tmp/orion_linux_x86-64
mkdir -p /tmp/orion
for i in "${!DISKS[@]}"
do
    sudo mkfs.ext4 ${DISKS[$i]}
    sudo mkdir /stor${i}
    sudo mount ${DISKS[$i]} /stor${i}
    echo ${DISKS[$i]} >> /tmp/${ORION_SCENARIO_FILE}.lun
done

for mode in "${TEST_MODES[@]}"
do
    run_orion ${mode}
done

LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"

cd /tmp
sudo zip -r orion.zip . -i orion/* >> ${LOG_FILE}
sudo zip -r orion.zip . -i summary.log >> ${LOG_FILE}
