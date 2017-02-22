# PXE Test Suite Guide

### Introduction
This document is intended as a guide for running PXE Test Suite. The contents of this document will pertain to general configuration advice of both the host computer and the PXE Server virtual machine.

### Supported Linux Distributions
- The Linux distributions that are supported by PXE Test Suite are: CentOS, RHEL, SLES and Ubuntu
- The distribution name is a required parameter in the XML files (centos, rhel, sles or ubuntu)
  + e.g. <param>distro=rhel</param> 
- For SLES, CentOS and RHEL the test suite needs an ISO file:
  + The ISO file should be copied in the default Hyper-V VHD path
  + The name of the ISO file is required as a parameter whithin the XML files (<param>IsoFilename=isoName</param>)
- For Ubuntu:
  + We don't need an ISO file. Also, the IsoFileName in XML files it's not mandatory 
  + Netboot files and installation files will be downloaded over the internet
  + A routing script it's needed. This will give Internet access to the PXE Client VM through the PXE Server's connection.
  + The routing script is provided by default and can be found in lisa/Infrastructure/PXE/routingScript.sh

### Test list
- There are two XML files, each coresponding to PXE Client's generation: 1 or 2
- Each generation has 3 test cases:
  + PXE_basic
    + This will only boot the PXE Client with the netboot files and an installation will not be performed
  + PXE_install_singleCpu
    + This will install a specfic Linux distribution on a PXE Client with one VCPU
  + PXE_install_SMP
    + This will install a specfic Linux distribution on a PXE Client with 4 VCPUs
- All test cases validations are made by verifying the Heartbeat and SQM data
- For PXE_install_singleCpu and PXE_install_SMP we need:
  + Kickstart file for RHEL
  + AutoYaST control file for SLES
  + Preseed file for Ubuntu
- All these files can be found within lisa folder, in /Infrastructure/PXE/ 
- The provided default files are enough for unattended installation. However, they can be edited for a specific use case

### Host
- Before starting the tests, the host needs to have configured 2 vSwitches (External and Private)
- The name of the Private switch will be filled inside both xml files
- The default name for the Private switch (and already filled in the xml files) is PXE 

### PXE Server
This is a VM we need to have before running the PXE Test Suite. For now, we don't have an automation script for deploying this VM. You can use an existing VM which is already configured or you need to configure it manually.

##### General setup
- The VM has to have 2 NICs: External and Private
- The External NIC will be used by LISA
- The Private NIC will be used during the tests by the PXE Server to communicate with the PXE Client
- The OS should be RHEL 7.x
- We need the install ISO of the guest RHEL 7.x to be mounted. This is only needed while we do the setup, after that (while testing) we won't need it. 

**The following guide shows how to setup a PXE Server for both BIOS and UEFI based booting (Gen1 & Gen2 in Hyper-V)**

#####  PXE Server setup
- Set a static ip for the Private NIC (eth1); edit /etc/sysconfig/network-scripts/ifcfg-eth1
  + DEVICE=eth1
  + NAME=eth1 
  + BOOTPROTO=static 
  + IPADDR=10.10.10.10
  + NETMASK=255.255.255.0 
  + ONBOOT=yes

- Install tftp: yum install tftp-server
- Install http server: yum install httpd
- Allow incoming connections to the tftp service in the firewall: firewall-cmd --add-service=tftp
- Make 2 new folders, for BIOS and UEFI booting
  + mkdir /var/lib/tftpboot/pxelinux
  + mkdir /var/lib/tftpboot/uefi
