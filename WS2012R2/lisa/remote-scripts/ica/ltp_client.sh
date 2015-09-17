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
# SCRIPT DESCRIPTION: This script will setup LTP for network tests on
# both server and client.
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

function install_ltp {
    echo "Creating ltp directory"
    test -d "$TOP_SRCDIR" || mkdir -p "$TOP_SRCDIR"
    cd $TOP_SRCDIR

    echo "Clone from Git"
    git clone https://github.com/linux-test-project/ltp.git
    TOP_SRCDIR="$HOME/src/ltp"

    echo "Configuring LTP"
    cd $TOP_SRCDIR
    make autotools

    echo "Creating build directory"
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
}

function setup_variables {
    sed -i -e 's|test_net.sh|/opt/ltp/testcases/bin/test_net.sh|g' /opt/ltp/testscripts/network.sh
    sed -i -e 's|test.sh|/opt/ltp/testcases/bin/test.sh|g' /opt/ltp/testcases/bin/test_net.sh
    sed -i -e 's|${RHOST:-""}|${RHOST:-"'$SERVER_IP'"}|g' /opt/ltp/testscripts/network.sh
    sed -i -e 's|${PASSWD:-""}|${PASSWD:-"'$SERVER_PASSWORD'"}|g' /opt/ltp/testscripts/network.sh
    sed -i -e 's|${IPV4_NETWORK:-"10.0.0"}|${IPV4_NETWORK:-"'${IP_ARR[0]}'.'${IP_ARR[1]}'.'${IP_ARR[2]}'"}|g' /opt/ltp/testscripts/network.sh
    sed -i -e 's|${LHOST_IPV4_HOST:-"2"}|${LHOST_IPV4_HOST:-"'${HOST_ARR[3]}'"}|g' /opt/ltp/testscripts/network.sh
    sed -i -e 's|${RHOST_IPV4_HOST:-"1"}|${RHOST_IPV4_HOST:-"'${IP_ARR[3]}'"}|g' /opt/ltp/testscripts/network.sh
    sed -i -e 's|${IPV4_NET_REV:-"0.0.10"}|${IPV4_NET_REV:-"'${IP_ARR[2]}'.'${IP_ARR[1]}'.'${IP_ARR[0]}'"}|g' /opt/ltp/testscripts/network.sh
    sed -i -e 's|= yes|= no|g' /etc/xinetd.d/echo
    sed -i -e 's|= yes|= no|g' /etc/xinetd.d/echo-dgram
    sed -i -e 's|= yes|= no|g' /etc/xinetd.d/echo-stream
    sed -i -e 's|if \[ "\$(rsh -n -l root \$RHOST pgrep -x rwhod)" == "" \]; then|rsh -n -l root \$RHOST pgrep -x rwhod \n if \[ \$\? -ne 0 \]; then|g' /opt/ltp/testcases/bin/rwho01

}

