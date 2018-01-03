#!/usr/bin/env bash

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

########################################################################
#
# perf_utils.sh
#
# Description:
#   Handle VM preparations for running performance tests
#
#   Steps:
#   1. setup_sysctl - setting and applying sysctl parameters
#   2. setup_io_scheduler - setting noop i/o scheduler on all disk type devices
# (this is not a permanent change - on reboot it needs to be reapplied)
#   3. setup_ntttcp - downlload and install ntttcp-for-linux
#   4. setup_lagscope - download an install lagscope to monitoring latency
########################################################################

declare -A sysctl_tcp_params=( ["net.core.netdev_max_backlog"]="30000"
                               ["net.core.rmem_default"]="67108864"
                               ["net.core.rmem_max"]="67108864"
                               ["net.core.wmem_default"]="67108864"
                               ["net.core.wmem_max"]="67108864"
                               ["net.ipv4.tcp_wmem"]="8192 12582912 67108864"
                               ["net.ipv4.tcp_rmem"]="8192 12582912 67108864"
                               ["net.ipv4.tcp_max_syn_backlog"]="80960"
                               ["net.ipv4.tcp_slow_start_after_idle"]="0"
                               ["net.ipv4.tcp_tw_reuse"]="1"
                               ["net.ipv4.tcp_abort_on_overflow"]="1"
                               ["net.ipv4.ip_local_port_range"]="10240 65535" )
declare -A sysctl_udp_params=( ["net.core.rmem_default"]="67108864"
                               ["net.core.rmem_max"]="67108864" )
sysctl_file="/etc/sysctl.conf"

