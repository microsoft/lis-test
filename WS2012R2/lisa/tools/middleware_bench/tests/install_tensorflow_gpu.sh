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
DISK="$1"
USER="$2"

sudo mkfs.ext4 ${DISK}
sudo mkdir /mnt/data
sudo mount ${DISK} /mnt/data/

mkdir -p /tmp/tensorflow_gpu
sudo mkdir -p /mnt/data/tensorflow_gpu
sudo chmod a+rwxt /mnt/data/tensorflow_gpu
sudo chown -R ${USER}:${USER} /mnt/data/

distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt-get update
    sudo DEBIAN_FRONTEND='noninteractive' /usr/bin/apt-get -y install python
    sudo DEBIAN_FRONTEND='noninteractive' /usr/bin/apt-get -y install pciutils
    sudo DEBIAN_FRONTEND='noninteractive' /usr/bin/apt-get -y install build-essential git libtool autoconf automake
    sudo DEBIAN_FRONTEND='noninteractive' /usr/bin/apt-get -y install wget
    wget -q https://developer.nvidia.com/compute/cuda/8.0/Prod2/local_installers/cuda-repo-ubuntu1604-8-0-local-ga2_8.0.61-1_amd64-deb -O /mnt/data/cuda-repo-ubuntu1604-8-0-local-ga2_8.0.61-1_amd64-deb.deb
    sudo dpkg -i /mnt/data/cuda-repo-ubuntu1604-8-0-local-ga2_8.0.61-1_amd64-deb.deb
    sudo apt-get update
    sudo apt-get install -y cuda

    wget -q https://developer.nvidia.com/compute/cuda/8.0/Prod2/patches/2/cuda-repo-ubuntu1604-8-0-local-cublas-performance-update_8.0.61-1_amd64-deb -O /mnt/data/cuda-repo-ubuntu1604-8-0-local-cublas-performance-update_8.0.61-1_amd64-deb.deb
    sudo dpkg -i /mnt/data/cuda-repo-ubuntu1604-8-0-local-cublas-performance-update_8.0.61-1_amd64-deb.deb

    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade
    sudo apt-get upgrade -yq cuda

    sudo apt-get install -y libcupti-dev
    wget -q http://developer.download.nvidia.com/compute/machine-learning/repos/ubuntu1404/x86_64/libcudnn6_6.0.21-1+cuda8.0_amd64.deb -O /mnt/data/libcudnn6_6.0.21-1+cuda8.0_amd64.deb
    sudo dpkg -i /mnt/data/libcudnn6_6.0.21-1+cuda8.0_amd64.deb
    sudo DEBIAN_FRONTEND='noninteractive' /usr/bin/apt-get -y install python-pip
    sudo DEBIAN_FRONTEND='noninteractive' /usr/bin/apt-get -y install git
elif [[ ${distro} == *"Amazon"* ]]
then
    #Amazon Linux
    sudo yum update -y
    sudo yum install -y python-pip git
else
    echo "Unsupported distribution: ${distro}."
fi

nvidia-smi -L
#K80, P100, V100 support
sudo nvidia-smi -pm 1
#STDOUT: Enabled persistence mode for GPU 000003FB:00:00.0.
sudo nvidia-smi --query-gpu=count --id=0 --format=csv
#Returns the number of Nvidia GPUs on the system
sudo nvidia-smi --query-gpu=clocks.applications.memory,clocks.applications.graphics --format=csv --id=0
#Returns the value of the memory and graphics clock
#clocks.applications.memory [MHz], clocks.applications.graphics [MHz]
#2505 MHz, 562 MHz
sudo nvidia-smi --query-gpu=count --id=0 --format=csv
sudo nvidia-smi -q -d CLOCK --id=0
#Returns the state of autoboost and autoboost_default

pip freeze > /mnt/data/tensorflow_gpu/requirements.txt
pip install --upgrade tensorflow-gpu==1.3

if [[ ${distro} == *"Amazon"* ]]
then
    sudo rm -rf /usr/local/cuda
    sudo ln -s /usr/local/cuda-8.0/ /usr/local/cuda
fi

cd /mnt/data
git clone https://github.com/tensorflow/benchmarks.git
cd benchmarks && git checkout abe3c808933c85e6db1719cdb92fcbbd9eac6dec
#getconf LONG_BIT
#lib or lib64
echo -e "import tensorflow; print(tensorflow.__version__)" | PATH=/usr/local/cuda/bin${PATH:+:${PATH}} CUDA_HOME=/usr/local/cuda LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}} python
if [ $? -ne 0 ]; then 
 echo -e "Failed to install tensorflow, please check logs for details" 
 exit 1  
fi

wget https://raw.githubusercontent.com/GoogleCloudPlatform/PerfKitBenchmarker/f03f7045d058af47ea32cc073420d7f4e6b653f9/perfkitbenchmarker/scripts/execute_command.py -O /tmp/tensorflow_gpu/execute_command.py
wget https://raw.githubusercontent.com/GoogleCloudPlatform/PerfKitBenchmarker/master/perfkitbenchmarker/scripts/wait_for_command.py -O /tmp/tensorflow_gpu/wait_for_command.py