function setup_scripts {
    echo "$HOST_IP `hostname`" >> /etc/hosts
    sed -i '/127.0.1.1/d' /etc/hosts
    sed -i -e 's|restart_daemon|restart|g' /opt/ltp/testcases/bin/xinetd_tests.sh
    sed -i -e 's|$(dirname "$i") == "."|$(dirname "$i") = "."|g' /opt/ltp/testcases/bin/rdist01
    sed -i -e 's/init || exit $?/init || exit $? \n. test.sh/g' /opt/ltp/testcases/bin/xinetd_tests.sh
    echo "ALL: 127.0.0.1" >> /etc/hosts.allow
    echo "ALL: 127.0.1.1" >> /etc/hosts.allow
    echo "ALL: $HOST_IP" >> /etc/hosts.allow
    echo "/ $SERVER_IP(rw,no_subtree_check,no_root_squash)" >> /etc/exports
    echo "rsh" >> /etc/securetty
    echo "rexec" >> /etc/securetty
    echo "rlogin" >> /etc/securetty
    echo "telnet" >> /etc/securetty
    echo "ftp" >> /etc/securetty
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

function verify_install(){
    if [ $1 -eq 0 ]; then
        echo "$2 was successfully installed." >> packets.log
    else
        echo "Error: failed to install $2" >> packets.log
    fi
}

function config_rsh_fedora {
    echo "Setting up rsh" >> steps.log
    cp ~/.ssh/$SSH_PRIVATE_KEY ~/.ssh/id_rsa
    SSH_PRIVATE_KEY=$SSH_PRIVATE_KEY.pub
    cp ~/.ssh/$SSH_PRIVATE_KEY ~/.ssh/id_rsa.pub
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


TOP_BUILDDIR="/opt/ltp"
TOP_SRCDIR="$HOME/src"

SERVER_IP=$1
SERVER_PASSWORD=$2
SERVER_USERNAME=$3
CLIENT_PASSWORD=$4 
SSH_PRIVATE_KEY=$5 

HOST_IP=$(ip addr show dev eth0 | grep "inet " | awk {'print $2'} | rev | cut -c 4- | rev)
IP_ARR=(${SERVER_IP//./ })
HOST_ARR=(${HOST_IP//./ })

#
# Copy server side scripts and trigger server side scripts
#
echo "Setting up server side..." >> steps.log

chmod +x ltp_server.sh

echo "Copy file to server" >> steps.log
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ~/ltp_server.sh ${SERVER_USERNAME}@[${SERVER_IP}]:
if [ $? -ne 0 ]; then
    msg="Error: Unable to copy test scripts to target server machine: ${LTP_SERVER_IP}. scp command failed."
    echo "${msg}" >> ~/steps.log
    exit 120
fi


echo "Installing and configuring ltp on server" >> steps.log
ssh -f -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ${SERVER_USERNAME}@${SERVER_IP} "~/ltp_server.sh $HOST_IP $CLIENT_PASSWORD"
if [ $? -ne 0 ]; then
    msg="Error: Unable to start LTP server scripts on the target server machine"
    echo "${msg}" >> ~/steps.log
    exit 130
fi


if is_fedora ; then
    echo "Starting the configuration..."
    PACK_LIST=(autoconf automake m4 libaio-devel libattr1 libcap-devel gd bison flex make gcc git xinetd tcpdump rsh finger-server rsh-server rusers rusers-server telnet-server rdist rsync telnet nfs-utils nfs-utils-lib rwho expect dnsmasq traceroute dhcp httpd vsftpd exportfs nfs-utils nfs4-acl-tools portmap virt-who ftp)
    for item in ${PACK_LIST[*]}
    do
        echo "Starting to install $item... "
        yum install $item -y 
        verify_install $? $item   
    done

    # waiting for server to finish the setup
    sleep 120

    echo "Installing LTP on client" >> steps.log
    install_ltp

    echo "Creating .rhosts file" >> steps.log
    echo $SERVER_IP >> /root/.rhosts

    echo "Set PATH for testcases" >> steps.log
    PATH=$PATH:/opt/ltp/testcases/bin

    echo "Setting up variables" >> steps.log
    setup_variables

    echo "Settup scrips and daemons" >> steps.log
    setup_scripts
 
    echo "Setting up rsh"
    config_rsh_fedora

    echo "Setting up telnet"
    config_telnet_fedora

    echo "Setting up finger"
    config_finger_fedora

    echo "Starting required services"
    services_start_fedora


elif is_ubuntu ; then
    echo "Starting the configuration..." >> steps.log
    
    PACK_LIST=(autoconf automake m4 libaio-dev libattr1 libcap-dev bison libdb4.8 libberkeleydb-perl flex make gcc git xinetd tcpdump rsh-server finger rdist rsync isc-dhcp-server apache2 rusersd rstat-client rusers rstatd nfs-common nfs-kernel-server cfingerd rwhod rwho expect dnsmasq traceroute telnetd)
    for item in ${PACK_LIST[*]}
    do
        echo "Starting to install $item... "
        apt-get install $item -y 
        verify_install $? $item   

    done

    # waiting for server to finish the setup
    sleep 120

    echo "Installing LTP on client" >> steps.log
    install_ltp

    echo "Creating .rhosts file" >> steps.log
    echo $SERVER_IP >> /root/.rhosts

    echo "Set PATH for testcases" >> steps.log
    PATH=$PATH:/opt/ltp/testcases/bin

    echo "Setting up variables" >> steps.log
    setup_variables

    echo "Settup scrips and daemons" >> steps.log
    setup_scripts
    services_start_ubuntu
    
    echo "Setting up rsh" >> steps.log
    cp ~/.ssh/$SSH_PRIVATE_KEY ~/.ssh/id_rsa
    SSH_PRIVATE_KEY=$SSH_PRIVATE_KEY.pub
    cp ~/.ssh/$SSH_PRIVATE_KEY ~/.ssh/id_rsa.pub

elif is_suse ; then
    # not supported
    echo "SUSE"
fi