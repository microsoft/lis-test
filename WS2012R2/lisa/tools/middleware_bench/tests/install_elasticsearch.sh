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

echo "system configuration"
sudo swapoff -a
sudo sysctl -w vm.max_map_count=262144
USER="$1"
DISK="$2"
echo "${USER}  -  nofile  65536" | sudo tee -a /etc/security/limits.conf
echo 'session required pam_limits.so' | sudo tee -a /etc/pam.d/su

distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt-get update
    sudo apt-get install -y python3-pip default-jdk
    sudo pip3 install esrally
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum install -y gcc python34.x86_64 python34-devel.x86_64 python34-setuptools.noarch git python34-pip java-1.8.0-openjdk*
    sudo pip-3.4 install esrally
    export PATH=$PATH:/usr/local/bin
else
    echo "Unsupported distribution: ${distro}."
fi


sudo mkfs.ext4 ${DISK}
sudo mkdir /mnt/data
sudo mount ${DISK} /mnt/data/

echo -ne '\n' | esrally configure
sed -i "/^root.dir.*/c\root.dir = /mnt/data" ~/.rally/rally.ini

sudo chown -R ${USER}:${USER} /mnt/data/
