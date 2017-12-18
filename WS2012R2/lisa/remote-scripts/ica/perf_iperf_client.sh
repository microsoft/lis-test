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
# perf_iperf_client.sh
#
# Description:
#     For the test to run you have to place the iperf tool package in the
#     Tools folder under lisa.
#
# Requirements:
#   The sar utility must be installed, package named sysstat
#
# Parameters:
#     IPERF_PACKAGE: the iperf3 tool package
#     IPERF3_SERVER_IP: the ipv4 address of the server
#     INDIVIDUAL_TEST_DURATION: the test duration of each iperf3 test
#     CONNECTIONS_PER_IPERF3: how many iPerf connections will be created by iPerf3 client to a single iperf3 server
#     SERVER_OS_USERNAME: the user name used to copy test signal file to server side
#     TEST_SIGNAL_FILE: the signal file send by client side to sync up the number of test connections
#     TEST_RUN_LOG_FOLDER: the log folder name. sar log and top log will be saved in this folder for further analysis
#     IPERF3_TEST_CONNECTION_POOL: the list of iperf3 connections need to be tested
#	  BANDWIDTH: bandwith used
#	  IPERF3_BUFFER: buffer size used for testing
#
#######################################################################

ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` ": ${1}"
}

UpdateTestState()
{
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

#
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
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}
dos2unix perf_utils.sh
# Source perf_utils.sh
. perf_utils.sh || {
    echo "Error: unable to source perf_utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Allowing more time for the 2nd VM to start
sleep 60

# Source constants file and initialize most common variables
UtilsInit
# In case of error
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
        LogMsg "Error: unable to source constants file. Aborting..."
        UpdateSummary "Error: unable to source constants file"
        SetTestStateAborted
        exit 5
        ;;
    *)
        # should not happen
        LogMsg "UtilsInit returned an unknown error. Aborting..."
        UpdateSummary "UtilsInit returned an unknown error. Aborting..."
        SetTestStateAborted
        exit 6
        ;;
esac

# Make sure the required test parameters are defined
if [ "${IPERF_PACKAGE:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the IPERF_PACKAGE test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${STATIC_IP:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the STATIC_IP test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${NETMASK:="UNDEFINED"}" = "UNDEFINED" ]; then
    NETMASK="255.255.255.0"
    msg="Error: the NETMASK test parameter is missing, default value will be used: 255.255.255.0"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ "${IPERF3_SERVER_IP:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the IPERF3_SERVER_IP test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${IPERF3_PROTOCOL:="UNDEFINED"}" = "UNDEFINED" ]; then
    IPERF3_PROTOCOL="TCP"
    PROTOCOL=
    msg="Info: no IPERF3_PROTOCOL was specified, assuming default TCP"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
else
    if [[ ${IPERF3_PROTOCOL} == "UDP" ]]; then
        PROTOCOL="--udp"
    fi
fi

if [ "${IPERF3_BUFFER:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Info: no IPERF3_BUFFER was specified, assuming default buffer size."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ "${BANDWIDTH:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Info: no BANDWIDTH was specified, assuming default value."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ "${STATIC_IP2:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the STATIC_IP2 test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${INDIVIDUAL_TEST_DURATION:="UNDEFINED"}" = "UNDEFINED" ]; then
    INDIVIDUAL_TEST_DURATION=600
    msg="Error: the INDIVIDUAL_TEST_DURATION test parameter is missing and the default value will be used: ${INDIVIDUAL_TEST_DURATION}."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ "${CONNECTIONS_PER_IPERF3:="UNDEFINED"}" = "UNDEFINED" ]; then
    CONNECTIONS_PER_IPERF3=4
    msg="Error: the CONNECTIONS_PER_IPERF3 test parameter is missing and the default value will be used: ${CONNECTIONS_PER_IPERF3}."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ "${SERVER_OS_USERNAME:="UNDEFINED"}" = "UNDEFINED" ]; then
    SERVER_OS_USERNAME="root"
    msg="Warning: the SERVER_OS_USERNAME test parameter is missing and the default value will be used: ${SERVER_OS_USERNAME}."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ "${TEST_SIGNAL_FILE:="UNDEFINED"}" = "UNDEFINED" ]; then
    TEST_SIGNAL_FILE="~/iperf3.test.sig"
    msg="Warning: the TEST_SIGNAL_FILE test parameter is missing and the default value will be used: ${TEST_SIGNAL_FILE}."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ "${TEST_RUN_LOG_FOLDER:="UNDEFINED"}" = "UNDEFINED" ]; then
    TEST_RUN_LOG_FOLDER="iperf3-client-logs"
    msg="Warning: the TEST_RUN_LOG_FOLDER test parameter is is missing and the default value will be used:${TEST_RUN_LOG_FOLDER}"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ "${IPERF3_TEST_CONNECTION_POOL:="UNDEFINED"}" = "UNDEFINED" ]; then
    IPERF3_TEST_CONNECTION_POOL=(1 2 4 8 16 32 64 128 256 512 1024 2000 3000 6000)
    msg="Warning: the IPERF3_TEST_CONNECTION_POOL test parameter is is missing and the default value will be used:(1 2 4 8 16 32 64 128 256 512 1024 2000 3000 6000)"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

#   ipv4 is the IP Address of the interface used to communicate with the VM, which needs to remain unchanged
#   it is not touched during this test (no dhcp or static ip assigned to it)
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
    # Check if the SRIOV driver is in use
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
# Config static IP - using bondvf.sh
if [ "${SRIOV}" = "bond" ]; then
    # Check if the SRIOV driver is in use
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
        LogMsg "BondCount returned: $bondCount"
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

echo "iPerf package name        = ${IPERF_PACKAGE}"
echo "iPerf client test interface ip           = ${STATIC_IP}"
echo "iPerf server ip           = ${STATIC_IP2}"
echo "iPerf server test interface ip        = ${IPERF3_SERVER_IP}"
echo "iPerf protocol        = ${IPERF3_PROTOCOL}"
echo "individual test duration (sec)    = ${INDIVIDUAL_TEST_DURATION}"
echo "connections per iperf3        = ${CONNECTIONS_PER_IPERF3}"
echo "user name on server       = ${SERVER_OS_USERNAME}"
echo "test signal file      = ${TEST_SIGNAL_FILE}"
echo "test run log folder       = ${TEST_RUN_LOG_FOLDER}"
echo "iperf3 test connection pool   = ${IPERF3_TEST_CONNECTION_POOL}"

#Apling performance parameters
setup_sysctl "$(declare -p sysctl_udp_params)"
if [ $? -ne 0 ]; then
    echo "Unable to add performance parameters."
    LogMsg "Unable to add performance parameters."
    UpdateTestState $ICA_TESTABORTED
fi

# Check for internet protocol version
CheckIPV6 "$STATIC_IP"
if [[ $? -eq 0 ]]; then
    CheckIPV6 "$IPERF3_SERVER_IP"
    if [[ $? -eq 0 ]]; then
        ipVersion="-6"
    else
        msg="Error: Not both test IPs are IPV6"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 60
    fi
else
    ipVersion="-4"
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
    apt-get update && apt-get install build-essential git sysstat dstat lib32z1 -y
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

# Extract the files from the IPerf tar package
tar -xzf ./${IPERF_PACKAGE}
if [ $? -ne 0 ]; then
    msg="Error: Unable extract ${IPERF_PACKAGE}"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 70
fi
# Get the root directory of the tarball
rootDir=`tar -tzf ${IPERF_PACKAGE} | sed -e 's@/.*@@' | uniq`
if [ -z ${rootDir} ]; then
    msg="Error: Unable to determine root directory if ${IPERF_PACKAGE} tarball"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 80
fi

LogMsg "rootDir = ${rootDir}"
cd ${rootDir}
# Build iperf
./configure
if [ $? -ne 0 ]; then
    msg="Error: ./configure failed"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 90
fi
make
if [ $? -ne 0 ]; then
    msg="Error: Unable to build iperf"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 100
fi
make install
if [ $? -ne 0 ]; then
    msg="Error: Unable to install iperf"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 110
fi

if [[ ${DISTRO} == *"suse"* || ${DISTRO} == *"ubuntu"* ]]; then
    ldconfig
    if [ $? -ne 0 ]; then
        msg="Warning: Couldn't run ldconfig, there might be shared library errors"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
    fi
fi

# Make all bash scripts executable
cd ~
dos2unix ~/*.sh
chmod 755 ~/*.sh

function get_tx_bytes(){
    # RX bytes:66132495566 (66.1 GB)  TX bytes:3067606320236 (3.0 TB)
    Tx_bytes=`ifconfig $ETH_NAME | grep "TX bytes"   | awk -F':' '{print $3}' | awk -F' ' ' {print $1}'`

    if [ "x$Tx_bytes" == "x" ]
    then
        #TX packets 223558709  bytes 15463202847 (14.4 GiB)
        Tx_bytes=`ifconfig $ETH_NAME| grep "TX packets"| awk '{print $5}'`
    fi
    echo $Tx_bytes

}

function get_tx_pkts(){
    # TX packets:543924452 errors:0 dropped:0 overruns:0 carrier:0
    Tx_pkts=`ifconfig $ETH_NAME | grep "TX packets" | awk -F':' '{print $2}' | awk -F' ' ' {print $1}'`

    if [ "x$Tx_pkts" == "x" ]
    then
        #TX packets 223558709  bytes 15463202847 (14.4 GiB)
        Tx_pkts=`ifconfig $ETH_NAME| grep "TX packets"| awk '{print $3}'`
    fi
    echo $Tx_pkts
}

LogMsg "Copy files to server: ${STATIC_IP2}"
scp -i "$HOME"/.ssh/"${SSH_PRIVATE_KEY}" -o StrictHostKeyChecking=no ~/perf_iperf_server.sh ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:
if [ $? -ne 0 ]; then
    msg="Error: Unable to copy test scripts to target server machine: ${STATIC_IP2}. scp command failed."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 130
fi
scp -i "$HOME"/.ssh/"${SSH_PRIVATE_KEY}" -o StrictHostKeyChecking=no ~/${IPERF_PACKAGE} ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:
scp -i "$HOME"/.ssh/"${SSH_PRIVATE_KEY}" -o StrictHostKeyChecking=no ~/constants.sh ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:
scp -i "$HOME"/.ssh/"${SSH_PRIVATE_KEY}" -o StrictHostKeyChecking=no ~/utils.sh ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:
scp -i "$HOME"/.ssh/"${SSH_PRIVATE_KEY}" -o StrictHostKeyChecking=no ~/perf_utils.sh ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:

# Start iPerf in server mode on the Target server side
LogMsg "Starting iPerf in server mode on ${STATIC_IP2}"
ssh -i "$HOME"/.ssh/"${SSH_PRIVATE_KEY}" -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "~/perf_iperf_server.sh > iPerf3_Panorama_ServerSideScript.log"
if [ $? -ne 0 ]; then
    msg="Error: Unable to start iPerf3 server scripts on the target server machine"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 130
fi

sleep 10

function run_iperf_parallel(){
    current_test_threads=$1
    port=8001
    number_of_connections=${current_test_threads}
    while [ ${number_of_connections} -gt ${CONNECTIONS_PER_IPERF3} ]; do
        number_of_connections=$(($number_of_connections - $CONNECTIONS_PER_IPERF3))
        logfile="/${HOME}/${TEST_RUN_LOG_FOLDER}/${current_test_threads}-p${port}-l${IPERF3_BUFFER}-iperf3.log"
        iperf3 ${PROTOCOL} -c ${IPERF3_SERVER_IP} -p ${port} ${ipVersion} ${BANDWIDTH+-b ${BANDWIDTH}} -l ${IPERF3_BUFFER} -P ${CONNECTIONS_PER_IPERF3} -t ${INDIVIDUAL_TEST_DURATION} --get-server-output -i ${INDIVIDUAL_TEST_DURATION} > ${logfile} 2>&1 & pid=$!
        port=$(($port + 1))
        PID_LIST+=" $pid"
    done
    if [ ${number_of_connections} -gt 0 ]
    then
        logfile="/${HOME}/${TEST_RUN_LOG_FOLDER}/${current_test_threads}-p${port}-l${IPERF3_BUFFER}-iperf3.log"
        iperf3 ${PROTOCOL} -c ${IPERF3_SERVER_IP} -p ${port} ${ipVersion} ${BANDWIDTH+-b ${BANDWIDTH}} -l ${IPERF3_BUFFER} -P ${number_of_connections} -t ${INDIVIDUAL_TEST_DURATION} --get-server-output -i ${INDIVIDUAL_TEST_DURATION} > ${logfile} 2>&1 & pid=$!
        PID_LIST+=" $pid"
    fi

    trap "sudo kill ${PID_LIST}" SIGINT
    wait ${PID_LIST}
}

function run_iperf_udp()
{
    current_test_threads=$1
    LogMsg "======================================"
    LogMsg "Running iPerf3 thread= ${current_test_threads}"
    LogMsg "======================================"
    port=8001
    server_iperf_instances=$((current_test_threads/${CONNECTIONS_PER_IPERF3}+port))
    for ((i=port; i<=server_iperf_instances; i++))
    do
        ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "iperf3 -s ${ipVersion} -p $i -i ${INDIVIDUAL_TEST_DURATION} -D"
        sleep 1
    done

    sar -n DEV 1 ${INDIVIDUAL_TEST_DURATION} > "${TEST_RUN_LOG_FOLDER}/sar-sender-${current_test_threads}.log" &
    dstat -dam > "${TEST_RUN_LOG_FOLDER}/dstat-sender-${current_test_threads}.log" &
    mpstat -P ALL 1 ${INDIVIDUAL_TEST_DURATION} > "${TEST_RUN_LOG_FOLDER}/mpstat-sender-${current_test_threads}.log" &

    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -f -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "sar -n DEV 1 ${INDIVIDUAL_TEST_DURATION} > ${TEST_RUN_LOG_FOLDER}/sar-receiver-${current_test_threads}.log"
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -f -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "dstat -dam > ${TEST_RUN_LOG_FOLDER}/dstat-receiver-${current_test_threads}.log"
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -f -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "mpstat -P ALL 1 ${INDIVIDUAL_TEST_DURATION} > ${TEST_RUN_LOG_FOLDER}/mpstat-receiver-${current_test_threads}.log"

    run_iperf_parallel ${current_test_threads}

    sleep 5
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -f -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "netstat -su > ${TEST_RUN_LOG_FOLDER}/receiver-${number_of_connections}-udp-tatistics.log"
    pkill -f iperf3
    pkill -x sar
    pkill -x dstat
    pkill -x mpstat
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "pkill -f iperf3"
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "pkill -x sar"
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "pkill -x dstat"
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "pkill -x mpstat"
    sleep 5
}

# Start iPerf3 client instances
LogMsg "Starting iPerf3 in client mode"
previous_tx_bytes=$(get_tx_bytes)
previous_tx_pkts=$(get_tx_pkts)
mkdir ${TEST_RUN_LOG_FOLDER}
for number_of_connections in "${IPERF3_TEST_CONNECTION_POOL[@]}"
do
    run_iperf_udp ${number_of_connections}
    sleep 15
done

current_tx_bytes=$(get_tx_bytes)
current_tx_pkts=$(get_tx_pkts)
bytes_new=`(expr $current_tx_bytes - $previous_tx_bytes)`
pkts_new=`(expr $current_tx_pkts - $previous_tx_pkts)`
avg_pkt_size=$(echo "scale=2;$bytes_new/$pkts_new/1024" | bc)

if [ -f iPerf3_Client_Logs.zip ]
then
    rm -f iPerf3_Client_Logs.zip
fi
# Test Finished. Collect logs, zip client side logs
sleep 30

ethtool -S eth1 > ${TEST_RUN_LOG_FOLDER}/sender-ethtool-eth1.log
ethtool -S enP2p0s2 > ${TEST_RUN_LOG_FOLDER}/sender-ethtool-enP2p0s2.log
ssh -i "$HOME"/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "ethtool -S eth1 > ~/${TEST_RUN_LOG_FOLDER}/receiver-ethtool-eth1.log"
ssh -i "$HOME"/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "ethtool -S enP2p0s2 > ~/${TEST_RUN_LOG_FOLDER}/receiver-ethtool-enP2p0s2.log"
scp -i "$HOME"/.ssh/${SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:/root/${TEST_RUN_LOG_FOLDER}/*receiver* /root/${TEST_RUN_LOG_FOLDER}
zip -r iPerf3_Client_Logs.zip ${TEST_RUN_LOG_FOLDER}/*

# Get logs from server side
ssh -i "$HOME"/.ssh/"${SSH_PRIVATE_KEY}" -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "echo 'if [ -f iPerf3_Server_Logs.zip  ]; then rm -f iPerf3_Server_Logs.zip; fi' | at now"
ssh -i "$HOME"/.ssh/"${SSH_PRIVATE_KEY}" -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "echo 'zip -r ~/iPerf3_Server_Logs.zip ~/${TEST_RUN_LOG_FOLDER}/*' | at now"
sleep 30
scp -i "$HOME"/.ssh/"${SSH_PRIVATE_KEY}" -o StrictHostKeyChecking=no -r ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:~/iPerf3_Server_Logs.zip ~/iPerf3_Server_Logs.zip
scp -i "$HOME"/.ssh/"${SSH_PRIVATE_KEY}" -o StrictHostKeyChecking=no -r ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:~/iPerf3_Panorama_ServerSideScript.log ~/iPerf3_Panorama_ServerSideScript.log

UpdateSummary "Distribution: $DISTRO"
UpdateSummary "Kernel: $(uname -r)"
UpdateSummary "Test Protocol: ${IPERF3_PROTOCOL}"
UpdateSummary "Packet size: $avg_pkt_size"
UpdateSummary "IPERF3_BUFFER: ${IPERF3_BUFFER}"

LogMsg "Test completed successfully"
UpdateTestState $ICA_TESTCOMPLETED
exit 0

