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
if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi
mkdir -p /tmp/nodejs

distro="$(head -1 /etc/issue)"
commitHash='c891603b2c6068ba4960ae8eacb11d23aa93bea0'
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt update
    sudo apt -y install sysstat zip >> ${LOG_FILE}
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum clean dbcache>> ${LOG_FILE}
    sudo yum -y install git sysstat zip>> ${LOG_FILE}
else
    LogMsg "Unsupported distribution: ${distro}."
fi




# Install nodejs from binary
wget https://nodejs.org/dist/v8.9.4/node-v8.9.4-linux-x64.tar.xz
sudo mkdir /usr/lib/nodejs
sudo tar -xJvf node-v8.9.4-linux-x64.tar.xz -C /usr/lib/nodejs 
sudo mv /usr/lib/nodejs/node-v8.9.4-linux-x64 /usr/lib/nodejs/node-v8.9.4

echo | tee -a .profile << EOF
export PATH=/usr/lib/nodejs/node-v8.9.4/bin:$PATH
EOF
source .profile


#check out a fixed version from fixed commit hash
git clone https://github.com/v8/web-tooling-benchmark
cd web-tooling-benchmark
git reset --hard $commitHash


#Build the benchmark suite and run test
npm install >> ${LOG_FILE}

sar -n DEV 1 2>&1 > /tmp/nodejs/sar.netio.log &
iostat -x -d 1 2>&1 > /tmp/nodejs/iostat.netio.log &
vmstat 1 2>&1 > /tmp/nodejs/vmstat.netio.log &

node dist/cli > /tmp/nodejs/web_tooling_benchmark.log

sudo pkill -f sar
sudo pkill -f iostat
sudo pkill -f vmstat


LogMsg "Nodejs Version: `node -v`"
LogMsg "Benchmark Commit Hash: $commitHash"
LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"


cd /tmp
zip -r nodejs.zip . -i nodejs/* >> ${LOG_FILE}
zip -r nodejs.zip . -i summary.log >> ${LOG_FILE}

