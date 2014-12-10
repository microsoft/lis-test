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
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################

# Description : This script will configure kdump on the linux VM


# Sourcing the testdata files
if [ -e $HOME/testdata.sh ]; then
	. $HOME/testdata.sh
else
	echo "ERROR: Unable to source the testdata file."
	exit 1
fi

# Register Suse Distribution for online updates
echo "Registration Successful"  
suse_register -a email=$email
if [ 0 -ne $? ]; then
	echo " Error: Registration to Suse failed "
    echo "Aborting test."
    exit 1
fi

# Enable the required repositories for getting debug packages
modules=(nu_novell_com:SLE11-SP1-Debuginfo-Pool nu_novell_com:SLE11-SP1-Debuginfo-Updates nu_novell_com:SLE11-SP2-Debuginfo-Core nu_novell_com:SLE11-SP2-Debuginfo-Updates)

for mod in ${modules[*]}
do
    echo " ${mod} Repository Enabled Successfully"
	zypper modifyrepo --enable ${mod}
    if [ 0 -ne $? ]; then
        echo " Error: Could not enable the repository ${mod} "
        echo "Aborting test."
        exit 1
    fi
done

# Upgrade the kernel and packages using
zypper --non-interactive up

# Install the appropriate debuginfo packages
modules=(kexec* kernel-default-debuginfo kernel-default-devel-debuginfo )

for mod in ${modules[*]}
do
    echo "Debug package ${mod} installed successfully"
	zypper --non-interactive install ${mod}
    if [ 0 -ne $? ]; then
        echo " Error: Could not install debug packages ${mod}"
        echo "Aborting test."
        exit 1
    fi
done

# Configure Kdump
chkconfig boot.kdump on
echo " Boot configuration file backed up successfully "  
cp /boot/grub/menu.lst /boot/grub/menu.lst-bkup
if [ 0 -ne $? ]; then
    echo " Error: Boot configuration file could not be backed up "
fi

# Modifying the boot configuration for Kdump
echo "Boot configuration file modified successfully with Kdump configuration " 
sed s/showopts/'showopts crashkernel=256M@128M'/ /boot/grub/menu.lst > /tmp/new.lst
if [ 0 -ne $? ]; then
    echo " Error: Boot configuration file could not be modified for Kdump configuration "
    echo "Aborting test."
	exit 1
fi

chmod 775 /boot/grub/menu.lst /tmp/new.lst
echo " Boot configuration file restored successfully"  
sudo cp /tmp/new.lst /boot/grub/menu.lst
if [ 0 -ne $? ]; then
    echo " Error: Boot configuration file could not be restored "
	echo "Aborting test."
	exit 1		
fi

#Verifying if the menu.lst has the changes
echo "Boot configuration successful"
grep 'crashkernel' /boot/grub/menu.lst
if [ 0 -ne $? ]; then
	echo " Error: Please reserve memory in the boot configuration "
	echo "Aborting test."
	exit 1
fi

# Configuring Linux Kernel for NMI interrupts
echo kernel.unknown_nmi_panic = 1 >> /etc/sysctl.conf

# Rebooting the VM to apply kdump configuration
reboot