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
# SCRIPT DESCRIPTION: This script will setup LTP for network tests.
# This script is called remotely from client.
#
################################################################

declare os_VENDOR os_RELEASE os_UPDATE os_PACKAGE os_CODENAME

########################################################################
# Determine what OS is running
########################################################################
# GetOSVersion
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
        os_RELEASE=$(lsb_release -r -s)
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
        # Red Hat Enterprise Linux Server release 5.5 (Tikanga)
        # Red Hat Enterprise Linux Server release 7.0 Beta (Maipo)
        # CentOS release 5.5 (Final)
        # CentOS Linux release 6.0 (Final)
        # Fedora release 16 (Verne)
        # XenServer release 6.2.0-70446c (xenenterprise)
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
    # If lsb_release is not installed, we should be able to detect Debian OS
    elif [[ -f /etc/debian_version ]] && [[ $(cat /proc/version) =~ "Debian" ]]; then
        os_VENDOR="Debian"
        os_PACKAGE="deb"
        os_CODENAME=$(awk '/VERSION=/' /etc/os-release | sed 's/VERSION=//' | sed -r 's/\"|\(|\)//g' | awk '{print $2}')
        os_RELEASE=$(awk '/VERSION_ID=/' /etc/os-release | sed 's/VERSION_ID=//' | sed 's/\"//g')
    fi
    export os_VENDOR os_RELEASE os_UPDATE os_PACKAGE os_CODENAME
}

########################################################################
# Determine if current distribution is a Fedora-based distribution
########################################################################
function is_fedora {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "Fedora" ] || [ "$os_VENDOR" = "Red Hat" ] || \
        [ "$os_VENDOR" = "CentOS" ] || [ "$os_VENDOR" = "OracleServer" ]
}

########################################################################
# Determine if current distribution is a SUSE-based distribution
########################################################################
function is_suse {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "openSUSE" ] || [ "$os_VENDOR" = "SUSE LINUX" ]
}

########################################################################
# Determine if current distribution is an Ubuntu-based distribution
########################################################################
function is_ubuntu {
    if [[ -z "$os_PACKAGE" ]]; then
        GetOSVersion
    fi
    [ "$os_PACKAGE" = "deb" ]
}


function verify_install(){
    if [ $1 -eq 0 ]; then
        echo "$2 was successfully installed." >> summary.log
    else
        echo "Error: failed to install $2" >> summary.log
    fi
}


function install_packages(){
    echo "Installing packages"

    PACK_LIST=(autoconf automake m4 libaio-dev libattr1 libcap-dev bison libdb4.8 libberkeleydb-perl flex make gcc git telnetd xinetd rusersd rusers rstatd nfs-common nfs-kernel-server rwho rwhod cfingerd rdist telnet apache2 expect finger ftp rsync rsyslog traceroute rsh-server tcpdump)
    for item in ${PACK_LIST[*]}
    do
        echo "Starting to install $item... "
        apt-get install $item -y
        verify_install $? $item
    done
    echo "Done installing packets"
}

function configure_ltp_server() {
    echo "Configuring LTP NET Server"

    ip_addr=$(ip addr show dev eth0 | grep "inet " | awk {'print $2'} | rev | cut -c 4- | rev)
    netmask=$(ifconfig eth0 | grep "Mask" | awk '{print $4}' | cut -c 6-)
    host_name="ltp-server"
    current_hostname=$(hostname)
    hostnamectl  set-hostname ${host_name}
    sed -i "s/$current_hostname/$host_name/g" /etc/hosts
    echo "${ip_addr} ${host_name}" >> /etc/hosts
    server_fqdn=$host_name
    client_ip=$1
    password=$2
    echo "$1" >> /root/.rhosts
    echo "rsh" >> /etc/securetty
    echo "rexec" >> /etc/securetty
    echo "rlogin" >> /etc/securetty
    echo "telnet" >> /etc/securetty
    echo "ftp" >> /etc/securetty
    echo "machine ${server_fqdn} login root password $2" >> /root/.netrc
    echo "/ ${ip_addr}(rw,no_root_squash,sync)" >> /etc/exports
    echo "ALL: 127.0.0.1" >> /etc/hosts.allow
    echo "ALL: 127.0.1.1" >> /etc/hosts.allow
    echo "ALL: $ip_addr" >> /etc/hosts.allow
    sed -i -e 's|= yes|= no|g' /etc/xinetd.d/echo
    sed -i -e "s/.*pam_securetty.so/#auth [success=ok new_authtok_reqd=ok ignore=ignore user_unknown=bad default=die] pam_securetty.so/g" /etc/pam.d/login
    sed -i -e 's|= yes|= no|g' /etc/xinetd.d/echo-dgram
    sed -i -e 's|= yes|= no|g' /etc/xinetd.d/echo-stream
    sed -i -e "s|.*pam_securetty.so|#auth       required     pam_securetty.so|g" /etc/pam.d/remote
    echo "Done configuring the server"
}

