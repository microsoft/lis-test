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

DISK="$1"
USER="$2"

if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi

sleep 30

LogMsg "Install tensorflow"
/tmp/install_tensorflow_gpu.sh ${DISK} ${USER} >> ${LOG_FILE}

sleep 30

if [ $? -ne 0 ]; then
 echo -e "Failed to install tensorflow, please check ${LOG_FILE} for details"
 exit 1
fi

distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt -y install zip >> ${LOG_FILE}
elif [[ ${distro} == *"Amazon"* ]]
then
    sed -i 's/import cPickle/import _pickle as cPickle/g' /mnt/data/benchmarks/scripts/tf_cnn_benchmarks/datasets.py
else
    echo "Unsupported distribution: ${distro}."
fi

gpucount=0
count=`sudo nvidia-smi --query-gpu=count --id=0 --format=csv`
for i in $count
do
   gpucount=$i
done

MODES=(inception3 vgg16 alexnet resnet50 resnet152)
BATCH_SIZE=(32 64 128 512)

for mode in "${MODES[@]}"
do
    for size in "${BATCH_SIZE[@]}"
    do
        LogMsg "Run tensorflow --batch_size=${size} --model=${mode} --data_name=imagenet  --device=gpu"
        uuid=$(uuidgen)
        SECONDS=0
        nohup python /tmp/tensorflow_gpu/execute_command.py --stdout /tmp/tensorflow_gpu/cmd${uuid}.stdout --stderr /tmp/tensorflow_gpu/cmd${uuid}.stderr --status /tmp/tensorflow_gpu/cmd${uuid}.status --command 'cd /mnt/data/benchmarks/scripts/tf_cnn_benchmarks;PATH=/usr/local/cuda/bin${PATH:+:${PATH}} CUDA_HOME=/usr/local/cuda LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}} python tf_cnn_benchmarks.py --local_parameter_device=cpu --batch_size='"${size}"' --model='"${mode}"' --data_name=imagenet --variable_update=parameter_server --distortions=True --device=gpu --data_format=NCHW --forward_only=False --use_fp16=False --num_gpus='"${gpucount}"'' 1> /tmp/tensorflow_gpu/cmd${uuid}.log 2>&1 &

        python /tmp/tensorflow_gpu/wait_for_command.py --status /tmp/tensorflow_gpu/cmd${uuid}.status
        echo "RuntimeSec: ${SECONDS}" >> /tmp/tensorflow_gpu/cmd${uuid}.stdout

        sudo lspci
        sudo nvidia-smi --query-gpu=clocks.applications.memory,clocks.applications.graphics --format=csv --id=0
        sudo nvidia-smi -q -d CLOCK --id=0
        nvidia-smi
        nvidia-smi -L
        sudo nvidia-smi --query-gpu=count --id=0 --format=csv
        nvidia-smi topo -p2p r
        sudo lspci
        sudo nvidia-smi --query-gpu=count --id=0 --format=csv
        sudo lspci
        getconf LONG_BIT
    done
done

LogMsg "Gpu Count : ${gpucount}"
LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"

cd /tmp
zip -r tensorflow_gpu.zip . -i tensorflow_gpu/* >> ${LOG_FILE}
zip -r tensorflow_gpu.zip . -i summary.log >> ${LOG_FILE}
