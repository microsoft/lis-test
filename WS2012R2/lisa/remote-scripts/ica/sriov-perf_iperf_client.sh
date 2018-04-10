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
# sriov-perf_iperf_client.sh
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
#     BOND_IP2: the ipv4 address of the server
#     INDIVIDUAL_TEST_DURATION: the test duration of each iperf3 test
#     CONNECTIONS_PER_IPERF3: how many iPerf connections will be created by iPerf3 client to a single iperf3 server
#     REMOTE_USER: the user name used to copy test signal file to server side
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
dos2unix perf_utils.sh
dos2unix SR-IOV_Utils.sh

# Source perf_utils.sh
. perf_utils.sh || {
    echo "Error: unable to source perf_utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Source perf_utils.sh
. SR-IOV_Utils.sh || {
    echo "Error: Unable to source SR-IOV_Utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

#Apling performance parameters
setup_sysctl
if [ $? -ne 0 ]; then
    echo "Unable to add performance parameters."
    LogMsg "Unable to add performance parameters."
    UpdateTestState $ICA_TESTABORTED
fi

# Allowing more time for the 2nd VM to start
sleep 90

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

#
# Make sure the required test parameters are defined
#
if [ "${IPERF_PACKAGE:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the IPERF_PACKAGE test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${BOND_IP1:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the BOND_IP1 test parameter is missing"
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

if [ "${BOND_IP2:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the BOND_IP2 test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${IPERF3_PROTOCOL:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Info: no IPERF3_PROTOCOL was specified, assuming default TCP"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
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

if [ "${REMOTE_USER:="UNDEFINED"}" = "UNDEFINED" ]; then
    REMOTE_USER="root"
    msg="Warning: the REMOTE_USER test parameter is missing and the default value will be used: ${REMOTE_USER}."
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


if [[ ${config_sriov} -eq "yes" ]]; then
    # Check the parameters in constants.sh
    Check_SRIOV_Parameters
    if [ $? -ne 0 ]; then
        msg="ERROR: The necessary parameters are not present in constants.sh. Please check the xml test file"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi

    # Check if the SR-IOV driver is in use
    VerifyVF
    if [ $? -ne 0 ]; then
        msg="ERROR: VF is not loaded! Make sure you are using compatible hardware"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi

    # Run the bonding script. Make sure you have this already on the system
    # Note: The location of the bonding script may change in the future
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
    ConfigureBond
    if [ $? -ne 0 ]; then
        msg="ERROR: Could not set a static IP to the bond!"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
    fi
fi
# Extract the files from the IPerf tar package
#
tar -xzf ./${IPERF_PACKAGE}
if [ $? -ne 0 ]; then
    msg="Error: Unable extract ${IPERF_PACKAGE}"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 70
fi

#
# Get the root directory of the tarball
#
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

iptables -F
ip6tables -F

#
# Distro specific setup
#
GetDistro

case "$DISTRO" in
debian*|ubuntu*)
    LogMsg "Updating apt repositories"
    apt update & wait

    LogMsg "Installing sar on Ubuntu"
    apt install sysstat -y
    if [ $? -ne 0 ]; then
        msg="Error: sysstat failed to install"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 85
    fi
    apt install zip build-essential -y
    if [ $? -ne 0 ]; then
        msg="Error: Build essential failed to install"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 85
    fi
    service ufw status
    if [ $? -ne 3 ]; then
        LogMsg "Disabling firewall on Ubuntu"
        service ufw stop
        if [ $? -ne 0 ]; then
                msg="Error: Failed to stop ufw"
                LogMsg "${msg}"
                echo "${msg}" >> ~/summary.log
        fi
    fi
    ;;
redhat_5|redhat_6|centos_6|centos_5)
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
    fi
    LogMsg "Check iptables status on RHEL"
	systemctl status firewalld
    if [ $? -ne 3 ]; then
        LogMsg "Disabling firewall on Redhat 7"
        systemctl disable firewalld
        if [ $? -ne 0 ]; then
            msg="Error: Failed to stop firewalld"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 85
        fi
        systemctl stop firewalld
        if [ $? -ne 0 ]; then
            msg="Error: Failed to turn off firewalld. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
    fi

    LogMsg "Check iptables status on RHEL7"
    service iptables status
    if [ $? -ne 3 ]; then
        iptables -F;
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush iptables rules. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
        chkconfig iptables off
        if [ $? -ne 0 ]; then
            msg="Error: Failed to turn off iptables. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
    fi

    LogMsg "Check ip6tables status on RHEL7"
    service ip6tables status
    if [ $? -ne 3 ]; then
        ip6tables -F;
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush ip6tables rules. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
        chkconfig ip6tables off
        if [ $? -ne 0 ]; then
            msg="Error: Failed to turn off iptables. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
    fi
    ;;

    suse_12)
        # Install gcc which is required to build iperf3
        zypper --non-interactive install gcc

        #Check if sysstat package is installed
        command -v sar
        if [ $? -ne 0 ]; then
            msg="Error: Sysstat (sar) is not installed. Please install it before running the performance tests!"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 82
        fi

        LogMsg "Check iptables status on SLES"
        service SuSEfirewall2 status
        if [ $? -ne 3 ]; then
            iptables -F;
            if [ $? -ne 0 ]; then
                msg="Error: Failed to flush iptables rules. Continuing"
                LogMsg "${msg}"
                echo "${msg}" >> ~/summary.log
            fi
            service SuSEfirewall2 stop
            if [ $? -ne 0 ]; then
                msg="Error: Failed to stop iptables"
                LogMsg "${msg}"
                echo "${msg}" >> ~/summary.log
                UpdateTestState $ICA_TESTFAILED
                exit 85
            fi
            chkconfig SuSEfirewall2 off
            if [ $? -ne 0 ]; then
                msg="Error: Failed to turn off iptables. Continuing"
                LogMsg "${msg}"
                echo "${msg}" >> ~/summary.log
            fi
        fi
    ;;

esac

#
# Build iperf
#
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

# Make all bash scripts executable
cd ~
dos2unix ~/*.sh
chmod 755 ~/*.sh

function get_tx_bytes() {
    # RX bytes:66132495566 (66.1 GB)  TX bytes:3067606320236 (3.0 TB)
    Tx_bytes=`ifconfig $ETH_NAME | grep "TX bytes"   | awk -F':' '{print $3}' | awk -F' ' ' {print $1}'`

    if [ "x$Tx_bytes" == "x" ]
    then
        #TX packets 223558709  bytes 15463202847 (14.4 GiB)
        Tx_bytes=`ifconfig $ETH_NAME| grep "TX packets"| awk '{print $5}'`
    fi
    echo $Tx_bytes
}

function get_tx_pkts() {
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
scp -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no ~/sriov-perf_iperf_server.sh ${REMOTE_USER}@[${STATIC_IP2}]:
if [ $? -ne 0 ]; then
    msg="Error: Unable to copy test scripts to target server machine: ${STATIC_IP2}. scp command failed."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 130
fi
scp -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no ~/${IPERF_PACKAGE} ${REMOTE_USER}@[${STATIC_IP2}]:
scp -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no ~/constants.sh ${REMOTE_USER}@[${STATIC_IP2}]:
scp -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no ~/utils.sh ${REMOTE_USER}@[${STATIC_IP2}]:


#
# Start iPerf in server mode on the Target server side
#
LogMsg "Starting iPerf in server mode on ${BOND_IP2}"
ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no ${REMOTE_USER}@${STATIC_IP2} "echo '~/sriov-perf_iperf_server.sh > iPerf3_Panorama_ServerSideScript.log' | at now"
if [ $? -ne 0 ]; then
    msg="Error: Unable to start iPerf3 server scripts on the target server machine"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 130
fi

#
# Wait for server to be ready
#
wait_for_server=600
server_state_file=serverstate.txt
while [ $wait_for_server -gt 0 ]; do
    # Try to copy and understand server state
    scp -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no ${REMOTE_USER}@[${STATIC_IP2}]:~/state.txt ~/${server_state_file}

    if [ -f ~/${server_state_file} ];
    then
        server_state=$(head -n 1 ~/${server_state_file})
        echo $server_state
        rm -rf ~/${server_state_file}
        if [ "$server_state" == "iPerf3Running" ];
        then
            break
        fi
    fi
    sleep 5
    wait_for_server=$(($wait_for_server - 5))
done

if [ $wait_for_server -eq 0 ] ;
then
    msg="Error: iperf3 server script has been triggered but not iperf3 are not in running state within ${wait_for_server} seconds."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 135
else
    LogMsg "iPerf3 servers are ready."
fi
#
# Start iPerf3 client instances
#
LogMsg "Starting iPerf3 in client mode"

previous_tx_bytes=$(get_tx_bytes)
previous_tx_pkts=$(get_tx_pkts)

i=0
mkdir -p ./${TEST_RUN_LOG_FOLDER}
while [ "x${IPERF3_TEST_CONNECTION_POOL[$i]}" != "x" ]
do
    port=8001
    echo "================================================="
    echo "Running Test: ${IPERF3_TEST_CONNECTION_POOL[$i]}"
    echo "================================================="

    touch ${TEST_SIGNAL_FILE}
    echo ${IPERF3_TEST_CONNECTION_POOL[$i]} > ${TEST_SIGNAL_FILE}
    scp -i "$HOME"/.ssh/"$sshKey" -v -o StrictHostKeyChecking=no ${TEST_SIGNAL_FILE} ${REMOTE_USER}@[${STATIC_IP2}]:
    sleep 15

    number_of_connections=${IPERF3_TEST_CONNECTION_POOL[$i]}
    bash ./perf_capturer.sh $INDIVIDUAL_TEST_DURATION ${TEST_RUN_LOG_FOLDER}/$number_of_connections &

    rm -rf the_generated_client.sh
    echo "./perf_run_parallelcommands.sh " > the_generated_client.sh

    while [ $number_of_connections -gt $CONNECTIONS_PER_IPERF3 ]; do
        number_of_connections=$(($number_of_connections-$CONNECTIONS_PER_IPERF3))
        echo " \"/root/${rootDir}/src/iperf3 -u ${IPERF3_PROTOCOL} -c $BOND_IP2 -p $port $ipVersion ${BANDWIDTH+-b ${BANDWIDTH}} -l ${IPERF3_BUFFER} -P $CONNECTIONS_PER_IPERF3 -t $INDIVIDUAL_TEST_DURATION --get-server-output -i ${INDIVIDUAL_TEST_DURATION} > /dev/null \" " >> the_generated_client.sh
        port=$(($port + 1))
    done

    if [ $number_of_connections -gt 0 ]
    then
        echo " \"/root/${rootDir}/src/iperf3 -u ${IPERF3_PROTOCOL} -c $BOND_IP2 -p $port $ipVersion ${BANDWIDTH+-b ${BANDWIDTH}} -l ${IPERF3_BUFFER} -P $number_of_connections  -t $INDIVIDUAL_TEST_DURATION --get-server-output -i ${INDIVIDUAL_TEST_DURATION} > /dev/null \" " >> the_generated_client.sh
    fi

    sed -i ':a;N;$!ba;s/\n/ /g'  ./the_generated_client.sh
    chmod 755 the_generated_client.sh

    cat ./the_generated_client.sh
    ./the_generated_client.sh > ${TEST_RUN_LOG_FOLDER}/${IPERF3_TEST_CONNECTION_POOL[$i]}-iperf3.log
    i=$(($i + 1))

    echo "Clients test just finished. Sleep 10 seconds for next test..."
    sleep 60
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
sleep 60

zip -r iPerf3_Client_Logs.zip ${TEST_RUN_LOG_FOLDER}/*

# Get logs from server side
ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no ${REMOTE_USER}@${STATIC_IP2} "echo 'if [ -f iPerf3_Server_Logs.zip  ]; then rm -f iPerf3_Server_Logs.zip; fi' | at now"
ssh -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no ${REMOTE_USER}@${STATIC_IP2} "echo 'zip -r ~/iPerf3_Server_Logs.zip ~/${TEST_RUN_LOG_FOLDER}/*' | at now"
sleep 60
scp -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no -r ${REMOTE_USER}@[${STATIC_IP2}]:~/iPerf3_Server_Logs.zip ~/iPerf3_Server_Logs.zip
scp -i "$HOME"/.ssh/"$sshKey" -o StrictHostKeyChecking=no -r ${REMOTE_USER}@[${STATIC_IP2}]:~/iPerf3_Panorama_ServerSideScript.log ~/iPerf3_Panorama_ServerSideScript.log

UpdateSummary "Distribution: $DISTRO"
UpdateSummary "Kernel: $(uname -r)"
UpdateSummary "Test Protocol: ${IPERF3_PROTOCOL}"
UpdateSummary "Packet size: $avg_pkt_size"
UpdateSummary "IPERF3_BUFFER: ${IPERF3_BUFFER}"

LogMsg "Test completed successfully"
UpdateTestState $ICA_TESTCOMPLETED
exit 0
