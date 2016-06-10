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

###############################################################
#
# Description:
#     This script was created to automate the setup of a PXE Server
#     It sets up the tftp server and http server for PXE install.
#     If distro is set to ubuntu, it will download necessary files
#     If distro is rhel or sles, it will mount an iso and copy the files
#  
#     MANDATORY: The PXE server has to have a dhcp, http and tftp server
#                running already
#
################################################################

#######################################################################
# Adds a timestamp to the log file
#######################################################################
LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}
}

#######################################################################
# Updates the summary.log file
#######################################################################
UpdateSummary()
{
    echo $1 >> ~/summary.log
}

#######################################################################
# Keeps track of the state of the test
#######################################################################
UpdateTestState()
{
    echo $1 > ~/state.txt
}

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Source constants file and initialize most common variables
UtilsInit

# In case of error
case $? in
    0)
        # Do nothing
        ;;
    1)
        LogMsg "ERROR: Unable to cd to $LIS_HOME. Aborting..."
        UpdateSummary "ERROR: Unable to cd to $LIS_HOME. Aborting..."
        SetTestStateAborted
        exit 3
        ;;
    2)
        LogMsg "ERROR: Unable to use test state file. Aborting..."
        UpdateSummary "ERROR: Unable to use test state file. Aborting..."
        # Need to wait for test timeout to kick in
        sleep 60
        echo "TestAborted" > state.txt
        exit 4
        ;;
    3)
        LogMsg "ERROR: unable to source constants file. Aborting..."
        UpdateSummary "ERROR: unable to source constants file"
        SetTestStateAborted
        exit 5
        ;;
    *)
        # Should not happen
        LogMsg "ERROR: UtilsInit returned an unknown error. Aborting..."
        UpdateSummary "ERROR: UtilsInit returned an unknown error. Aborting..."
        SetTestStateAborted
        exit 6
        ;;
esac

#
# Check if the CDROM module is loaded
#
CD=`lsmod | grep 'ata_piix\|isofs'`
if [[ $CD != "" ]] ; then
    module=`echo $CD | cut -d ' ' -f1`
    LogMsg "${module} module is present."
else
    LogMsg "ata_piix module is not present in VM"
    LogMsg "Loading ata_piix module "
    insmod /lib/modules/`uname -r`/kernel/drivers/ata/ata_piix.ko
    sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "Unable to load ata_piix module"
        LogMsg "Aborting test."
        UpdateSummary "ata_piix load : Failed"
        UpdateTestState "TestFailed"
        exit 1
    else
        LogMsg "ata_piix module loaded inside the VM"
    fi
fi

