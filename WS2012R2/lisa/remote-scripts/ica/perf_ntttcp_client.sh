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
#     For the test to run you have to place the iperf tool package in the
#     Tools folder under lisa.
#
# Requirements:
#   The sar utility must be installed, package named sysstat
#
# Parameters:
#     IPERF3_SERVER_IP: the ipv4 address of the server
#     SERVER_OS_USERNAME: the user name used to copy test signal file to server side
#
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
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

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

function get_tx_bytes(){
    # RX bytes:66132495566 (66.1 GB)  TX bytes:3067606320236 (3.0 TB)
    Tx_bytes=`ifconfig $ETH_NAME | grep "TX bytes"   | awk -F':' '{print $3}' | awk -F' ' ' {print $1}'`
    
    if [ "x$Tx_bytes" == "x" ]
    then
        #TX packets 223558709  bytes 15463202847 (14.4 GiB)
        Tx_bytes=`ifconfig $ETH_NAME| grep "TX packets"| awk '{print $5}'`
        echo $Tx_bytes
    fi    
}

function get_tx_pkts(){
    # TX packets:543924452 errors:0 dropped:0 overruns:0 carrier:0
    Tx_pkts=`ifconfig $ETH_NAME | grep "TX packets" | awk -F':' '{print $2}' | awk -F' ' ' {print $1}'`

    if [ "x$Tx_pkts" == "x" ]
    then
        #TX packets 223558709  bytes 15463202847 (14.4 GiB)
        Tx_pkts=`ifconfig $ETH_NAME| grep "TX packets"| awk '{print $3}'`
        echo $Tx_pkts
    fi    
}

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

if [ "${SERVER_IP:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the SERVER_IP test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${STATIC_IP2:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the STATIC_IP2 test parameter is missing"
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

declare __iface_ignore

# Parameter provided in constants file
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

    # Get the interface associated with the given ipv4
    __iface_ignore=$(ip -o addr show | grep "$ipv4" | cut -d ' ' -f2)
fi

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

echo "Ntttcp client test interface ip           = ${STATIC_IP}"
echo "Ntttcp server ip           = ${STATIC_IP2}"
echo "Ntttcp server test interface ip        = ${SERVER_IP}"
echo "Test duration       = ${TEST_DURATION}"
echo "Test Threads       = ${TEST_THREADS}"
echo "Max threads       = ${MAX_THREADS}"
echo "user name on server       = ${SERVER_OS_USERNAME}"
echo "Test Interface       = ${ETH_NAME}"

#
# Check for internet protocol version
#
CheckIPV6 "$STATIC_IP"
if [[ $? -eq 0 ]]; then
    CheckIPV6 "$SERVER_IP"
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
    ipVersion=
fi

#
#Check distro
#
GetDistro
case "$DISTRO" in
debian*|ubuntu*)
    LogMsg "Installing sar on Ubuntu"
    apt-get install sysstat -y
    if [ $? -ne 0 ]; then
        msg="Error: sysstat failed to install"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 85
    fi
    apt-get install build-essential git -y
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
                UpdateTestState $ICA_TESTFAILED
                exit 85
        fi
    fi
    ;;
redhat_5|redhat_6|centos_6)
    if [ "$DISTRO" == "redhat_6" ] || ["$DISTRO" == "centos_6" ]; then
        # Import CERN's GPG key
        rpm --import http://ftp.scientificlinux.org/linux/scientific/5x/x86_64/RPM-GPG-KEYs/RPM-GPG-KEY-cern
        if [ $? -ne 0 ]; then
            msg="Error: Failed to import CERN's GPG key."
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi

        # Save repository information
        wget -O /etc/yum.repos.d/slc6-devtoolset.repo http://linuxsoft.cern.ch/cern/devtoolset/slc6-devtoolset.repo
        if [ $? -ne 0 ]; then
            msg="Error: Failed to save repository information."
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi

        # The below will also install all the required dependencies
        yum install -y devtoolset-2-gcc-c++
        if [ $? -ne 0 ]; then
            msg="Error: Failed to install the new version of gcc."
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        echo "source /opt/rh/devtoolset-2/enable" >> /root/.bashrc
        source /root/.bashrc

        LogMsg "Disabling firewall on Redhat 6.x."
        echo "Disabling firewall on Redhat 6.x." >> ~/summary.log
        iptables -X; iptables -F
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush iptables rules. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
        service iptables stop
        if [ $? -ne 0 ]; then
            msg="Error: Failed to stop iptables and ip6tables."
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 85
        fi
        service ip6tables stop
         if [ $? -ne 0 ]; then
            msg="Error: Failed to stop ip6tables and ip6tables."
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 85
        fi
    else
        LogMsg "Iptables and ip6tables are disabled."
    fi
    ;;
