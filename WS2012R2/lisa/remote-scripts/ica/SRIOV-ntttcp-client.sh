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
# SRIOV-ntttcp-client.sh
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
dos2unix perf_utils.sh
dos2unix SR-IOV_Utils.sh

# Source perf_utils.sh
. perf_utils.sh || {
    echo "ERROR: unable to source perf_utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Source perf_utils.sh
. SR-IOV_Utils.sh || {
    echo "ERROR: Unable to source SR-IOV_Utils.sh!"
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

#Create log folder
if [ -d  $log_folder ]; then
    echo "File $log_folder exists: will be deleted."
    LogMsg "File $log_folder exists." >> ~/summary.log
    rm -rf $log_folder
else
    mkdir $log_folder
fi
eth_log="$HOME/$log_folder/eth_report.log"
echo "#test_connections    throughput_gbps    average_packet_size" > $eth_log

#
# Make sure the required test parameters are defined
#

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

CheckIPV6 "$BOND_IP1"
if [[ $? -eq 0 ]]; then
    CheckIPV6 "$BOND_IP2"
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
#Check distro
#
iptables -F
ip6tables -F
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
    LogMsg "Installing sar on Ubuntu"
    apt-get install bc
    if [ $? -ne 0 ]; then
        msg="ERROR: sysstat failed to install"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 85
    fi
    apt-get install build-essential git -y
    if [ $? -ne 0 ]; then
        msg="ERROR: Build essential failed to install"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 85
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
    #Installing monitoring tools
    yum install -y bc sysstat
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
    LogMsg "Check iptables status on SLES 12"
    service SuSEfirewall2 status
    if [ $? -ne 3 ]; then
        iptables -F;
        if [ $? -ne 0 ]; then
            msg="ERROR: Failed to flush iptables rules. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
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
ulimit -n 30480
if [ $? -ne 0 ]; then
    LogMsg "ERROR: Unable to enlarged system limit"
    UpdateTestState $ICA_TESTABORTED
fi

#Install LAGSCOPE tool for latency
setup_lagscope
if [ $? -ne 0 ]; then
    echo "Unable to compile lagscope."
    LogMsg "Unable to compile lagscope."
    UpdateTestState $ICA_TESTABORTED
fi

#Install NTTTCP for network throughput
setup_ntttcp
if [ $? -ne 0 ]; then
    echo "Unable to compile ntttcp-for-linux."
    LogMsg "Unable to compile ntttcp-for-linux."
    UpdateTestState $ICA_TESTABORTED
fi
dos2unix ~/*.sh
chmod 755 ~/*.sh

# set static IPs for test interfaces
LogMsg "Copy files to server: ${STATIC_IP2}"
scp -i $HOME/.ssh/$sshKey -v -o StrictHostKeyChecking=no ~/SRIOV-ntttcp-server.sh ${REMOTE_USER}@[${STATIC_IP2}]:
if [ $? -ne 0 ]; then
    msg="ERROR: Unable to copy test scripts to target server machine: ${STATIC_IP2}. scp command failed."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 130
fi
scp -i $HOME/.ssh/$sshKey -v -o StrictHostKeyChecking=no ~/constants.sh ${REMOTE_USER}@[${STATIC_IP2}]:
scp -i $HOME/.ssh/$sshKey -v -o StrictHostKeyChecking=no ~/utils.sh ${REMOTE_USER}@[${STATIC_IP2}]:
scp -i $HOME/.ssh/$sshKey -v -o StrictHostKeyChecking=no ~/perf_utils.sh ${REMOTE_USER}@[${STATIC_IP2}]:


#
# Start ntttcp in server mode on the Target server side
#
LogMsg "Starting ntttcp in server mode on ${BOND_IP2}"
ssh -i $HOME/.ssh/$sshKey -v -o StrictHostKeyChecking=no ${REMOTE_USER}@${STATIC_IP2} "echo '~/SRIOV-ntttcp-server.sh > ntttcp_ServerSideScript.log' | at now"
if [ $? -ne 0 ]; then
    msg="ERROR: Unable to start ntttcp server scripts on the target server machine"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 130
fi

# Wait for server to be ready
wait_for_server=600
server_state_file=serverstate.txt
while [ $wait_for_server -gt 0 ]; do
    # Try to copy and understand server state
    scp -i $HOME/.ssh/$sshKey -v -o StrictHostKeyChecking=no ${REMOTE_USER}@[${STATIC_IP2}]:~/state.txt ~/${server_state_file}

    if [ -f ~/${server_state_file} ];
    then
        server_state=$(head -n 1 ~/${server_state_file})
        echo $server_state
        rm -rf ~/${server_state_file}
        if [ "$server_state" == "NtttcpRunning" ];
        then
            break
        fi
    fi
    sleep 5
    wait_for_server=$(($wait_for_server - 5))
done

if [ $wait_for_server -eq 0 ] ;
then
    msg="ERROR: ntttcp server script has been triggered but are not in running state within ${wait_for_server} seconds."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 135
else
    LogMsg "Ntttcp server are ready."
fi

#Starting test
previous_tx_bytes=$(get_tx_bytes $ETH_NAME)
previous_tx_pkts=$(get_tx_pkts $ETH_NAME)
ssh -i $HOME/.ssh/${sshKey} -v -o StrictHostKeyChecking=no ${REMOTE_USER}@${STATIC_IP2} "mkdir /root/$log_folder"

i=0
while [ "x${TEST_THREADS[$i]}" != "x" ]
do
    current_test_threads=${TEST_THREADS[$i]}
    if [ $current_test_threads -lt $MAX_THREADS ]
    then
        num_threads_P=$current_test_threads
        num_threads_n=1
    else
        num_threads_P=$MAX_THREADS
        num_threads_n=$(($current_test_threads / $num_threads_P))
    fi

    echo "======================================"
    echo "Running Test: $num_threads_P X $num_threads_n"
    echo "======================================"

    ssh -i $HOME/.ssh/${sshKey} -v -o StrictHostKeyChecking=no ${REMOTE_USER}@${STATIC_IP2} "pkill -f ntttcp"
    ssh -i $HOME/.ssh/${sshKey} -v -o StrictHostKeyChecking=no ${REMOTE_USER}@${STATIC_IP2} "ntttcp -r${BOND_IP2} -P $num_threads_P ${ipVersion} -e > $HOME/$log_folder/ntttcp-receiver-p${num_threads_P}X${num_threads_n}.log" &

    ssh -i $HOME/.ssh/${sshKey} -v -o StrictHostKeyChecking=no ${REMOTE_USER}@${STATIC_IP2} "pkill -f lagscope"
    ssh -i $HOME/.ssh/${sshKey} -v -o StrictHostKeyChecking=no ${REMOTE_USER}@${STATIC_IP2} "lagscope -r${BOND_IP2} ${ipVersion}" &

    sleep 2
    lagscope -s${BOND_IP2} -t ${TEST_DURATION} -V ${ipVersion} > "./$log_folder/lagscope-ntttcp-p${num_threads_P}X${num_threads_n}.log" &
    ntttcp -s${BOND_IP2} -P $num_threads_P -n $num_threads_n -t ${TEST_DURATION} ${ipVersion} -f > "./$log_folder/ntttcp-sender-p${num_threads_P}X${num_threads_n}.log"

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

    echo "current test finished. wait for next one... "
    i=$(($i + 1))
    sleep 5
done
sts=$?
if [ $sts -eq 0 ]; then
    LogMsg "Ntttcp succeeded with all connections."
    echo "Ntttcp succeeded with all connections." >> ~/summary.log
    cd $HOME
    scp -i $HOME/.ssh/${sshKey} -v -o StrictHostKeyChecking=no ${REMOTE_USER}@[${STATIC_IP2}]:/root/$log_folder/* /root/$log_folder
    if [ $? -ne 0 ]; then
        echo "ERROR: Unable to trnsfer server side logs."
        UpdateTestState $ICA_TESTFAILED
    fi
    zip -r $log_folder.zip $log_folder/*
    sleep 20
    UpdateTestState $ICA_TESTCOMPLETED
else 
    LogMsg "Something gone wrong. Please re-run.."
    echo "Something gone wrong. Please re-run.." >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
fi
