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

#######################################################################
#
# perf_ntttcp_client.sh
#
# Description:
#     A multiple-thread based Linux network throughput benchmark tool.
#     For the test to run you have to install ntttcp-for-linux from github: https://github.com/Microsoft/ntttcp-for-linux
#
# Requirements:
#   - GCC installed
#
#Example run
#
#To measure the network performance between two multi-core serves running SLES 12, NODE1 (192.168.4.1) and NODE2 (192.168.4.2), connected via a 40 GigE connection.
#
#And on NODE2 (the sender), run: ./ntttcp -s192.168.4.1
#Run ntttcp as a receiver with default setting. The default setting includes: with 16 threads created and run across all CPUs, 
#allocating 64K receiver buffer, and run for 60 seconds.)
#######################################################################

ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"
HOME="/root"


LogMsg() {
    echo `date "+%a %b %d %T %Y"` ": ${1}"
}

UpdateTestState() {
    echo $1 > ~/state.txt
}


#######################################################################
#
# Main script body
#
#######################################################################
cd ~
UpdateTestState $ICA_TESTRUNNING
LogMsg "Starting test"

# Delete any old summary.log file
#
LogMsg "Cleaning up old summary.log"
if [ -e ~/summary.log ]; then
    rm -f ~/summary.log
fi

touch ~/summary.log

# Convert eol
dos2unix utils.sh
# Source utils.sh
. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

dos2unix perf_utils.sh
# Source perf_utils.sh
. perf_utils.sh || {
    echo "ERROR: unable to source perf_utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Source constants file and initialize most common variables
UtilsInit
# In case of ERROR
case $? in
    0)
        #do nothing, init succeeded
        ;;
    1)
        LogMsg "Unable to cd to $LIS_HOME. Aborting..."
        UpdateSummary "Unable to cd to $LIS_HOME. Aborting..."
        SetTestStateAborted
        exit 3
        ;;
    2)
        LogMsg "Unable to use test state file. Aborting..."
        UpdateSummary "Unable to use test state file. Aborting..."
        # need to wait for test timeout to kick in
        # hailmary try to update teststate
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
        # should not happen
        LogMsg "UtilsInit returned an unknown ERROR. Aborting..."
        UpdateSummary "UtilsInit returned an unknown ERROR. Aborting..."
        SetTestStateAborted
        exit 6
        ;;
esac

