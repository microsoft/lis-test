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

USER="$1"

if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi

distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt -y install zip >> ${LOG_FILE}
fi

LogMsg "ulimit value : `ulimit -n`"
LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"

sudo mkdir /home/${USER}/.rally/logs/elasticsearch

sudo mv /home/${USER}/.rally/logs/*.log /home/${USER}/.rally/logs/elasticsearch

cd /home/${USER}/.rally/logs/

zip -r elasticsearch.zip . -i elasticsearch/* >> ${LOG_FILE}

cp elasticsearch.zip /tmp >> ${LOG_FILE}

cd /tmp
zip -r elasticsearch.zip . -i summary.log >> ${LOG_FILE}
