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

########################################################################
#
# This script prepares the test environment for the VM:
# - turns off firewall/ Network Manager
# - turns off SELinux
# - registers the system (RedHat and SUSE only)
# - installs packages for each distribution
# - installs stressapptest and stress-ng
# - sets up SSH keys
#
# How to run:
# Place this script and your public and authorized keys in /root/ then
# run the script. 
#
#   ./aio.sh
#
# If you run the script on RedHat or SUSE, pass the registration 
# username and password to the script.
#
#   ./aio.sh "your_username" "your_password"
#
########################################################################

declare os_VENDOR os_RELEASE os_UPDATE os_PACKAGE os_CODENAME

stressapptest_githubLink=https://github.com/stressapptest/stressapptest.git

stressng_githubLink=https://github.com/ColinIanKing/stress-ng
stressng_version=V0.07.16

bzip2_version=bzip2-1.0.3
bzip2_archive=$bzip2_version.tar.gz
bzip2_downloadLink=bzip.org/1.0.3/$bzip2_archive

keyutils_version=keyutils-1.5.9
keyutils_archive=$keyutils_version.tar.bz2
keyutils_downloadLink=https://build.opensuse.org/source/security/keyutils/$keyutils_archive

work_directory=/tmp/lisa

########################################################################
#
# Determine what OS is running
#
########################################################################
function GetOSVersion {
    # Figure out which vendor we are
    if [[ -x "`which sw_vers 2>/dev/null`" ]]; then
        # OS/X
        os_VENDOR=`sw_vers -productName`
        os_RELEASE=`sw_vers -productVersion`
        os_UPDATE=${os_RELEASE##*.}
        os_RELEASE=${os_RELEASE%.*}
        os_PACKAGE=""
        if [[ "$os_RELEASE" =~ "10.7" ]]; then
            os_CODENAME="lion"
        elif [[ "$os_RELEASE" =~ "10.6" ]]; then
            os_CODENAME="snow leopard"
        elif [[ "$os_RELEASE" =~ "10.5" ]]; then
            os_CODENAME="leopard"
        elif [[ "$os_RELEASE" =~ "10.4" ]]; then
            os_CODENAME="tiger"
        elif [[ "$os_RELEASE" =~ "10.3" ]]; then
            os_CODENAME="panther"
        else
            os_CODENAME=""
        fi
    elif [[ -x $(which lsb_release 2>/dev/null) ]]; then
        os_VENDOR=$(lsb_release -i -s)
        os_RELEASE=$(lsb_release -r -s | head -c 1)
        os_UPDATE=""
        os_PACKAGE="rpm"
        if [[ "Debian,Ubuntu,LinuxMint" =~ $os_VENDOR ]]; then
            os_PACKAGE="deb"
        elif [[ "SUSE LINUX" =~ $os_VENDOR ]]; then
            lsb_release -d -s | grep -q openSUSE
            if [[ $? -eq 0 ]]; then
                os_VENDOR="openSUSE"
            fi
        elif [[ $os_VENDOR == "openSUSE project" ]]; then
            os_VENDOR="openSUSE"
        elif [[ $os_VENDOR =~ Red.*Hat ]]; then
            os_VENDOR="Red Hat"
        fi
        os_CODENAME=$(lsb_release -c -s)
    elif [[ -r /etc/redhat-release ]]; then

        #
        # Red Hat Enterprise Linux Server release 5.5 (Tikanga)
        # Red Hat Enterprise Linux Server release 7.0 Beta (Maipo)
        # CentOS release 5.5 (Final)
        # CentOS Linux release 6.0 (Final)
        # Fedora release 16 (Verne)
        # XenServer release 6.2.0-70446c (xenenterprise)
        #
        os_CODENAME=""
        for r in "Red Hat" CentOS Fedora XenServer; do
            os_VENDOR=$r
            if [[ -n "`grep \"$r\" /etc/redhat-release`" ]]; then
                ver=`sed -e 's/^.* \([0-9].*\) (\(.*\)).*$/\1\|\2/' /etc/redhat-release`
                os_CODENAME=${ver#*|}
                os_RELEASE=${ver%|*}
                os_UPDATE=${os_RELEASE##*.}
                os_RELEASE=${os_RELEASE%.*}
                break
            fi
            os_VENDOR=""
        done
        os_PACKAGE="rpm"
    elif [[ -r /etc/SuSE-release ]]; then
        for r in openSUSE "SUSE Linux"; do
            if [[ "$r" = "SUSE Linux" ]]; then
                os_VENDOR="SUSE LINUX"
            else
                os_VENDOR=$r
            fi

            if [[ -n "`grep \"$r\" /etc/SuSE-release`" ]]; then
                os_CODENAME=`grep "CODENAME = " /etc/SuSE-release | sed 's:.* = ::g'`
                os_RELEASE=`grep "VERSION = " /etc/SuSE-release | sed 's:.* = ::g'`
                os_UPDATE=`grep "PATCHLEVEL = " /etc/SuSE-release | sed 's:.* = ::g'`
                break
            fi
            os_VENDOR=""
        done
        os_PACKAGE="rpm"
    
    #
    # If lsb_release is not installed, we should be able to detect Debian OS
    #
    elif [[ -f /etc/debian_version ]] && [[ $(cat /proc/version) =~ "Debian" ]]; then
        os_VENDOR="Debian"
        os_PACKAGE="deb"
        os_CODENAME=$(awk '/VERSION=/' /etc/os-release | sed 's/VERSION=//' | sed -r 's/\"|\(|\)//g' | awk '{print $2}')
        os_RELEASE=$(awk '/VERSION_ID=/' /etc/os-release | sed 's/VERSION_ID=//' | sed 's/\"//g')
    fi
    export os_VENDOR os_RELEASE os_UPDATE os_PACKAGE os_CODENAME
}

########################################################################
#
# Determine if current distribution is a Fedora-based distribution
#
########################################################################
function is_fedora {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "Fedora" ] || [ "$os_VENDOR" = "Red Hat" ] || \
        [ "$os_VENDOR" = "CentOS" ] || [ "$os_VENDOR" = "OracleServer" ]
}

########################################################################
#
# Determine if current distribution is a SUSE-based distribution
#
########################################################################
function is_suse {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "openSUSE" ] || [ "$os_VENDOR" = "SUSE LINUX" ]
}

########################################################################
#
# Determine if current distribution is an Ubuntu-based distribution
#
########################################################################
function is_ubuntu {
    if [[ -z "$os_PACKAGE" ]]; then
        GetOSVersion
    fi
    [ "$os_PACKAGE" = "deb" ]
}

########################################################################
#
# Determine if keys were successfully copied
#
########################################################################
function copy_check (){
    if [ $? == 0 ] ; then
        echo "$1 successfully copied $2" >> summary.log
    else
        echo "ERROR: $1 failed copy $2" >> summary.log
fi

}

########################################################################
#
# Set up SSH keys
#
########################################################################
function rsa_keys(){
    cd /root/
    if [ ! -d /root/.ssh ] ; then
        mkdir /root/.ssh
        echo "/root/.ssh was created" >> summary.log
    else
        echo "/root/.ssh folder already exists" >> summary.log
    fi

    file=$(echo $1 | grep -oP "[a-zA-Z-_0-9]*")

    cp $file /root/.ssh/
    copy_check $file

    cp $file".pub" /root/.ssh/
    copy_check $file".pub"

    cat $file".pub" > /root/.ssh/authorized_keys
    copy_check $file".pub" "in authorized_keys"
    chmod 600 /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/$file
    chmod 700 .ssh
}

########################################################################
#
# Set up SSH
#
########################################################################
function configure_ssh(){
    echo "Uncommenting #Port 22..."
    sed -i -e 's/#Port/Port/g' /etc/ssh/sshd_config
    if [ $? -eq 0 ]
    then
        echo "Uncomment Port succeeded." >> summary.log
    else
        echo "Error: Uncomment #Port failed." >> summary.log
    fi

    echo "Uncommenting #Protocol 2..."
    sed -i -e 's/#Protocol/Protocol/g' /etc/ssh/sshd_config
    if [ $? -eq 0 ]
    then
        echo "Uncomment Protocol succeeded." >> summary.log
    else
        echo "Error: Uncomment #Protocol failed." >> summary.log
    fi

    echo "Uncommenting #PermitRootLogin..."
    sed -i -e 's/#PermitRootLogin/PermitRootLogin/g' /etc/ssh/sshd_config
    if [ $? -eq 0 ]
    then
        echo "Uncomment #PermitRootLogin succeeded." >> summary.log
    else
        echo "Error: Uncomment #PermitRootLogin failed." >> summary.log
    fi

    echo "Uncommenting RSAAuthentication..."
    sed -i -e 's/#RSAAuthentication/RSAAuthentication/g' /etc/ssh/sshd_config
    if [ $? -eq 0 ]
    then
        echo "Uncomment #RSAAuthentication succeeded." >> summary.log
    else
        echo "Error: Uncomment #RSAAuthentication failed." >> summary.log
    fi

    echo "Uncommenting PubkeyAuthentication..."
    sed -i -e 's/#PubkeyAuthentication/PubkeyAuthentication/g' /etc/ssh/sshd_config
    if [ $? -eq 0 ]
    then
        echo "Uncomment #PubkeyAuthentication succeeded." >> summary.log
    else
        echo "Error: Uncomment #PubkeyAuthentication failed." >> summary.log
    fi

    echo "Uncommenting AuthorizedKeysFile..."
    sed -i -e 's/#AuthorizedKeysFile/AuthorizedKeysFile/g' /etc/ssh/sshd_config
    if [ $? -eq 0 ]
    then
        echo "Uncomment #AuthorizedKeysFile succeeded." >> summary.log
    else
        echo "Error: Uncomment #AuthorizedKeysFile failed." >> summary.log
    fi

    echo "Uncommenting PasswordAuthentication..."
    sed -i -e 's/#PasswordAuthentication/PasswordAuthentication/g' /etc/ssh/sshd_config
    if [ $? -eq 0 ]
    then
        echo "Uncomment #PasswordAuthentication succeeded." >> summary.log
    else
        echo "Error: Uncomment #PasswordAuthentication failed." >> summary.log
    fi

    echo "Allow root login..."
    sed -i -e 's/PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config
}

########################################################################
#
# Function which verifies if an install was successfull
#
########################################################################
function verify_install (){
    if [ $1 -eq 0 ]; then
        echo "$2 was successfully installed." >> summary.log
    else
        echo "Error: failed to install $2" >> summary.log
    fi
}

########################################################################
#
# Install stressapp test
#
########################################################################
function install_stressapptest(){
    echo "Installing stressapptest..." >> summary.log
    
    if [ ! -d $work_directory ] ; then
        mkdir $work_directory
    fi
    
    git clone $stressapptest_githubLink $work_directory/stressapptest
    cd $work_directory/stressapptest
    ./configure
    make
    make install
    verify_install $? stressapptest
    cd ~
}

########################################################################
#
# Install stress-ng
#
########################################################################
function install_stress_ng(){
    echo "Installing stress-ng..." >> summary.log

    if [ ! -d $work_directory ] ; then
        mkdir $work_directory
    fi
    
    git clone $stressng_githubLink $work_directory/stress-ng
    cd $work_directory/stress-ng
    git checkout tags/$stressng_version
    make
    make install
    verify_install $? Stress
    cd ~
}

########################################################################
#
# Add crashkernel parameter to grub
#
########################################################################
function configure_grub(){
    echo "Configuring GRUB..." >> summary.log
    if is_ubuntu ; then
        sed -i -e 's/DEFAULT=""/DEFAULT="console=tty0 console=ttyS1 crashkernel=256M@128M"/g' /etc/default/grub
        update-grub
    elif is_fedora ; then
        if [ $os_RELEASE -eq 7 ] ; then
            sed -i -e 's/crashkernel=auto/crashkernel=256M@128M console=tty0 console=ttyS1/g' /etc/default/grub
            perl -pi -e "s/quiet//g" /etc/default/grub
            grub2-mkconfig -o /etc/grub2.cfg
        elif [ $os_RELEASE -eq 6 ] ; then
            sed -i -e 's/crashkernel=auto/crashkernel=256M@128M console=tty0 console=ttyS1/g' /boot/grub/grub.conf
            perl -pi -e "s/quiet//g" /boot/grub/grub.conf
        fi
    elif is_suse ; then
        if [ $os_RELEASE -eq 12 ] ; then
            sed -i -e 's/218M-:109M/256M@128M console=tty0 console=ttyS1/g' /etc/default/grub
            perl -pi -e "s/quiet//g" /etc/default/grub
            grub2-mkconfig -o /etc/grub2.cfg
        elif [ $os_RELEASE -eq 11 ] ; then
            sed -i -e 's/256M-:128M/256M@128M console=tty0 console=ttyS1/g' /boot/grub/menu.lst
            perl -pi -e "s/splash=silent//g" /boot/grub/menu.lst
        fi
    fi
}

########################################################################
#
# Create script to remove net udev rules at shutdown
#
########################################################################
function remove_udev(){
    echo "#!/bin/bash" >> /etc/init.d/remove_udev
    echo "rm -rf /etc/udev/rules.d/70-persistent-net.rules" >> /etc/init.d/remove_udev
    chmod 775 /etc/init.d/remove_udev
    if is_suse ; then
        ln -s /etc/init.d/remove_udev /etc/init.d/rc0.d/S00remove_udev
        if [ $? -ne 0 ]; then
            ln -s /etc/init.d/remove_udev /etc/rc.d/rc0.d/S00remove_udev
        fi
    else
        ln -s /etc/init.d/remove_udev /etc/rc0.d/S00remove_udev
    fi
}

########################################################################
#Check if commands execute correctly
########################################################################
function check_exec(){
    $1 --help > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        echo $?
    else
        echo "Could not execute command"
    fi
}

#######################################################################
#
# Main script body
#
#######################################################################
if is_fedora ; then
    echo "Starting the configuration..."
    chkconfig irqbalance off
    chkconfig iptables off
    chkconfig ip6tables off
    if [ $? == 0 ] ; then
        echo "iptables turned off" >> summary.log
    else
        echo "ERROR: iptables cannot be turned off" >> summary.log
    fi
    
    #
    # Removing /var/log/messages
    #
    rm -f /var/log/messages
    
    if [ $os_RELEASE -eq 6 ]; then
        echo "Changing ONBOOT..."
        sed -i -e 's/ONBOOT=no/ONBOOT=yes/g' /etc/sysconfig/network-scripts/ifcfg-eth0
        echo "Turning off selinux..."
        echo 0 > /selinux/enforce
        echo "selinux=0" >> /boot/grub/grub.conf
        sed -i -e 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    fi

    echo "Registering the system..." >> summary.log

    if [ $# -ne 2 ]; then
        echo "ERRROR: Incorrect number of arguments!" >> summary.log
        echo "Usage: ./AIO.sh username password" >> summary.log
    fi
    username=$1
    password=$2

    echo "os_RELEASE: $os_RELEASE" >> summary.log
    echo "os_UPDATE: $os_UPDATE" >> summary.log
    rhnreg_ks --username $username --password $password
    if [ $? -ne 0 ]; then
        subscription-manager register --username $username --password $password
        subscription-manager attach --auto
    fi

    x=$(cat /etc/sysctl.conf | grep net.ipv6.conf.all.disable_ipv6)
    if [[ $x ]]; then
        sed -i -e 's/net.ipv6.conf.all.disable_ipv6 = 1/net.ipv6.conf.all.disable_ipv6 = 0/g' /etc/sysctl.conf
    else
        echo "net.ipv6.conf.all.disable_ipv6 = 0" >> /etc/sysctl.conf
    fi

    x=$(cat /etc/sysctl.conf | grep net.ipv6.conf.default.disable_ipv6)
    if [[ $x ]]; then
        sed -i -e 's/net.ipv6.conf.default.disable_ipv6 = 1/net.ipv6.conf.default.disable_ipv6 = 0/g' /etc/sysctl.conf
    else
        echo "net.ipv6.conf.default.disable_ipv6 = 0" >> /etc/sysctl.conf
    fi

    x=$(cat /etc/sysctl.conf | grep net.ipv6.conf.lo.disable_ipv6)
    if [[ $x ]]; then
        sed -i -e 's/net.ipv6.conf.lo.disable_ipv6 = 1/net.ipv6.conf.lo.disable_ipv6 = 0/g' /etc/sysctl.conf
    else
        echo "net.ipv6.conf.lo.disable_ipv6 = 0" >> /etc/sysctl.conf
    fi

    echo "Shutting down Network Manager on RHEL 6.x/7.x"
    if [ $os_RELEASE -eq 7 ] || [ $os_RELEASE -eq 6 ]; then
        service NetworkManager stop
        if [ $? -ne 0 ]; then
            echo "ERROR: Network Manager service didn't stop" >> summary.log
        fi
        chkconfig NetworkManager off
        service network start
        if [ $? -ne 0 ]; then
            echo "ERROR: Network service didn't start" >> summary.log
        fi
        chkconfig network on
    fi

    echo "Installing packages..." >> summary.log
    PACK_LIST=(openssh-server dos2unix at net-tools gpm bridge-utils btrfs-progs xfsprogs ntp crash bc dosfstools 
    selinux-policy-devel libaio-devel libattr-devel keyutils-libs-devel gcc gcc-c++ autoconf automake nano parted
    kexec-tools device-mapper-multipath expect sysstat git wget mdadm bc numactl python3 nfs-utils omping nc 
    pciutils squashfs-tools)
    for item in ${PACK_LIST[*]}
    do
        echo "Starting to install $item... "
        yum install $item -y
        verify_install $? $item
    done
    yum groups mark install "Development Tools"
    yum groups mark convert "Development Tools"
    yum -y groupinstall "Development Tools"
    verify_install $? "Development Tools"
    
    if [ ! -d $work_directory ] ; then
        mkdir $work_directory
    fi
    wget -O $work_directory/$bzip2_archive $bzip2_downloadLink
    tar zxvf $work_directory/$bzip2_archive -C $work_directory/
    cd $work_directory/$bzip2_version
    make install
    cd ~
    install_stressapptest
    
    if [ -e /boot/efi ]; then
        mkdir /boot/efi/EFI/boot/
        cp /boot/efi/EFI/redhat/grub.efi /boot/efi/EFI/boot/bootx64.efi
        cp /boot/efi/EFI/redhat/grub.conf /boot/efi/EFI/boot/bootx64.conf
        
    fi

elif is_ubuntu ; then
    echo "Starting the configuration..."
    echo "Disable IPv6 for apt-get"
    echo "Acquire::ForceIPv4 "true";" > /etc/apt/apt.conf.d/99force-ipv4
    
    #
    # Removing /var/log/syslog
    #
    rm -f /var/log/syslog*

    #
    # Because Ubuntu has a 100 seconds delay waiting for a new network interface,
    # we're disabling the delays in order to not conflict with the automation
    #
    sed -i -e 's/sleep 40/#sleep 40/g' /etc/init/failsafe.conf
    sed -i -e 's/sleep 59/#sleep 59/g' /etc/init/failsafe.conf
    PACK_LIST=(kdump-tools openssh-server tofrodos dosfstools dos2unix ntp gcc open-iscsi iperf gpm vlan iozone3 at 
    multipath-tools expect zip libaio-dev make libattr1-dev stressapptest git wget mdadm automake libtool pkg-config
    bridge-utils btrfs-tools libkeyutils-dev xfsprogs reiserfsprogs sysstat build-essential bc numactl python3 pciutils
    nfs-client parted netcat squashfs-tools linux-cloud-tools-common linux-tools-`uname -r` linux-cloud-tools-`uname -r`)
    for item in ${PACK_LIST[*]}
    do
        echo "Starting to install $item... "
        apt-get install $item -y
        verify_install $? $item
    done

    if [ -e /etc/multipath.conf ]; then
        rm /etc/multipath.conf
    fi
    echo -e "blacklist {\n\tdevnode \"^sd[a-z]\"\n}" >> /etc/multipath.conf
    service multipath-tools restart
    if [ -e /boot/efi ]; then
        cp -r /boot/efi/EFI/ubuntu/ /boot/efi/EFI/boot
        if [ -e /boot/efi/EFI/boot/shimx64.efi ]; then
            mv /boot/efi/EFI/boot/shimx64.efi /boot/efi/EFI/boot/bootx64.efi
        elif [ -e /boot/efi/EFI/boot/grubx64.efi ]; then
            mv /boot/efi/EFI/boot/grubx64.efi /boot/efi/EFI/boot/bootx64.efi
        fi
    fi
    
elif is_suse ; then

    #
    # SLES ISO must be mounted for BETA releases
    #
    chkconfig atd on
    service atd start
    
    #
    # Removing /var/log/messages
    #
    rm -f /var/log/messages
    
    echo "Registering the system..." >> summary.log
    if [ $# -ne 2 ]; then
        echo "ERRROR: Incorrect number of arguments!" >> summary.log
        echo "Usage: ./AIO.sh username password" >> summary.log
    fi
    username=$1
    password=$2

    if [ $os_RELEASE -eq 12 ]; then
        echo "Registering SLES 11" >> summary.log
        SUSEConnect -r $password -e $username

        #
        # Adding repo for SVN
        #
        zypper addrepo http://download.opensuse.org/repositories/devel:tools:scm:svn/SLE_12/devel:tools:scm:svn.repo
        zypper --no-gpg-checks refresh

    elif [ $os_RELEASE -eq 11 ]; then
        echo "Registering SLES 11" >> summary.log
        suse_register -a regcode-sles=$password -a email=$username -L /root/.suse_register.log

        #
        # Adding repo for SVN
        #
        zypper addrepo http://download.opensuse.org/repositories/devel:tools:scm:svn/SLE_11_SP4/devel:tools:scm:svn.repo
        zypper --no-gpg-checks refresh

    else
        echo "ERROR: Unsupported version of SLES!" >> summary.log
    fi

    echo "Installing dependencies for SLES 12" >> summary.log

    #
    # Installing dependencies for stress-ng to work
    # First one needed is keyutils
    #
    wget -O $work_directory/$keyutils_archive $keyutils_downloadLink
    tar -xjvf $work_directory/$keyutils_archive -C $work_directory/
    cd $work_directory/$keyutils_version/
    make
    make install
    cd ~

    PACK_LIST=(at dos2unix dosfstools git-core subversion ntp gcc gcc-c++ wget mdadm expect sysstat bc numactl python3
    nfs-client pciutils libaio-devel parted squashfs-tools)
    for item in ${PACK_LIST[*]}
    do
        echo "Starting to install $item... " >> summary.log
        zypper --non-interactive in $item
        verify_install $? $item
    done

    install_stressapptest
    verify_install $? stressapptest
    if [ -e /boot/efi ]; then
        if [ -e /boot/efi/SuSE ]; then
            cp –r /boot/efi/efi/SuSE/ /boot/efi/EFI/boot
        elif [ -e /boot/efi/opensuse ]; then
            cp –r /boot/efi/efi/opensuse/ /boot/efi/EFI/boot
        fi
        if  [ -e /boot/efi/EFI/BOOT/shim.efi ]; then
            mv /boot/efi/EFI/BOOT/shim.efi /boot/efi/EFI/boot/bootx64.efi
        elif [ -e /boot/efi/EFI/BOOT/grubx64.efi ]; then
            mv /boot/efi/EFI/BOOT/grubx64.efi /boot/efi/EFI/boot/bootx64.efi
        elif [ -e /boot/efi/EFI/BOOT/elilo.efi]; then
            mv /boot/efi/EFI/BOOT/elilo.efi /boot/efi/EFI/boot/bootx64.efi
       
        fi
    fi
fi

install_stress_ng
verify_install $? stress-ng
configure_grub
rsa_keys rhel5_id_rsa
configure_ssh
remove_udev

#remove files from /tmp after install is complete
if [[ $(check_exec stressapptest) -eq 0 && $(check_exec stress-ng) -eq 0 && $(check_exec bzip2) -eq 0 ]] ; then
        rm -rf $work_directory/
fi