# Make sure the required test parameters are defined
if [ "${STATIC_IP:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="ERROR: the STATIC_IP test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${NETMASK:="UNDEFINED"}" = "UNDEFINED" ]; then
    NETMASK="255.255.255.0"
    msg="ERROR: the NETMASK test parameter is missing, default value will be used: 255.255.255.0"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ "${SERVER_IP:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="ERROR: the SERVER_IP test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${STATIC_IP2:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="ERROR: the STATIC_IP2 test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${SERVER_OS_USERNAME:="UNDEFINED"}" = "UNDEFINED" ]; then
    SERVER_OS_USERNAME="root"
    msg="Warning: the SERVER_OS_USERNAME test parameter is missing and the default value will be used: ${SERVER_OS_USERNAME}."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

# Parameter provided in constants file
#  ipv4 is the IP Address of the interface used to communicate with the VM, which needs to remain unchanged
#  it is not touched during this test (no dhcp or static ip assigned to it)
if [ "${ipv4:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter ipv4 is not defined in constants file! Make sure you are using the latest LIS code."
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
    exit 30
else
    CheckIP "$ipv4"
    if [ 0 -ne $? ]; then
        msg="Test parameter ipv4 = $ipv4 is not a valid IP Address"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateAborted
        exit 10
    fi
fi

#Get test synthetic interface
declare __iface_ignore
# Get the interface associated with the given ipv4
__iface_ignore=$(ip -o addr show | grep "$ipv4" | cut -d ' ' -f2)
# Retrieve synthetic network interfaces
GetSynthNetInterfaces
if [ 0 -ne $? ]; then
    msg="No synthetic network interfaces found"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi
# Remove interface if present
SYNTH_NET_INTERFACES=(${SYNTH_NET_INTERFACES[@]/$__iface_ignore/})
if [ ${#SYNTH_NET_INTERFACES[@]} -eq 0 ]; then
    msg="The only synthetic interface is the one which LIS uses to send files/commands to the VM."
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
    exit 10
fi
# SRIOV setup (transparent VF)
if [ "${SRIOV}" = "yes" ]; then
    # Check if the SR-IOV driver is in use used from perf_utils
    VerifyVF
    if [ $? -ne 0 ]; then
        msg="ERROR: VF is not loaded! Make sure you are using compatible hardware"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi
    __vf_ignore='enP2p0s2'
    SYNTH_NET_INTERFACES=(${SYNTH_NET_INTERFACES[@]/$__vf_ignore/})
fi

LogMsg "Found ${#SYNTH_NET_INTERFACES[@]} synthetic interface(s): ${SYNTH_NET_INTERFACES[*]} in VM"
# Test interfaces
declare -i __iterator
for __iterator in "${!SYNTH_NET_INTERFACES[@]}"; do
    ip link show "${SYNTH_NET_INTERFACES[$__iterator]}" >/dev/null 2>&1
    if [ 0 -ne $? ]; then
        msg="Invalid synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 20
    fi
done
LogMsg "Found ${#SYNTH_NET_INTERFACES[@]} synthetic interface(s): ${SYNTH_NET_INTERFACES[*]} in VM"

# Config static IP - using bondvf.sh
if [ "${SRIOV}" = "bond" ]; then
    # Check if the SR-IOV driver is in use
    VerifyVF
    if [ $? -ne 0 ]; then
        msg="ERROR: VF is not loaded! Make sure you are using compatible hardware"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi
    # Run bondvf.sh platform specific script
    RunBondingScript
    bondCount=$?
    if [ $bondCount -eq 99 ]; then
        msg="ERROR: Running the bonding script failed. Please double check if it is present on the system"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    else
        LogMsg "BondCount returned by SR-IOV_Utils: $bondCount"
    fi
    # Set static IP to the bond
    perf_ConfigureBond ${STATIC_IP}
    if [ $? -ne 0 ]; then
        msg="ERROR: Could not set a static IP to the bond!"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi
fi

# Config static IP - with transparent-vf it is not necessary to run bondvf.sh
if [[ "${SRIOV}" = "yes" ]] || [[ "${SRIOV}" = "no" ]]; then
    #Config static ip on the client side.
    config_staticip ${STATIC_IP} ${NETMASK}
    if [ $? -ne 0 ]; then
        echo "ERROR: Function config_staticip failed."
        LogMsg "ERROR: Function config_staticip failed."
        UpdateTestState $ICA_TESTABORTED
    fi
fi
echo "Ntttcp client test interface ip           = ${STATIC_IP}"
echo "Ntttcp server ip           = ${STATIC_IP2}"
echo "Ntttcp server test interface ip        = ${SERVER_IP}"
echo "Test duration       = ${TEST_DURATION}"
echo "Test Threads       = ${TEST_THREADS}"
echo "Max threads       = ${MAX_THREADS}"
echo "user name on server       = ${SERVER_OS_USERNAME}"
echo "Test Interface       = ${ETH_NAME}"

#Apling performance parameters
setup_sysctl "$(declare -p sysctl_tcp_params)"
if [ $? -ne 0 ]; then
    echo "Unable to add performance parameters."
    LogMsg "Unable to add performance parameters."
    UpdateTestState $ICA_TESTABORTED
fi

# Check for internet protocol version
CheckIPV6 "$STATIC_IP"
if [[ $? -eq 0 ]]; then
    CheckIPV6 "$SERVER_IP"
    if [[ $? -eq 0 ]]; then
        ipVersion="-6"
    else
        msg="ERROR: Not both test IPs are IPV6"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 60
    fi
else
    ipVersion=
fi

# Flushing firewall rules
iptables -F
if [ $? -ne 0 ]; then
    msg="ERROR: Failed to flush iptables rules. Continuing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi
ip6tables -F
if [ $? -ne 0 ]; then
    msg="ERROR: Failed to flush ip6tables rules. Continuing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

#Check distro
GetDistro
case "$DISTRO" in
debian*|ubuntu*)
    disable_firewall
    if [[ $? -ne 0 ]]; then
        msg="ERROR: Unable to disable firewall.Exiting"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
    LogMsg "Installing dependency tools on Ubuntu"
    apt-get update && apt-get install build-essential git sysstat dstat -y
    if [ $? -ne 0 ]; then
        msg="ERROR: dependencies failed to install"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
    fi
    ;;
redhat_5|redhat_6|centos_6|centos_5)
    yum install -y bc sysstat dstat
    if [ $? -ne 0 ]; then
        msg="ERROR: dependencies failed to install"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
    fi
    LogMsg "Check irqbalance status on RHEL 5/6.x."
    service irqbalance status
    if [ $? -eq 3 ]; then
        LogMsg "Enabling irqbalance on Redhat 5/6.x"
        service irqbalance start
        if [ $? -ne 0 ]; then
            msg="ERROR: Failed to start irqbalance. Failing."
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        service irqbalance status
    fi
    disable_firewall
    if [[ $? -ne 0 ]]; then
        msg="ERROR: Unable to disable firewall.Exiting"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
    ;;
redhat_7|centos_7)
    yum install -y bc sysstat dstat
    if [ $? -ne 0 ]; then
        msg="ERROR: dependencies failed to install"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
    fi
    LogMsg "Check irqbalance status on RHEL 7.xx."
    systemctl status irqbalance
    if [ $? -eq 3 ]; then
        LogMsg "Enabling irqbalance on Redhat 7.x"
        systemctl enable irqbalance && systemctl start irqbalance
        if [ $? -ne 0 ]; then
            msg="ERROR: Failed to start irqbalance. Failing."
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        systemctl status irqbalance
    fi
    LogMsg "Check firewalld status on RHEL 7.xx."
    systemctl status firewalld
    if [ $? -ne 3 ]; then
        LogMsg "Disabling firewall on Redhat 7.x"
        systemctl stop firewalld && systemctl disable firewalld
        if [ $? -ne 0 ]; then
            msg="ERROR: Failed to turn off firewalld. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
    fi
    disable_firewall
    if [[ $? -ne 0 ]]; then
        msg="ERROR: Unable to disable firewall.Exiting"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
    ;;
suse_12)
    zypper -n in dstat sysstat gcc
    if [ $? -ne 0 ]; then
        msg="ERROR: dependencies failed to install"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
    fi
    LogMsg "Check iptables status on SLES 12"
    service SuSEfirewall2 status
    if [ $? -ne 3 ]; then
        service SuSEfirewall2 stop
        if [ $? -ne 0 ]; then
            msg="ERROR: Failed to stop iptables"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 85
        fi
        chkconfig SuSEfirewall2 off
        if [ $? -ne 0 ]; then
            msg="ERROR: Failed to turn off iptables. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
    fi
    ;;
