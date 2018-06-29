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
mkdir -p /tmp/tensorflow_cpu
sudo mkdir -p /opt/tensorflow_cpu
sudo chmod a+rwxt /opt/tensorflow_cpu

distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt-get update
    sudo DEBIAN_FRONTEND='noninteractive' /usr/bin/apt-get -y install python
    sudo DEBIAN_FRONTEND='noninteractive' /usr/bin/apt-get -y install lsb-release
    sudo apt-get -y install pciutils
    sudo DEBIAN_FRONTEND='noninteractive' /usr/bin/apt-get -y install python-pip
    sudo /usr/bin/apt-get -y install git
elif [[ ${distro} == *"Amazon"* ]]
then
    #Amazon Linux
    sudo yum update -y
    sudo yum install -y python redhat-lsb-core python-pip git
else
    echo "Unsupported distribution: ${distro}."
fi

cat /proc/sys/net/ipv4/tcp_congestion_control
lscpu
lsb_release -d
uname -r

#Preparing benchmark tensorflow
lspci
sudo mkdir -p /opt/tensorflow_cpu && sudo pip freeze > /opt/tensorflow_cpu/requirements.txt
sudo pip install --upgrade https://anaconda.org/intel/tensorflow/1.4.0/download/tensorflow-1.4.0-cp27-cp27mu-linux_x86_64.whl
git clone https://github.com/tensorflow/benchmarks.git
cd benchmarks && git checkout abe3c808933c85e6db1719cdb92fcbbd9eac6dec
lspci
python -c "import tensorflow; print(tensorflow.__version__)" 
lspci

wget https://raw.githubusercontent.com/GoogleCloudPlatform/PerfKitBenchmarker/master/perfkitbenchmarker/scripts/execute_command.py -O /tmp/tensorflow_cpu/execute_command.py
wget https://raw.githubusercontent.com/GoogleCloudPlatform/PerfKitBenchmarker/master/perfkitbenchmarker/scripts/wait_for_command.py -O /tmp/tensorflow_cpu/wait_for_command.py