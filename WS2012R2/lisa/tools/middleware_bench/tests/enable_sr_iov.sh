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
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y build-essential rpm dkms
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