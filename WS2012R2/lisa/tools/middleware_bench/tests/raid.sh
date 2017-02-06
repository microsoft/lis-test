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
LOG_FILE=/tmp/raid.log
function LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1} >> ${LOG_FILE}
}
if [ $# -lt 3 ]; then
    echo -e "\nUsage:\n$0 level raid-devices dev1 dev2 ..."
    exit 1
fi
level=$1
no_devices=$2
declare -a devices=("${@:3}")

sudo apt-get install -y mdadm

# force disk rescan
#for i in /sys/class/scsi_host/*; do sudo echo "- - -" > ${i}/scan; done
#sudo fdisk -l

LogMsg "Parameters are level=${level} raid-devices=${no_devices} devices=${devices[@]}"
conf_raid()
{
DEV="/dev/md0"
sudo mdadm --create --verbose ${DEV} --level=${level} --name=MY_RAID --raid-devices=${no_devices} "${devices[@]}" >> ${LOG_FILE}
sudo mdadm --wait ${DEV} >> ${LOG_FILE}
sudo mkfs.ext4 -L MY_RAID ${DEV} >> ${LOG_FILE}
sudo mkdir -p /raid
sudo mount LABEL=MY_RAID /raid
}

conf_raid