sleep 1
mkdir /var/www/PXE
if [ $distro != "ubuntu" ]; then
    LogMsg "Mount the CDROM"
    mount /dev/cdrom /mnt/
    sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "Unable to mount the CDROM"
        LogMsg "Mount CDROM failed: ${sts}"
        LogMsg "Aborting test."
        UpdateTestState "TestFailed"
        exit 1
    else
        LogMsg  "CDROM is mounted successfully inside the VM"
        LogMsg  "CDROM is detected inside the VM"
    fi

    ls /mnt
    sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "Unable to read data from the CDROM"
        LogMsg "Read data from CDROM failed: ${sts}"
        UpdateTestState "TestFailed"
        exit 1
    else
        LogMsg "Data read successfully from the CDROM"
    fi

    cp -r /mnt/* /var/www/PXE/
fi

# Make the necessary changes to http server
echo "Alias /PXE /var/www/PXE/" >> /etc/httpd/conf.d/pxe.conf
echo "<Directory /var/www/PXE/>" >> /etc/httpd/conf.d/pxe.conf
echo "Options Indexes FollowSymLinks" >> /etc/httpd/conf.d/pxe.conf
echo "Order Deny,Allow" >> /etc/httpd/conf.d/pxe.conf
echo "Allow from all" >> /etc/httpd/conf.d/pxe.conf
echo "</Directory>" >> /etc/httpd/conf.d/pxe.conf

if [ $generation -eq 2 ]; then
    mkdir /var/lib/tftpboot/uefi/PXE
    # Make the necessary changes to the tftp server config
    sed -i -e 's/set timeout=60/set timeout=5/g' /var/lib/tftpboot/uefi/grub.cfg
    sed -i -e '1iset default=3\' /var/lib/tftpboot/uefi/grub.cfg
elif [ $generation -eq 1 ]; then
    mkdir /var/lib/tftpboot/pxelinux/PXE
    # Make the necessary changes to the tftp server config
    sed -i -e 's/timeout 600/timeout 5/g' /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
else
    LogMsg "ERROR: Generation in constants file is not correct"
    UpdateTestState "TestFailed"
    exit 1   
fi

if [ $distro == "rhel" ]; then
    if [ $generation -eq 2 ]; then
        # Copy boot image files to tftp server
        cp /mnt/images/pxeboot/vmlinuz /var/lib/tftpboot/uefi/PXE/
        cp /mnt/images/pxeboot/initrd.img /var/lib/tftpboot/uefi/PXE/

        echo "  menuentry 'RHEL' {" >> /var/lib/tftpboot/uefi/grub.cfg
        if [ $willInstall == "no" ]; then
            echo "  linuxefi uefi/PXE/vmlinuz ip=dhcp inst.repo=http://10.10.10.10/PXE" >> /var/lib/tftpboot/uefi/grub.cfg
        else
            echo "  linuxefi uefi/PXE/vmlinuz ip=dhcp inst.repo=http://10.10.10.10/PXE ks=http://10.10.10.10/PXE/ks.cfg" >> /var/lib/tftpboot/uefi/grub.cfg
        fi
        echo "  initrdefi uefi/PXE/initrd.img" >> /var/lib/tftpboot/uefi/grub.cfg
        echo "  }" >> /var/lib/tftpboot/uefi/grub.cfg
    elif [ $generation -eq 1 ]; then
        # Copy boot image files to tftp server
        cp /mnt/images/pxeboot/vmlinuz /var/lib/tftpboot/pxelinux/PXE
        cp /mnt/images/pxeboot/initrd.img /var/lib/tftpboot/pxelinux/PXE

        echo "label RHEL" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        echo "  menu label ^Install RHEL" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        echo "  menu default" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        echo "  kernel PXE/vmlinuz" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        if [ $willInstall == "no" ]; then
            echo "append initrd=PXE/initrd.img ip=dhcp inst.repo=http://10.10.10.10/PXE" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        else
            echo "  append initrd=PXE/initrd.img ip=dhcp inst.repo=http://10.10.10.10/PXE ks=http://10.10.10.10/PXE/ks.cfg" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        fi

    fi
elif [ $distro == "sles" ]; then
    if [ $generation -eq 2 ]; then
        # Copy boot image files to tftp server
        cp /mnt/boot/x86_64/loader/linux /var/lib/tftpboot/uefi/PXE/
        cp /mnt/boot/x86_64/loader/initrd /var/lib/tftpboot/uefi/PXE/

        echo "  menuentry 'SLES' {" >> /var/lib/tftpboot/uefi/grub.cfg
        if [ $willInstall == "no" ]; then
            echo "  linuxefi uefi/PXE/linux install=http://10.10.10.10/PXE inst.stage2=http://10.10.10.10/PXE" >> /var/lib/tftpboot/uefi/grub.cfg
        else
            echo "  linuxefi uefi/PXE/linux install=http://10.10.10.10/PXE inst.stage2=http://10.10.10.10/PXE autoyast=http:/10.10.10.10/PXE/autoinstGen2.xml" >> /var/lib/tftpboot/uefi/grub.cfg
        fi
        echo "  initrdefi uefi/PXE/initrd" >> /var/lib/tftpboot/uefi/grub.cfg
        echo "  }" >> /var/lib/tftpboot/uefi/grub.cfg

    elif [ $generation -eq 1 ]; then
        # Copy boot image files to tftp server
        cp /mnt/boot/x86_64/loader/linux /var/lib/tftpboot/pxelinux/PXE
        cp /mnt/boot/x86_64/loader/initrd /var/lib/tftpboot/pxelinux/PXE

        echo "label SLES" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        echo "  menu label ^Install SLES" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        echo "  menu default" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        echo "  kernel PXE/linux" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        if [ $willInstall == "no" ]; then
            echo "append initrd=PXE/initrd ip=dhcp install=http://10.10.10.10/PXE inst.stage2=http://10.10.10.10/PXE" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        else
            echo "append initrd=PXE/initrd ip=dhcp install=http://10.10.10.10/PXE inst.stage2=http://10.10.10.10/PXE autoyast=http://10.10.10.10/PXE/autoinstGen1.xml" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        fi
    fi    
elif [ $distro == "ubuntu" ]; then
    # Download latest netboot files
    wget http://archive.ubuntu.com/ubuntu/dists/xenial/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/initrd.gz
    wget http://archive.ubuntu.com/ubuntu/dists/xenial/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/linux
    if [ $generation -eq 2 ]; then
        # Copy boot image files to tftp server
        cp linux /var/lib/tftpboot/uefi/PXE/
        cp initrd.gz /var/lib/tftpboot/uefi/PXE/

        echo "  menuentry 'Ubuntu' {" >> /var/lib/tftpboot/uefi/grub.cfg
        if [ $willInstall == "no" ]; then
            echo "  linuxefi uefi/PXE/linux auto=true priority=critical quiet --" >> /var/lib/tftpboot/uefi/grub.cfg
        else
            echo "  linuxefi uefi/PXE/linux auto=true priority=critical interface=auto url=http://10.10.10.10/PXE/ubuntuGen2.seed" >> /var/lib/tftpboot/uefi/grub.cfg
        fi
        echo "  initrdefi uefi/PXE/initrd.gz" >> /var/lib/tftpboot/uefi/grub.cfg
        echo "  }" >> /var/lib/tftpboot/uefi/grub.cfg

    elif [ $generation -eq 1 ]; then
       
        # Copy boot image files to tftp server
        cp linux /var/lib/tftpboot/pxelinux/PXE
        cp initrd.gz /var/lib/tftpboot/pxelinux/PXE

        echo "label Ubuntu" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        echo "  menu label ^Install Ubuntu" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        echo "  menu default" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        echo "  kernel PXE/linux" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        if [ $willInstall == "no" ]; then
            echo "append initrd=ubuntu16/initrd.gz auto=true priority=critical quiet --" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        else
            echo "append initrd=ubuntu16/initrd.gz auto=true priority=critical interface=auto url=http://10.10.10.10/PXE/ubuntu.seed vga=788 quiet --" >> /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
        fi
    fi    
fi

service httpd restart
service tftp restart

if [ $distro != "ubuntu" ]; then
    umount /mnt/
    sts=$?

    if [ 0 -ne ${sts} ]; then
        LogMsg "Unable to unmount the CDROM"
        LogMsg "umount failed: ${sts}"
        LogMsg "Aborting test."
        UpdateTestState "TestFailed"
        exit 1
    fi
fi

UpdateSummary "Tftp & http setup were successfull"
LogMsg "Result: Setup completed successfully"
UpdateTestState "TestCompleted"
exit 0