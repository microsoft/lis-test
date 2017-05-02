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

if [ $# -lt 1 ]; then
    echo -e "\nUsage:\n$0 instancetype"
    exit 1
fi

INSTANCETYPE="$1"

sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y build-essential rpm dkms

if [[ ${INSTANCETYPE} == *"p2."* ]]; then
    cd /tmp
    git clone https://github.com/amzn/amzn-drivers
    amzn_drv_version=`sed -n  's/---- r\([0-9.]*\) ----/\1/p' amzn-drivers/kernel/linux/ena/RELEASENOTES.md | head -1`
    sudo mv amzn-drivers /usr/src/amzn-drivers-${amzn_drv_version}
    sudo echo -e "PACKAGE_NAME=\"ena\"\nPACKAGE_VERSION=\"${amzn_drv_version}\"\nCLEAN=\"make -C kernel/linux/ena clean\"\nMAKE=\"make -C kernel/linux/ena/ BUILD_KERNEL=\${kernelver}\"\nBUILT_MODULE_LOCATION[0]=\"kernel/linux/ena/\"\nBUILT_MODULE_NAME[0]=\"ena\"\nDEST_MODULE_LOCATION[0]=\"/updates\"\nDEST_MODULE_NAME[0]=\"ena\"\nAUTOINSTALL=\"yes\"\n" > /usr/src/amzn-drivers-${amzn_drv_version}/dkms.conf
    sudo dkms add -m amzn-drivers -v ${amzn_drv_version}
    sudo dkms build -m amzn-drivers -v ${amzn_drv_version}
    sudo dkms install -m amzn-drivers -v ${amzn_drv_version}
    sudo update-initramfs -c -k all
else
    cd /tmp
    wget https://sourceforge.net/projects/e1000/files/ixgbevf%20stable/3.1.2/ixgbevf-3.1.2.tar.gz
    tar -xf ixgbevf-3.1.2.tar.gz
    sudo mv ixgbevf-3.1.2 /usr/src/
    sudo echo -e "PACKAGE_NAME=\"ixgbevf\"\nPACKAGE_VERSION=\"3.1.2\"\nCLEAN=\"cd src/; make clean\"\nMAKE=\"cd src/; make BUILD_KERNEL=\${kernelver}\"\nBUILT_MODULE_LOCATION[0]=\"src/\"\nBUILT_MODULE_NAME[0]=\"ixgbevf\"\nDEST_MODULE_LOCATION[0]=\"/updates\"\nDEST_MODULE_NAME[0]=\"ixgbevf\"\nAUTOINSTALL=\"yes\"\n" > /usr/src/ixgbevf-3.1.2/dkms.conf
    sudo dkms add -m ixgbevf -v 3.1.2
    sudo dkms build -m ixgbevf -v 3.1.2
    sudo dkms install -m ixgbevf -v 3.1.2
    sudo update-initramfs -c -k all
    sudo echo "options ixgbevf InterruptThrottleRate=1,1,1,1,1,1,1,1" > /etc/modprobe.d/ixgbevf.conf
    sudo sed -i '/^GRUB\_CMDLINE\_LINUX/s/\"$/\ net\.ifnames\=0\"/' /etc/default/grub
    sudo update-grub
fi

