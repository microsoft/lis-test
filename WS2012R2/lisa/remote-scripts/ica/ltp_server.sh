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

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

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
    echo "Starting the configuration..."
    PACK_LIST=(autoconf automake m4 libattr1 bison flex make gcc xinetd nfs-kernel-server rdist telnet apache2 expect finger rsync rsyslog traceroute rsh-server tcpdump git-core finger-server dhcp dnsmasq telnet-server rpcbind lftp)
    for item in ${PACK_LIST[*]}
    do
        echo "Starting to install $item... "
        zypper --non-interactive install $item
        verify_install $? $item
    done
    
    echo "Configure LTP server" >> steps.log
    configure_ltp_server $1 $2

    echo "Installing LTP on client" >> steps.log
    install_ltp

    sed -i -e 's|(login)*|.*login|g' /opt/ltp/testcases/bin/telnet01
    sed -i -e 's|$RUSER@|ltp-server:~|g' /opt/ltp/testcases/bin/telnet01
    sed -i -e 's|(login)*|.*login|g' /opt/ltp/testcases/bin/rlogin01
    sed -i -e 's|$RUSER@|ltp-server:~|g' /opt/ltp/testcases/bin/rlogin01
    sed -i -e 's|}|\t\tdisable = no\n}|g' /etc/xinetd.d/rsh
    sed -i -e 's|}|\t\tdisable = no\n}|g' /etc/xinetd.d/rlogin
    sed -i -e 's|= yes|= no|g' /etc/xinetd.d/telnet
    sed -i -e 's|restart xinetd|service xinetd restart|g' /opt/ltp/testcases/bin/rlogin01

    echo "pts/0">> /etc/securetty
    echo "pts/1">> /etc/securetty
    echo "pts/2">> /etc/securetty
    echo "pts/3">> /etc/securetty

    netmask=$(ifconfig eth0 | grep "Mask" | awk '{print $4}' | cut -c 6-)
    ip_addr=$(ip addr show dev eth0 | grep "inet " | awk {'print $2'} | rev | cut -c 4- | rev)
    echo "/ ${ip_addr}/$netmask(rw,no_root_squash,sync)" >> /etc/exports
    echo "$ip_addr root" >> /root/.rhosts

    chkconfig rsh on
    chkconfig rlogin on
    chkconfig finger on

    service xinetd restart
    service nfs restart
    /sbin/SuSEfirewall2 off
fi