function install_ltp(){
    
    TOP_BUILDDIR="/opt/ltp"
    TOP_SRCDIR="$HOME/src"
    echo "Creating working directory"
    test -d "$TOP_SRCDIR" || mkdir -p "$TOP_SRCDIR"
    cd $TOP_SRCDIR
    echo "Cloning LTP"
    git clone https://github.com/linux-test-project/ltp.git
    TOP_SRCDIR="$HOME/src/ltp"
    echo "Configuring LTP"
    cd $TOP_SRCDIR
    make autotools
    echo "Creating bild directory"
    test -d "$TOP_BUILDDIR" || mkdir -p "$TOP_BUILDDIR"
    cd $TOP_BUILDDIR && "$TOP_SRCDIR/configure"
    cd "$TOP_SRCDIR"
    ./configure
    echo "Compiling LTP"
    make all
    if [ $? -gt 0 ]; then
        echo "Failed to compile LTP"
        exit 10
    fi
    echo "Installing LTP"
    make install
    if [ $? -gt 0 ]; then
            echo "Failed to install LTP"
            exit 10
    fi
    echo "LTP successfully installed."
}

function services_start_ubuntu {
    service xinetd restart
    rpc.rstatd start
    exportfs -ra
    service nfs-kernel-server restart
    service rpcbind restart
}

function services_start_fedora {
    chkconfig finger on
    chkconfig rsh on
    chkconfig rlogin on
    chkconfig rexec on
    chkconfig rstatd on
    chkconfig rusersd on
    chkconfig nfs-server on

    service xinetd restart
    service rstatd restart
    service nfs restart
    exportfs -ra
    service rpcbind restart
    service rusersd restart
    service rwhod restart
    service virt-who start

    systemctl restart rsh.socket
    systemctl restart rlogin.socket
    systemctl restart rexec.socket
}

function config_rsh_fedora {
    echo "Setting up rsh"
    echo "service shell
{
        disable = no
        socket_type = stream
        wait = no
        user = root
        log_on_success += USERID
        log_on_failure += USERID
        server = /usr/sbin/in.rshd
}" >> /etc/xinetd.d/rsh

    iptables -F
    setenforce 0
}

function config_telnet_fedora {
    echo "service telnet
{
        flags           = REUSE
        socket_type     = stream
        wait            = no
        user            = root
        server          = /usr/sbin/in.telnetd
        log_on_failure  += USERID
        disable         = no
}" >> /etc/xinetd.d/telnet
}

function config_finger_fedora {
    echo "service finger
{
        socket_type = stream
        wait  = no
        user  = nobody
        server  = /usr/sbin/in.fingerd
        disable  = no
}" >> /etc/xinetd.d/finger
}
#######################################################################
#
# Main script body
#
#######################################################################

HOST_IP=$1
HOST_PASSWORD=$2

if is_fedora ; then
    echo "FEDORA"
    echo "Starting the configuration..."
    PACK_LIST=(autoconf automake m4 libaio-devel libattr1 libcap-devel bison flex make gcc git xinetd tcpdump rsh finger-server rusers rusers-server rsh-server gd telnet-server rdist rsync telnet nfs-utils nfs-utils-lib rwho expect dnsmasq traceroute dhcp httpd vsftpd exportfs nfs-utils nfs4-acl-tools portmap virt-who ftp)
    for item in ${PACK_LIST[*]}
    do
        echo "Starting to install $item... "
        yum install $item -y 
        verify_install $? $item   
    done

    configure_ltp_server $HOST_IP $HOST_PASSWORD
    config_rsh_fedora
    config_finger_fedora
    config_telnet_fedora
    install_ltp
    services_start_fedora
   
elif is_ubuntu ; then
    install_packages
    configure_ltp_server $HOST_IP $HOST_PASSWORD
    install_ltp

elif is_suse ; then
    # not supported
    echo "SUSE"
fi