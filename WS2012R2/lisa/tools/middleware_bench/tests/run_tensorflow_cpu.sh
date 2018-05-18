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

distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt -y install zip >> ${LOG_FILE}
fi

LogMsg "Install tensorflow"

/tmp/install_tensorflow_cpu.sh >> ${LOG_FILE}

MODES=(inception3 vgg16 alexnet resnet50 resnet152)
BATCH_SIZE=(32 64 128 512)

for mode in "${MODES[@]}"
do
    for size in "${BATCH_SIZE[@]}"
    do
        LogMsg "Run tensorflow --batch_size=${size} --model=${mode} --data_name=imagenet  --device=cpu"
        uuid=$(uuidgen)
        SECONDS=0
        nohup python /tmp/tensorflow_cpu/execute_command.py --stdout /tmp/tensorflow_cpu/cmd${uuid}.stdout --stderr /tmp/tensorflow_cpu/cmd${uuid}.stderr --status /tmp/tensorflow_cpu/cmd${uuid}.status --command 'cd benchmarks/scripts/tf_cnn_benchmarks ; python tf_cnn_benchmarks.py --local_parameter_device=cpu --batch_size='"${size}"' --model='"${mode}"' --data_name=imagenet --variable_update=parameter_server --distortions=True --device=cpu --data_format=NHWC --forward_only=False --use_fp16=False' 1> /tmp/tensorflow_cpu/cmd${uuid}.log 2>&1 &

        python /tmp/tensorflow_cpu/wait_for_command.py --status /tmp/tensorflow_cpu/cmd${uuid}.status
        echo "RuntimeSec: ${SECONDS}" >> /tmp/tensorflow_cpu/cmd${uuid}.stdout

    done
done

LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"

cd /tmp
zip -r tensorflow_cpu.zip . -i tensorflow_cpu/* >> ${LOG_FILE}
zip -r tensorflow_cpu.zip . -i summary.log >> ${LOG_FILE}