function setup_sysctl {
    eval "declare -A sysctl_params="${1#*=}
    for param in "${!sysctl_params[@]}"; do
        grep -q "$param" ${sysctl_file} && \
        sed -i 's/^'"$param"'.*/'"$param"' = '"${sysctl_params[$param]}"'/' ${sysctl_file} || \
        echo "$param = ${sysctl_params[$param]}" >> ${sysctl_file} || return 1
    done
    sysctl -p ${sysctl_file}
    return $?
}

function setup_sysctl {
    sudo sed -i '/DefaultTasksMax/c\DefaultTasksMax=12288' /etc/systemd/system.conf
    for param in "${!sysctl_tcp_params[@]}"; do
        grep -q "$param" ${sysctl_file} && \
        sed -i 's/^'"$param"'.*/'"$param"' = '"${sysctl_tcp_params[$param]}"'/' \
            ${sysctl_file} || \
        echo "$param = ${sysctl_tcp_params[$param]}" >> ${sysctl_file} || return 1
    done
    sysctl -p ${sysctl_file}
    sudo sed -i '/DefaultTasksMax/c\DefaultTasksMax=122880' /etc/systemd/system.conf
    return $?
}
setup_sysctl

# change i/o scheduler to noop on each disk - does not persist after reboot
function setup_io_scheduler {
    sys_disks=( $(lsblk -o KNAME,TYPE -dn | grep disk | awk '{ print $1 }') )
    for disk in "${sys_disks[@]}"; do
        current_scheduler=$(cat /sys/block/${disk}/queue/scheduler)
        if [[ ${current_scheduler} != *"[noop]"* ]]; then
          echo noop > /sys/block/${disk}/queue/scheduler
        fi
    done
    # allow current I/O ops to be executed before the new scheduler is applied
    sleep 5
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "###Setting sysctl params###"
    setup_sysctl "$(declare -p sysctl_tcp_params)"
    if [[ $? -ne 0 ]]
    then
        echo "ERROR: Unable to set sysctl params" >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi
    echo "###Setting elevator to noop###"
    setup_io_scheduler
    if [[ $? -ne 0 ]]
    then
        echo "ERROR: Unable to set elevator to noop." >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi
    echo "Done."
fi

#Install ntttcp-for-linux
function setup_ntttcp {
    if [ "$(which ntttcp)" == "" ]; then
      rm -rf ntttcp-for-linux
      git clone https://github.com/Microsoft/ntttcp-for-linux
      status=$?
      if [ $status -eq 0 ]; then
        echo "ntttcp-for-linux successfully downloaded." >> ~/summary.log
        cd ntttcp-for-linux/src
      else
        echo "ERROR: Unable to download ntttcp-for-linux" >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
        exit 1
      fi
      make && make install
      if [[ $? -ne 0 ]]
      then
        echo "ERROR: Unable to compile ntttcp-for-linux." >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
        exit 1
      fi
      cd /root/
    fi
}

#Install lagscope
function setup_lagscope {
    if [[ "$(which lagscope)" == "" ]]; then
      rm -rf lagscope
      git clone https://github.com/Microsoft/lagscope
      status=$?
      if [ $status -eq 0 ]; then
        echo "Lagscope successfully downloaded." >> ~/summary.log
        cd lagscope/src
      else
        echo "ERROR: Unable to download lagscope." >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
        exit 1
      fi
      make && make install
      if [[ $? -ne 0 ]]
      then
        echo "ERROR: Unable to compile ntttcp-for-linux." >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
        exit 1
      fi
      cd /root/
    fi
}

#Install FIO-tool
function setup_fio {
    FIO=/root/${FILE_NAME}
    if [ ! -e ${FIO} ]; then
        echo "ERROR: Cannot find FIO test source file." >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
        exit 20
    fi
    # Get Root Directory of the archive
    FIODIR=`tar -tvf ${FIO} | head -n 1 | awk -F " " '{print $6}' | awk -F "/" '{print $1}'`
    tar -xvf ${FIO}
    sts=$?
    if [ 0 -ne ${sts} ]; then
        echo "ERROR: Failed to extract the FIO archive!" >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi
    if [ ! ${FIODIR} ]; then
        echo "ERROR: Cannot find FIODIR." >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi
    #Compiling FIO
    cd ${FIODIR}
    ./configure
    sts=$?
    if [ 0 -ne ${sts} ]; then
        echo "ERROR: Unable to configure FIO." >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
        exit 1
    else
        echo "Configure: Success" >> ~/summary.log
    fi
    make && make install
    sts=$?
    if [ 0 -ne ${sts} ]; then
        echo "ERROR: Unable to compile FIO." >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
        exit 1
    else
    echo "FIO successfully installed." >> ~/summary.log
    fi
  cd /root/
}
#Upgrade gcc to 4.8.1
function upgrade_gcc {
# for RHEL subscription this is available with the devtoolset-2 package
# Import CERN's GPG key
    rpm --import http://ftp.scientificlinux.org/linux/scientific/obsolete/5x/x86_64/RPM-GPG-KEYs/RPM-GPG-KEY-cern
    if [ $? -ne 0 ]; then
        echo "Error: Failed to import CERN's GPG key." >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi
# Save repository information
    wget -O /etc/yum.repos.d/slc6-devtoolset.repo http://linuxsoft.cern.ch/cern/devtoolset/slc6-devtoolset.repo
    if [ $? -ne 0 ]; then
        echo "Error: Failed to save repository information." >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi

# The below will also install all the required dependencies
    yum install -y devtoolset-2-gcc-c++
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to install the new version of gcc." >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi
    echo "source /opt/rh/devtoolset-2/enable" >> /root/.bashrc
    source /root/.bashrc
}

#Function for TX Bytes
function get_tx_bytes(){
    # RX bytes:66132495566 (66.1 GB)  TX bytes:3067606320236 (3.0 TB)
    Tx_bytes=`ifconfig $1 | grep "TX bytes"   | awk -F':' '{print $3}' | awk -F' ' ' {print $1}'`

    if [ "x$Tx_bytes" == "x" ]
    then
        #TX packets 223558709  bytes 15463202847 (14.4 GiB)
        Tx_bytes=`ifconfig $1| grep "TX packets"| awk '{print $5}'`
    fi
    echo $Tx_bytes

}

#Function for TX packets
function get_tx_pkts(){
    # TX packets:543924452 errors:0 dropped:0 overruns:0 carrier:0
    Tx_pkts=`ifconfig $1 | grep "TX packets" | awk -F':' '{print $2}' | awk -F' ' ' {print $1}'`

    if [ "x$Tx_pkts" == "x" ]
    then
        #TX packets 223558709  bytes 15463202847 (14.4 GiB)
        Tx_pkts=`ifconfig $1 | grep "TX packets"| awk '{print $3}'`
    fi
    echo $Tx_pkts
}

#Firewall and iptables for Ubuntu/CentOS6.x/RHEL6.x
function disable_firewall {
    service ufw status | grep inactive
    if [[ $? -ne 0 ]]; then
      echo "WARN: Service firewall active. Will disable it ..."
      service ufw stop
    else
      echo "Firewall is disabled."
    fi
    iptables -F
    ip6tables -F
    service iptables status | grep inactive
    if [[ $? -ne 0 ]]; then
      echo "WARN: Service iptables active. Will disable it ..."
      service iptables stop
    else
      echo "Iptables is disabled."
    fi
    service ip6tables status | grep inactive
    if [[ $? -ne 0 ]]; then
      echo "WARN: Service ip6tables active. Will disable it ..."
      service ip6tables stop
    else
      echo "Ip6tables is disabled."
    fi
    echo "Iptables and ip6tables disabled."
}

# Set static IPs for test interfaces
function config_staticip {
    declare -i __iterator=0
    while [ $__iterator -lt ${#SYNTH_NET_INTERFACES[@]} ]; do
        LogMsg "Trying to set an IP Address via static on interface ${SYNTH_NET_INTERFACES[$__iterator]}"
        CreateIfupConfigFile "${SYNTH_NET_INTERFACES[$__iterator]}" "static" $1 $2
        if [ 0 -ne $? ]; then
            msg="ERROR: Unable to set address for ${SYNTH_NET_INTERFACES[$__iterator]} through static"
            LogMsg "$msg"
            UpdateSummary "$msg"
            exit 10
        fi
        : $((__iterator++))
    done
}

#Run FIO on single physical disk
function fio_single_disk {
    #Check for raid partition
    FIND_RAID=$(cat /proc/mdstat | grep md | awk -F:  '{ print $1 }')
    if [ -n ${FIND_RAID} ]; then
        LogMsg "INFO: Raid partition found. Will delete it."
        mdadm --stop ${FIND_RAID}
        mdadm --remove ${FIND_RAID}
    fi
    #Create partition for test
    echo -e "o\nn\np\n1\n\n\nw" | fdisk ${TEST_DEVICE}
    mkfs.${FS} ${TEST_DEVICE}1
    if [ "$?" = "0" ]; then
        LogMsg "mkfs.$FS ${TEST_DEVICE}1 successful..."
        mount ${TEST_DEVICE}1 /mnt
        if [ "$?" = "0" ]; then
            LogMsg "Drive mounted successfully..."
        else
            LogMsg "ERROR in mounting drive..."
            echo "Drive mount : Failed" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
        else
        LogMsg "ERROR in creating file system.."
        echo "Creating Filesystem : Failed" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
    fi
    #Creating log folder
    if [ -d "/root/${LOG_FOLDER}" ]; then
        echo "WARN: ${LOG_FOLDER} exists. Will delete it ..." >> ~/summary.log
        rm -rf /root/${LOG_FOLDER}

    fi

	echo "Creating log folder..."
    mkdir /root/${LOG_FOLDER}

        # Run FIO with block size 8k and iodepth 1
    /root/${FIODIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-1q.log

    # Run FIO with block size 8k and iodepth 2
    sed --in-place=.orig -e s:"iodepth=1":"iodepth=2": /root/${FIO_SCENARIO_FILE}
    /root/${FIODIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-2q.log

    # Run FIO with block size 8k and iodepth 4
    sed --in-place=.orig -e s:"iodepth=2":"iodepth=4": /root/${FIO_SCENARIO_FILE}
    /root/${FIODIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-4q.log

    # Run FIO with block size 8k and iodepth 8
    sed --in-place=.orig -e s:"iodepth=4":"iodepth=8": /root/${FIO_SCENARIO_FILE}
    /root/${FIODIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-8q.log

    #Run FIO with block size 8k and iodepth 16
    sed --in-place=.orig -e s:"iodepth=8":"iodepth=16": /root/${FIO_SCENARIO_FILE}
    /root/${FIODIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-16q.log

    # Run FIO with block size 8k and iodepth 32
    sed --in-place=.orig -e s:"iodepth=16":"iodepth=32": /root/${FIO_SCENARIO_FILE}
    /root/${FIODIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-32q.log

    # Run FIO with block size 8k and iodepth 64
    sed --in-place=.orig -e s:"iodepth=32":"iodepth=64": /root/${FIO_SCENARIO_FILE}
    /root/${FIODIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-64q.log

    # Run FIO with block size 8k and iodepth 128
    sed --in-place=.orig -e s:"iodepth=64":"iodepth=128": /root/${FIO_SCENARIO_FILE}
    /root/${FIODIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-128q.log

    # Run FIO with block size 8k and iodepth 256
    sed --in-place=.orig -e s:"iodepth=128":"iodepth=256": /root/${FIO_SCENARIO_FILE}
    /root/${FIODIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-256q.log

    # Run FIO with block size 8k and iodepth 512
    sed --in-place=.orig -e s:"iodepth=256":"iodepth=512": /root/${FIO_SCENARIO_FILE}
    /root/${FIODIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-512q.log

    # Run FIO with block size 8k and iodepth 1024
    sed --in-place=.orig -e s:"iodepth=512":"iodepth=1024": /root/${FIO_SCENARIO_FILE}
    /root/${FIODIR}/fio /root/${FIO_SCENARIO_FILE} > /root/${LOG_FOLDER}/FIOLog-1024q.log

    cd /root
    zip -r ${LOG_FOLDER}.zip ${LOG_FOLDER}/*
    if [ $? -ne 0 ]; then
        echo "ERROR: Unable to archive ${LOG_FOLDER}." >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi
}
#Run FIO on multiple physical disks
function fio_raid {
    echo "INFO: Searching for raid partition."
    FIND_RAID2=$(cat /proc/mdstat | grep md | awk -F:  '{ print $1 }')
    if [ -n ${FIND_RAID2} ]; then
        echo  "INFO: Raid partition found. Will delete it."
        mdadm --stop ${FIND_RAID2}
        mdadm --remove ${FIND_RAID2}
        for i in  ${RAID_DEVICES[@]}
        do
            mdadm --zero-superblock /dev/sd$i
        done
    fi

    yes | mdadm --create --verbose /dev/${RAID_NAME} --level=0 --name=raid0_fio --raid-devices=${DISKS} /dev/sd[b-e]
    if [ $? -ne 0 ]; then
        echo "ERROR: Unable to create RAID0"  >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
    fi
    mdadm -E /dev/sd[b-e]
    if [ $? -ne 0 ]; then
        echo "ERROR: Raid partition was not found." >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
    fi
    #Write 0 on RAID
    dd if=/dev/zero of=/dev/${RAID_NAME} bs=1M oflag=direct
    #Detect OS Version
    GetDistro
    if [ $? -ne 0 ]; then
        echo "ERROR: Unable to detect OS version."
        UpdateTestState $ICA_TESTABORTED
    fi
    if [ ${DISTRO} == "centos_6" ]; then
        mkfs.${FS} /dev/${RAID_NAME} -E lazy_itable_init=0 -K
    else
        mkfs.${FS} /dev/${RAID_NAME} -E lazy_itable_init=0,lazy_journal_init=0 -K
    fi
    mount /dev/${RAID_NAME} /mnt
     #Creating log folder
    if [ -d "/root/${LOG_FOLDER}" ]; then
        echo "WARN: ${LOG_FOLDER} exists. Will delete it ..." >> ~/summary.log
        rm -rf /root/${LOG_FOLDER}
        mkdir /root/${LOG_FOLDER}
    else
        echo "Creating log folder..."
        mkdir /root/${LOG_FOLDER}
    fi
    cd /mnt
    ################################
    # IO SIZE
    ################################
    iosize_index=0
    while [ "x${IO_SIZE[$iosize_index]}" != "x" ]
    do
        current_io_size=${IO_SIZE[$iosize_index]}
        current_file_size=${FILE_SIZE[$iosize_index]}
        echo "Running IO size = ${current_io_size} K "
        ################################
        # Q DEPTH
        ################################
        q_depth_index=0
        while [ "x${Q_DEPTH[$q_depth_index]}" != "x" ]
        do
            current_q_depth=${Q_DEPTH[$q_depth_index]}
            if [ $current_q_depth -gt 8 ]
            then
                actual_q_depth=$(($current_q_depth / 8))
                num_jobs=8
            else
                actual_q_depth=$current_q_depth
                num_jobs=1
            fi
            echo "    Running q depth = ${current_q_depth} ( ${actual_q_depth} X ${num_jobs} )"
            ################################
            # IO MODE
            ################################
            io_mode_index=0
            while [ "x${IO_MODE[$io_mode_index]}" != "x" ]
            do
                current_io_mode=${IO_MODE[$io_mode_index]}
                echo "        Running IO test = ${current_io_mode}"
                log_file="/root/${LOG_FOLDER}/${current_io_size}K-${current_q_depth}-${current_io_mode}.fio.log"
                echo "FIO TEST COMMAND:" > ${log_file}
                echo "fio --name=${current_io_mode} --bs=${current_io_size}k --ioengine=libaio --iodepth=${actual_q_depth} --size=${current_file_size}G --direct=1 --runtime=120 --numjobs=${num_jobs} --rw=${current_io_mode} --group_reporting" >> ${log_file}
                      fio --name=${current_io_mode} --bs=${current_io_size}k --ioengine=libaio --iodepth=${actual_q_depth} --size=${current_file_size}G --direct=1 --runtime=120 --numjobs=${num_jobs} --rw=${current_io_mode} --group_reporting  >> ${log_file}
                sleep 1
                io_mode_index=$(($io_mode_index + 1))
            done
            sleep 1
            q_depth_index=$(($q_depth_index + 1))
        done

        echo ""
        sleep 1
        iosize_index=$(($iosize_index + 1))
    done
    sleep 1

    cd /root
    zip -r ${LOG_FOLDER}.zip ${LOG_FOLDER}/*
}

perf_ConfigureBond()
{
    LogMsg "BondCount: $bondCount"
    ip_to_set=$1
    # Set static IPs for each bond created
    staticIP=$(cat constants.sh | grep ${ip_to_set} | head -1 | tr = " " | awk '{print $2}')

    if is_ubuntu ; then
        __file_path="/etc/network/interfaces"
        # Change /etc/network/interfaces
        sed -i "s/bond0 inet dhcp/bond0 inet static/g" $__file_path
        sed -i "/bond0 inet static/a address $staticIP" $__file_path
        sed -i "/address ${staticIP}/a netmask $NETMASK" $__file_path

    elif is_suse ; then
        __file_path="/etc/sysconfig/network/ifcfg-bond0"
        # Replace the BOOTPROTO, IPADDR and NETMASK values found in ifcfg file
        sed -i "/\b\(BOOTPROTO\|IPADDR\|\NETMASK\)\b/d" $__file_path
        cat <<-EOF >> $__file_path
        BOOTPROTO=static
        IPADDR=$staticIP
        NETMASK=$NETMASK
EOF

    elif is_fedora ; then
        __file_path="/etc/sysconfig/network-scripts/ifcfg-bond0"
        # Replace the BOOTPROTO, IPADDR and NETMASK values found in ifcfg file
        sed -i "/\b\(BOOTPROTO\|IPADDR\|\NETMASK\)\b/d" $__file_path
        cat <<-EOF >> $__file_path
        BOOTPROTO=static
        IPADDR=$staticIP
        NETMASK=$NETMASK
EOF
    fi
    LogMsg "Network config file path: $__file_path"

    # Add some interface output
    LogMsg "$(ip -o addr show bond0 | grep -vi inet6)"

    # Get everything up & running
    if is_ubuntu ; then
        service networking restart

    elif is_suse ; then
        service network restart

    elif is_fedora ; then
        service network restart
    fi
}

#
# VerifyVF - check if the VF driver is use
#
VerifyVF()
{
	# Check for pciutils. If it's not on the system, install it
	lspci --version
	if [ $? -ne 0 ]; then
	    msg="INFO: pciutils not found. Trying to install it"
	    LogMsg "$msg"

	    GetDistro
	    case "$DISTRO" in
	        suse*)
	            zypper --non-interactive in pciutils
	            if [ $? -ne 0 ]; then
	                msg="ERROR: Failed to install pciutils"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            fi
	            ;;
	        ubuntu*)
	            apt-get install pciutils -y
	            if [ $? -ne 0 ]; then
	                msg="ERROR: Failed to install pciutils"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            fi
	            ;;
	        redhat*|centos*)
	            yum install pciutils -y
	            if [ $? -ne 0 ]; then
	                msg="ERROR: Failed to install pciutils"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            fi
	            ;;
	            *)
	                msg="ERROR: OS Version not supported"
	                LogMsg "$msg"
	                UpdateSummary "$msg"
	                SetTestStateFailed
	                exit 1
	            ;;
	    esac
	fi

	# Using lsmod command, verify if driver is loaded
	lsmod | grep ixgbevf
	if [ $? -ne 0 ]; then
	    lsmod | grep mlx4_core
	    if [ $? -ne 0 ]; then
	  		msg="ERROR: Neither mlx4_core or ixgbevf drivers are in use!"
	  		LogMsg "$msg"
		    UpdateSummary "$msg"
		    SetTestStateFailed
		    exit 1
		fi
	fi

	# Using the lspci command, verify if NIC has SR-IOV support
	lspci -vvv | grep ixgbevf
	if [ $? -ne 0 ]; then
		lspci -vvv | grep mlx4_core
		if [ $? -ne 0 ]; then
		    msg="No NIC with SR-IOV support found!"
		    LogMsg "$msg"
		    UpdateSummary "$msg"
		    SetTestStateFailed
		    exit 1
		fi
	fi

    interface=$(ls /sys/class/net/ | grep -v 'eth0\|eth1\|bond*\|lo' | head -1)
    ifconfig -a | grep $interface
    if [ $? -ne 0 ]; then
        msg="ERROR: VF device, $interface , was not found!"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    fi

    return 0
}

#
# RunBondingScript - it will run the bonding script. Acceptance criteria is the
# presence of the bond between VF and eth after the bonding script ran.
# NOTE: function returns the number of bonds present on VM, not "0"
#
RunBondingScript()
{
	if is_ubuntu ; then
	    bash /usr/src/linux-headers-*/tools/hv/bondvf.sh

	    # Verify if bond0 was created
	    bondCount=$(cat /etc/network/interfaces | grep "auto bond" | wc -l)
	    if [ 0 -eq $bondCount ]; then
	        msg="ERROR: Bonding script failed. No bond was created"
		    LogMsg "$msg"
		    UpdateSummary "$msg"
		    SetTestStateFailed
		    return 99
	    fi

	elif is_suse ; then
	    bash /usr/src/linux-*/tools/hv/bondvf.sh

	    # Verify if bond0 was created
	    bondCount=$(ls -d /etc/sysconfig/network/ifcfg-bond* | wc -l)
	    if [ 0 -eq $bondCount ]; then
	        msg="ERROR: Bonding script failed. No bond was created"
		    LogMsg "$msg"
		    UpdateSummary "$msg"
		    SetTestStateFailed
		    return 99
	    fi

	elif is_fedora ; then
	    ./bondvf.sh

	    # Verify if bond0 was created
	    bondCount=$(ls -d /etc/sysconfig/network-scripts/ifcfg-bond* | wc -l)
	    if [ 0 -eq $bondCount ]; then
	        msg="ERROR: Bonding script failed. No bond was created"
		    LogMsg "$msg"
		    UpdateSummary "$msg"
		    SetTestStateFailed
		    return 99
	    fi
	fi

	LogMsg "Successfully ran the bonding script"
	return $bondCount
}