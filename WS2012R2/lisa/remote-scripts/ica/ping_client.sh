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
# ping_client.sh
#
# Parameters:
#     VM2TEST_IP: the ipv4 address of the server
#     SERVER_OS_USERNAME: the user name used to copy test signal file to server side
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

if [ "${VM2TEST_IP:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the VM2TEST_IP test parameter is missing"
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

#Get test synthetic interface
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

echo "Ping client test interface ip           = ${STATIC_IP}"
echo "Ping server ip           = ${STATIC_IP2}"
echo "Ping server test interface ip        = ${VM2TEST_IP}"
echo "user name on server       = ${SERVER_OS_USERNAME}"
echo "Ping count              = ${PING_COUNT}"

#
# Check for internet protocol version
#
CheckIPV6 "$STATIC_IP"
if [[ $? -eq 0 ]]; then
    CheckIPV6 "$VM2TEST_IP"
    if [[ $? -eq 0 ]]; then
        ipVersion="6"
        
    else
        msg="Error: Not both test IPs are IPV6"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 60
    fi
else
    ipVersion=$null
fi

GetDistro

case "$DISTRO" in
debian*|ubuntu*)
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
redhat_5|redhat_6)
    LogMsg "Check iptables status on RHEL"
    service iptables status
    if [ $? -ne 3 ]; then
        LogMsg "Disabling firewall on Redhat"
        iptables -F
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush iptables rules. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
        service iptables stop
        if [ $? -ne 0 ]; then
            msg="Error: Failed to stop iptables"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 85
        fi
		service ip6tables stop
        if [ $? -ne 0 ]; then
            msg="Error: Failed to stop ip6tables"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 85
        fi
        chkconfig iptables off
        if [ $? -ne 0 ]; then
            msg="Error: Failed to turn off iptables. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
    fi
    ;;
redhat_7)
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

    LogMsg "Check iptables status on RHEL 7"
    service iptables status
    if [ $? -ne 3 ]; then
        iptables -F;
        if [ $? -ne 0 ]; then
            msg="Error: Failed to flush iptables rules. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
        service iptables stop
        if [ $? -ne 0 ]; then
            msg="Error: Failed to stop iptables"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 85
        fi
        chkconfig iptables off
        if [ $? -ne 0 ]; then
            msg="Error: Failed to turn off iptables. Continuing"
            LogMsg "${msg}"
            echo "${msg}" >> ~/summary.log
        fi
    fi
    ;;

    suse_12)
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

# Make all bash scripts executable
cd ~
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
                    else 
                        PING_INTERFACE=${SYNTH_NET_INTERFACES[$__iterator]}
    fi

    : $((__iterator++))

done

LogMsg "Copy files to server: ${STATIC_IP2}"
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ~/ping_server.sh ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:
if [ $? -ne 0 ]; then
    msg="Error: Unable to copy test scripts to VM1: ${STATIC_IP2}. scp command failed."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 130
fi
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ~/constants.sh ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ~/utils.sh ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:

#
# Start ping on VM2.
#
 LogMsg "Preparing for ping  VM server on ${STATIC_IP2}"
ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "echo '~/ping_server.sh > ping_logServer.log' | at now"
 if [ $? -ne 0 ]; then
     msg="Error: Unable to run ping_server scripts on the target server machine"
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
    scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:~/state.txt ~/${server_state_file}

    if [ -f ~/${server_state_file} ];
    then
        server_state=$(head -n 1 ~/${server_state_file})
        echo $server_state
        rm -rf ~/${server_state_file}
        if [ "$server_state" == "PingRunning" ];
        then
            break
        fi
    fi
    sleep 5
    wait_for_server=$(($wait_for_server - 5))
done

if [ $wait_for_server -eq 0 ] ;
then
    msg="Error: ping server script has been triggered but are not in running state within ${wait_for_server} seconds."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 135
else
    LogMsg "Ping servers are ready."
fi
#
# Start ping between VMs
#
sleep 3

LogMsg "Starting ping between VMs."
ping${ipVersion} -I $PING_INTERFACE ${VM2TEST_IP} -c $PING_COUNT > ping_logs.log 2>&1
if [ $? -ne 0 ]; then
    msg="Error: Unable to ping."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 140
fi
# Test Finished. Collect logs, zip client side logs
# Get logs from server side
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no -r ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:~/ping_logServer.log ~/ping_logServer.log
RESULT_STATISTICS=$(cat ping_logs.log |grep statistics)
RESULT_PACK=$(cat ping_logs.log |grep packets) 
RESULT=$(cat ping_logs.log |grep rtt)

UpdateSummary "$RESULT_STATISTICS"
UpdateSummary "$RESULT_PACK"
UpdateSummary "$RESULT"
UpdateSummary " "
UpdateSummary "Distribution: $DISTRO"
UpdateSummary "Kernel: $(uname -r)"

#
# If we made it here, everything worked
#
Shut down dependency VM
ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "reboot | at now"
if [ $? -ne 0 ]; then
    msg="Warning: Unable to shut down target server machine"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

LogMsg "Test completed successfully"
UpdateTestState $ICA_TESTCOMPLETED
exit 0