esac

LogMsg "Enlarging the system limit"
ulimit -n 204800
if [ $? -ne 0 ]; then
    LogMsg "ERROR: Unable to enlarged system limit"
    UpdateTestState $ICA_TESTABORTED
fi

#Install LAGSCOPE tool for latency
setup_lagscope
if [ $? -ne 0 ]; then
    echo "ERROR: Unable to compile lagscope."
    LogMsg "ERROR: Unable to compile lagscope."
    UpdateTestState $ICA_TESTABORTED
fi

#Install NTTTCP for network throughput
setup_ntttcp
if [ $? -ne 0 ]; then
    echo "ERROR: Unable to compile ntttcp-for-linux."
    LogMsg "ERROR: Unable to compile ntttcp-for-linux."
    UpdateTestState $ICA_TESTABORTED
fi

dos2unix ~/*.sh
chmod 755 ~/*.sh
LogMsg "Copy files to server: ${STATIC_IP2}"
scp -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ~/perf_ntttcp_server.sh ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:
if [ $? -ne 0 ]; then
    msg="ERROR: Unable to copy test scripts to target server machine: ${STATIC_IP2}. scp command failed."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 130
fi
scp -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ~/constants.sh ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:
scp -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ~/utils.sh ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:
scp -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ~/perf_utils.sh ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:

# Start ntttcp in server mode on the Target server side
LogMsg "Starting ntttcp in server mode on ${STATIC_IP2}"
ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "~/perf_ntttcp_server.sh > ntttcp_ServerSideScript.log"
if [ $? -ne 0 ]; then
    msg="ERROR: Unable to start ntttcp server scripts on the target server machine"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 130
fi

#Create log folder
if [ -d  $HOME/$log_folder ]; then
    echo "File $log_folder exists: will be deleted."
    LogMsg "File $log_folder exists." >> ~/summary.log
    rm -rf $HOME/$log_folder
fi

mkdir $HOME/$log_folder
eth_log="$HOME/$log_folder/eth_report.log"
echo "#test_connections    throughput_gbps    average_packet_size" > $eth_log

sleep 10
#Starting test
cat /proc/interrupts > $HOME/$log_folder/sender-interrupts-start.log
ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "cat /proc/interrupts > $HOME/$log_folder/receiver-interrupts-start.log"
previous_tx_bytes=$(get_tx_bytes $ETH_NAME)
previous_tx_pkts=$(get_tx_pkts $ETH_NAME)
port_change=false
port=
for current_test_threads in "${TEST_THREADS[@]}"
do
    if [ $current_test_threads -lt $MAX_THREADS ]
    then
        num_threads_P=$current_test_threads
        num_threads_n=1
    else
        num_threads_P=$MAX_THREADS
        num_threads_n=$(($current_test_threads / $num_threads_P))
    fi
    if ${port_change}
    then
        port=20000
        port_change=false
    else
        port=40000
        port_change=true
    fi
    echo "======================================"
    echo "Running Test: $num_threads_P X $num_threads_n"
    echo "======================================"
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -f -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "ulimit -n 204800 && ntttcp -r${SERVER_IP} -P $num_threads_P -e ${ipVersion} > $HOME/$log_folder/ntttcp-receiver-p${num_threads_P}X${num_threads_n}.log"
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -f -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "lagscope -r${SERVER_IP} ${ipVersion}"
    sleep 1
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -f -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "for ((i=1;i<=$TEST_DURATION;i++)); do ss -ta | grep ESTA | grep -v ssh | wc -l >> $HOME/$log_folder/tcp-connections-p${current_test_threads}.log; sleep 1; done"
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -f -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "sar -n DEV 1 ${TEST_DURATION} > $HOME/$log_folder/sar-receiver-p${current_test_threads}.log"
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -f -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "dstat -dam 1 ${TEST_DURATION} > $HOME/$log_folder/dstat-receiver-p${current_test_threads}.log"
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -f -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "mpstat -P ALL 1 ${TEST_DURATION} > $HOME/$log_folder/mpstat-receiver-p${current_test_threads}.log"

    sar -n DEV 1 ${TEST_DURATION} > "$HOME/$log_folder/sar-sender-p${current_test_threads}.log" &
    dstat -dam 1 ${TEST_DURATION} > "$HOME/$log_folder/dstat-sender-p${current_test_threads}.log" &
    mpstat -P ALL 1 ${TEST_DURATION} > "$HOME/$log_folder/mpstat-sender-p${current_test_threads}.log" &

    lagscope -s${SERVER_IP} -t ${TEST_DURATION} -V ${ipVersion} > "./$log_folder/lagscope-ntttcp-p${num_threads_P}X${num_threads_n}.log" &
    ntttcp -s${SERVER_IP} -P $num_threads_P -n $num_threads_n -t ${TEST_DURATION} ${ipVersion} -f${port} > "./$log_folder/ntttcp-sender-p${num_threads_P}X${num_threads_n}.log"
    sts=$?

    current_tx_bytes=$(get_tx_bytes $ETH_NAME)
    current_tx_pkts=$(get_tx_pkts $ETH_NAME)
    bytes_new=`(expr $current_tx_bytes - $previous_tx_bytes)`
    pkts_new=`(expr $current_tx_pkts - $previous_tx_pkts)`
    avg_pkt_size=$(echo "scale=2;$bytes_new/$pkts_new/1024" | bc)
    Throughput=$(echo "scale=2;$bytes_new/$TEST_DURATION*8/1024/1024/1024" | bc)
    previous_tx_bytes=$current_tx_bytes
    previous_tx_pkts=$current_tx_pkts

    echo "Throughput (gbps): $Throughput"
    echo "average packet size: $avg_pkt_size"
    printf "%4s  %8.2f  %8.2f\n" ${current_test_threads} $Throughput $avg_pkt_size >> $eth_log

    echo "current test finished. wait 10 seconds for next one... "
    sleep 10
    pkill -x ntttcp
    pkill -x lagscope
    pkill -f ESTA
    pkill -x sar
    pkill -x dstat
    pkill -x mpstat
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "pkill -x ntttcp"
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "pkill -x lagscope"
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "pkill -x sar"
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "pkill -x dstat"
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "pkill -x mpstat"
done

ethtool -S eth1 > $HOME/$log_folder/sender-ethtool-eth1.log
ethtool -S enP2p0s2 > $HOME/$log_folder/sender-ethtool-enP2p0s2.log
ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "ethtool -S eth1 > $HOME/$log_folder/receiver-ethtool-eth1.log"
ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "ethtool -S enP2p0s2 > $HOME/$log_folder/receiver-ethtool-enP2p0s2.log"
cat /proc/interrupts > $HOME/$log_folder/sender-interrupts-end.log
ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "cat /proc/interrupts > $HOME/$log_folder/receiver-interrupts-end.log"
LogMsg "Ntttcp succeeded with all connections."
echo "Ntttcp succeeded with all connections." >> ~/summary.log
cd $HOME
scp -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:/root/$log_folder/* /root/$log_folder
if [ $? -ne 0 ]; then
    echo "ERROR: Unable to transfer server side logs."
    UpdateTestState $ICA_TESTFAILED
fi
zip -r $log_folder.zip $log_folder/*

if [ $sts -eq 0 ]; then
    LogMsg "Test completed"
    echo "Test completed" >> ~/summary.log
else
    LogMsg "Some NTTTCP connections failed to run."
    echo "Some NTTTCP connections failed to run." >> ~/summary.log
fi

UpdateTestState $ICA_TESTCOMPLETED
