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
# 
# Description:
#     Running ab performance tool.
#
# Parameters:
#     APACHE_SERVER: the ipv4 address of the server
#     SERVER_USERNAME: the user name used to copy test signal file to server side
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
    NETMASK="255.255.255.2"
    msg="Error: the NETMASK test parameter is missing, default value will be used: 255.255.255.0"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ "${APACHE_SERVER:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the APACHE_SERVER test parameter is missing"
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

if [ "${SERVER_USERNAME:="UNDEFINED"}" = "UNDEFINED" ]; then
    SERVER_USERNAME="root"
    msg="Warning: the SERVER_USERNAME test parameter is missing and the default value will be used: ${SERVER_USERNAME}."
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

echo "AB client test interface ip           = ${STATIC_IP}"
echo "Apache server ip           = ${STATIC_IP2}"
echo "Apache server test interface ip        = ${APACHE_SERVER}"
echo "user name on server       = ${SERVER_USERNAME}"


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
    fi

    : $((__iterator++))

done

LogMsg "Copy files to server: ${STATIC_IP2}"
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no ~/performance_ab_server.sh ${SERVER_USERNAME}@[${STATIC_IP2}]:
if [ $? -ne 0 ]; then
    msg="Error: Unable to copy test scripts to target server machine: ${STATIC_IP2}. scp command failed."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 130
fi
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no ~/constants.sh ${SERVER_USERNAME}@[${STATIC_IP2}]:
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no ~/utils.sh ${SERVER_USERNAME}@[${STATIC_IP2}]:

#
# Start apache server configuration on the Target server side
#
LogMsg "Starting apache configuration script to server"
ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no ${SERVER_USERNAME}@${STATIC_IP2} "echo '~/performance_ab_server.sh > APACHE_ServerSideScript.log' | at now"
if [ $? -ne 0 ]; then
    msg="Error: Unable to start script on the target server machine"
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
    scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no ${SERVER_USERNAME}@[${STATIC_IP2}]:~/state.txt ~/${server_state_file}

    if [ -f ~/${server_state_file} ];
    then
        server_state=$(head -n 1 ~/${server_state_file})
        echo $server_state
        rm -rf ~/${server_state_file}
        if [ "$server_state" == "APACHERunning" ];
        then
            break
        fi
    fi
    sleep 5
    wait_for_server=$(($wait_for_server - 5))
done

if [ $wait_for_server -eq 0 ] ;
then
    msg="Error: server script has been triggered but are not in running state within ${wait_for_server} seconds."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 135
else
    LogMsg "APACHE server is ready."
fi
#
# Start ab test
#
sleep 3

#
# Distro specific setup
#
GetDistro

case "$DISTRO" in
debian*|ubuntu*)
    apt-get update
    LogMsg "Info: -----------------------------------------"
    LogMsg "Info: Apache utility tool installation on client side"
    apt-get install -y apache2-utils
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to install apache2-utils."
        UpdateTestState $ICA_TESTFAILED
        exit 20          
    fi
    ;;
redhat*|centos*)
    LogMsg "Info: -----------------------------------------"
    LogMsg "Info: Apache utility tool installation on client side"
    yum install -y httpd-tools
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to install httpd tools."
        UpdateTestState $ICA_TESTFAILED
        exit 20     
    fi
    ;;
suse*)
    LogMsg "Info: -----------------------------------------"
    LogMsg "Info: Apache utility tool installation on client side"
    zypper --non-interactive install apache2-utils
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to install apache2-utils."
        UpdateTestState $ICA_TESTFAILED
        exit 20          
    fi
    ;;
esac

LogMsg "Starting the benchmark"
ab -n ${APACHE_TEST_NUM_REQUESTS} -c ${APACHE_TEST_NUM_CONCURRENCY} http://${APACHE_SERVER}/test.dat >> summary.log
if [ $? -ne 0 ]; then
    msg="Error: Could not start ab performance test."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 150
fi

# Test Finished. Collect logs, zip client side logs
# Get logs from server side
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no -r ${SERVER_USERNAME}@[${STATIC_IP2}]:~/APACHE_ServerSideScript.log ~/APACHE_ServerSideScript.log

UpdateSummary "Distribution: $DISTRO"
UpdateSummary "Kernel: $(uname -r)"

#
# If we made it here, everything worked
#
#Shut down dependency VM
ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ${SERVER_USERNAME}@${STATIC_IP2} "init 0 | at now"

LogMsg "Test completed successfully"
UpdateTestState $ICA_TESTCOMPLETED
exit 0