- Install dhcp server: yum install dhcp
- Configure dhcp server; /etc/dhcp/dhcpd.conf should look like this:

  + option space pxelinux;  
  + option pxelinux.magic code 208 = string;  
  + option pxelinux.configfile code 209 = text;  
  + option pxelinux.pathprefix code 210 = text;  
  + option pxelinux.reboottime code 211 = unsigned integer 32;  
  + option architecture-type code 93 = unsigned integer 16;  
  + option routers 10.10.10.10;  
  + option domain-name **DOMAIN_NAME**;  
  + option domain-name-servers **DNS_SERVERS_LIST**;  
  + subnet 10.10.10.0 netmask 255.255.255.0 {  
    + range 10.10.10.20 10.10.10.80;  
    + default-lease-time 43200;  
    + max-lease-time 86400;  
    + class "pxeclients" {  
      + match if substring (option vendor-class-identifier, 0, 9) = "PXEClient";  
      + next-server 10.10.10.10;  
      + if option architecture-type = 00:07 {  
        + filename "uefi/shim.efi";  
      + } else {  
        + filename "pxelinux/pxelinux.0";  
      + }  
    + }  
  + }  
- Mount the install ISO: mount -t iso9660 /path_to_image/name_of_image.iso /mount_point -o loop,ro
- Copy pxelinux.0 and shim.efi into the system:
  + cp -pr /mount_point/Packages/syslinux-version-architecture.rpm /PUBLIC_DIRECTORY
  + cp -pr /mount_point/Packages/shim-version-architecture.rpm /PUBLIC_DIRECTORY
  + cp -pr /mount_point/Packages/grub2-efi-version-architecture.rpm /PUBLIC_DIRECTORY
- Unmount the ISO: umount /mount_point
- Extract the 3 files copied from the ISO
  + rpm2cpio PUBLIC_DIRECTORY/syslinux-version-architecture.rpm | cpio -dimv
  + rpm2cpio PUBLIC_DIRECTORY/shim-version-architecture.rpm | cpio -dimv
  + rpm2cpio PUBLIC_DIRECTORY/grub2-efi-version-architecture.rpm | cpio -dimv
- Copy the extracted files into coresponding tftp folders:
  + cp publicly_available_directory/usr/share/syslinux/pxelinux.0 /var/lib/tftpboot/pxelinux
  + cp publicly_available_directory/boot/efi/EFI/redhat/shim.efi /var/lib/tftpboot/uefi/
  + cp publicly_available_directory/boot/efi/EFI/redhat/grubx64.efi /var/lib/tftpboot/uefi/
- For BIOS-based tftp setup:
  + Create the directory pxelinux.cfg/ in the pxelinux/ directory: mkdir /var/lib/tftpboot/pxelinux/pxelinux.cfg
  + Add a configuration file named default to the pxelinux.cfg/ directory: vi /var/lib/tftpboot/pxelinux/pxelinux.cfg/default
    + default vesamenu.c32
    + timeout 500
    + display boot.msg
  + The following example is for a RHEL7 entry in default file. However, the PXE Test Suite will edit this file, so it's not required to add these lines.
    + label rhel7
    + menu label ^Install RHEL7
    + kernel vmlinuz
    + append initrd=initrd.img ip=dhcp inst.repo=http://10.10.10.10/rhel7 ks=http://10.10.10.10/rhel7/ks.cfg
- For UEFI-based tftp setup:
  + Add a configuration file named grub.cfg to the uefi/ directory: vi /var/lib/tftpboot/uefi/grub.cfg 
    + set timeout=60
  + The following example is for a RHEL7 entry in grub.cfg file. However, the PXE Test Suite will edit this file, so it's not required to add these lines.
    + menuentry 'RHEL 7' {
    + linuxefi uefi/vmlinuz ip=dhcp inst.repo=http://10.10.10.10/rhel7 ks=http://10.10.10.10/rhel7/ks.cfg
    + initrdefi uefi/initrd.img
    + }
- Make sure the http server is configured correctly: vi /etc/httpd/conf/httpd.conf
  + ServerRoot "/etc/httpd"
  + Listen 80
  + Include conf.modules.d/*.conf
  + IncludeOptional conf.d/*.conf
- Start all the required services: systemctl start xinetd.service dhcpd.service tftp.service httpd.service
- Set up the required services for automatic start at boot: systemctl enable xinetd.service dhcpd.service tftp.service httpd.service
- At this point the PXE server should be ready for beeing used within PXE Test Suite