redhat_7)
    LogMsg "Check firewalld status on RHEL 7.xx."
    systemctl status firewalld
    if [ $? -ne 3 ]; then
        LogMsg "Disabling firewall on Redhat 7.x"
        systemctl stop firewalld && systemctl disable firewalld
        if [ $? -ne 0 ]; then
            msg="Error: Failed to turn off firewalld. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
    fi
    LogMsg "Disable iptables on RHEL 7.x"
    service iptables stop
    if [ $? -ne 0 ]; then
        msg="Error: Failed to stop iptables and ip6tables."
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 85
    fi
    service ip6tables stop
    if [ $? -ne 0 ]; then
        msg="Error: Failed to stop ip6tables and ip6tables."
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 85
    fi    
    ;;
suse_12)
    LogMsg "Check iptables status on SLES 12"
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
#Install LAGSCOPE tool for latency
#
echo "Installing LAGSCOPE" 
if [ "$(which lagscope)" == "" ]; then
    rm -rf lagscope
    git clone https://github.com/Microsoft/lagscope
    if [ $? -eq 0 ]; then
        cd lagscope/src
        make && make install
        echo "LAGSCOPE installed.." >> ~/summary.log
        LogMsg "LAGSCOPE installed."
    fi        
cd $HOME
fi

#
#Install NTTTCP for network throughput
#

if [ "$(which ntttcp)" == "" ]; then
    rm -rf ntttcp-for-linux
    git clone https://github.com/Microsoft/ntttcp-for-linux.git
    cd ntttcp-for-linux/src
#    
########## Build ntttcp
#
    rm -f /usr/bin/ntttcp
    make
    if [ $? -ne 0 ]; then
        msg="Error: Unable to build ntttcp"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 100
    fi

    make install
    if [ $? -ne 0 ]; then
        msg="Error: Unable to install ntttcp"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 110
    fi
    cd $HOME
fi 
dos2unix ~/*.sh
chmod 755 ~/*.sh

# set static IPs for test interfaces
declare -i __iterator=0

while [ $__iterator -lt ${#SYNTH_NET_INTERFACES[@]} ]; do

    LogMsg "Trying to set an IP Address via static on interface ${SYNTH_NET_INTERFACES[$__iterator]}"
    CreateIfupConfigFile "${SYNTH_NET_INTERFACES[$__iterator]}" "static" $STATIC_IP $NETMASK

    if [ 0 -ne $? ]; then
        msg="Unable to set address for ${SYNTH_NET_INTERFACES[$__iterator]} through static"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 10
    fi

    : $((__iterator++))
done

LogMsg "Copy files to server: ${STATIC_IP2}"
scp -i $HOME/.ssh/$SSH_PRIVATE_KEY -v -o StrictHostKeyChecking=no ~/perf_ntttcp_server.sh ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:
if [ $? -ne 0 ]; then
    msg="Error: Unable to copy test scripts to target server machine: ${STATIC_IP2}. scp command failed."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 130
fi
scp -i $HOME/.ssh/$SSH_PRIVATE_KEY -v -o StrictHostKeyChecking=no ~/constants.sh ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:
scp -i $HOME/.ssh/$SSH_PRIVATE_KEY -v -o StrictHostKeyChecking=no ~/utils.sh ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:

#
# Start ntttcp in server mode on the Target server side
#
LogMsg "Starting ntttcp in server mode on ${STATIC_IP2}"
ssh -i $HOME/.ssh/$SSH_PRIVATE_KEY -v -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "echo '~/perf_ntttcp_server.sh > ntttcp_ServerSideScript.log' | at now"
if [ $? -ne 0 ]; then
    msg="Error: Unable to start ntttcp server scripts on the target server machine"
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
    scp -i $HOME/.ssh/$SSH_PRIVATE_KEY -v -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:~/state.txt ~/${server_state_file}

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
    msg="Error: ntttcp server script has been triggered but are not in running state within ${wait_for_server} seconds."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 135
else
    LogMsg "Ntttcp server are ready."
fi

#Starting test
previous_tx_bytes=$(get_tx_bytes)
previous_tx_pkts=$(get_tx_pkts)

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
    
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -v -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${SERVER_IP} "pkill -f ntttcp"
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -v -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${SERVER_IP} "ntttcp -r${SERVER_IP} -P $num_threads_P -t ${TEST_DURATION} ${ipVersion}" &

    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -v -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${SERVER_IP} "pkill -f lagscope"
    ssh -i $HOME/.ssh/${SSH_PRIVATE_KEY} -v -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${SERVER_IP} "lagscope -r${SERVER_IP} ${ipVersion}" &
    
    sleep 2
    lagscope -s${SERVER_IP} -t ${TEST_DURATION} -V ${ipVersion} > "./$log_folder/lagscope-ntttcp-p${num_threads_P}X${num_threads_n}.log" &
    ntttcp -s${SERVER_IP} -P $num_threads_P -n $num_threads_n -t ${TEST_DURATION} ${ipVersion} > "./$log_folder/ntttcp-p${num_threads_P}X${num_threads_n}.log"

    current_tx_bytes=$(get_tx_bytes)
    current_tx_pkts=$(get_tx_pkts)
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
    zip -r $log_folder.zip . -i $log_folder/*
    sleep 20
    UpdateTestState $ICA_TESTCOMPLETED
else 
    LogMsg "Something gone wrong. Please re-run.."
    echo "Something gone wrong. Please re-run.." >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
fi