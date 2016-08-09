#!/bin/bash

#######################################################################
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
#######################################################################

#######################################################################
#
# perf_mongodb_client.sh
#
# Description:
#    Install and configure mongodb so the mongoperf benchmark can
#    be run.  This script needs to be run on single VM.
#
#    mongo perf needs Java runtime is also installed.
#
#    Installing and configuring MongoDB consists of the following
#    steps:
#
#     1. Install a Java JDK
#     2. Download the MongoDB tar.gz archive on server side
#     3. Unpackage the Mongo archive on server side
#     4. Move the mongo directory to /usr/bin/
#     5. Update the ~/.bashrc file with mongodb specific exports
#     8. Start mongoperf test using ycsb client
#######################################################################
#
# Constants/Globals
#
ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during the setup of the test
ICA_TESTFAILED="TestFailed"        # Error occurred during the test

CONSTANTS_FILE="/root/constants.sh"
SUMMARY_LOG=~/summary.log
YCSB_LOG="ycsb.log"

#######################################################################
#
# LogMsg()
#
#######################################################################
LogMsg()
{
    echo `date "+%b %d %Y %T"` : "${1}"    # Add the time stamp to the log message
    echo "${1}" >> ~/mongodb.log
}

#######################################################################
#
# UpdateTestState()
#
#######################################################################
UpdateTestState()
{
    echo "${1}" > ~/state.txt
}

#######################################################################
#
# UpdateSummary()
#
#######################################################################
UpdateSummary()
{
    echo "${1}" >> ~/summary.log
}

#######################################################################
#
# Parse results into csv
#
#######################################################################
ParseResults()
{
    value=""
    for token in ${pattern[@]}; do
        value+=`cat ycsb.log | grep -i $token | cut -f 3 -d " " | cut -f 1 -d "."`
        value+=","
    done
    echo ${value::-1} >> mongodb.csv
}

#######################################################################
#
# ConfigRhel()
#
#######################################################################
ConfigRhel()
{
    LogMsg "ConfigRhel"

    #
    # Install Java
    #
    LogMsg "Check if Java is installed"

    javaInstalled=`which java`
    if [ ! $javaInstalled ]; then
        LogMsg "Installing Java"

        yum -y install java-1.7.0-openjdk
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to install Java"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi
    #
    # Figure out where Java is installed so we can configure a JAVA_HOME variable
    #
    LogMsg "Create JAVA_HOME variable"

    javaConfig=`echo "" | update-alternatives --config java | grep "*"`
    tokens=( $javaConfig )
    javaPath=${tokens[2]}
    if [ ! -e $javaPath ]; then
        LogMsg "Error: Unable to find the Java install path"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    temp=`dirname $javaPath`
    JAVA_HOME=`dirname $temp`
    if [ ! -e $JAVA_HOME ]; then
        LogMsg "Error: Invalid JAVA_HOME computed: ${JAVA_HOME}"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
}

#######################################################################
#
# ConfigSles()
#
#######################################################################
ConfigSles()
{
    LogMsg "ConfigSles"

    #
    # Install Java
    #
    LogMsg "Check if Java is installed"

    javaInstalled=`which java`
    if [ ! $javaInstalled ]; then
        LogMsg "Installing Java"

        zypper --non-interactive install jre-1.7.0
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to install java"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi
    #
    # Figure out where Java is installed so we can configure a JAVA_HOME variable
    #
    javaConfig=`update-alternatives --config java`
    tempHome=`echo $javaConfig | cut -f 2 -d ':' | cut -f 2 -d ' '`

    if [ ! -e $tempHome ]; then
        LogMsg "Error: The Java directory '${tempHome}' does not exist"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    temp1=`dirname $tempHome`
    JAVA_HOME=`dirname $temp1`

    if [ ! -e $JAVA_HOME ]; then
        LogMsg "Error: Invalid JAVA_HOME computed: ${JAVA_HOME}"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
}

#######################################################################
#
# ConfigUbuntu()
#
#######################################################################
ConfigUbuntu()
{
    LogMsg "ConfigUbuntu"

    #
    # Install Java
    #
    LogMsg "Check if Java is installed"

    javaInstalled=`which java`
    if [ ! $javaInstalled ]; then
        LogMsg "Installing Java"
        apt-get update
        apt-get -y install default-jdk
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to install java"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi
    #
    # Figure out where Java is installed so we can configure a JAVA_HOME variable
    #
    javaConfig=`update-alternatives --config java`
    tempHome=`echo $javaConfig | cut -f 2 -d ':' | cut -f 2 -d ' '`
    if [ ! -e $tempHome ]; then
        LogMsg "Error: The Java directory '${tempHome}' does not exist"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    temp1=`dirname $tempHome`
    temp2=`dirname $temp1`
    JAVA_HOME=`dirname $temp2`
    if [ ! -e $JAVA_HOME ]; then
        LogMsg "Error: Invalid JAVA_HOME computed: ${JAVA_HOME}"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
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
        LogMsg "UtilsInit returned an unknown error. Aborting..."
        UpdateSummary "UtilsInit returned an unknown error. Aborting..."
        SetTestStateAborted
        exit 6
        ;;
esac

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

if [ ! ${MONGODB_VERSION} ]; then
    errMsg="The MONGODB_VERSION test parameter is not defined. Setting as 3.2.8 "
    MONGODB_VERSION=3.2.8
    LogMsg "${errMsg}"
    echo "${errMsg}" >> ~/summary.log
fi

if [ ! ${YCSB_VERSION} ]; then
    errMsg="The YCSB_VERSION test parameter is not defined. Setting as default 0.5.0 "
    YCSB_VERSION=0.5.0
    LogMsg "${errMsg}"
    echo "${errMsg}" >> ~/summary.log
fi

if [ ! ${MD_SERVER} ]; then
    nThreads=16
    LogMsg "Info : nThreads not defined in constants.sh. Setting as ${nThreads}"
fi

if [ "${threads:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter threads is not defined in constants file. Default 1 thread."
    LogMsg "$msg"
    echo $msg >> ~/summary.log
    exit 30

fi

if [ "${pattern:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter tokens is not defined in constants file. No data to parse."
    LogMsg "$msg"
    echo $msg >> ~/summary.log
    exit 30

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

#
# Distro specific setup
#
GetDistro

case "$DISTRO" in
    redhat* | centos*)
        ConfigRhel
    ;;
    ubuntu*)
        ConfigUbuntu
    ;;
    debian*)
        LogMsg "Debian is not supported"
        UpdateTestState "TestAborted"
        UpdateSummary "  Distro '${distro}' is not currently supported"
        exit 1
    ;;
    suse*)
        ConfigSles
    ;;
     *)
        LogMsg "Distro '${distro}' not supported"
        UpdateTestState "TestAborted"
        UpdateSummary " Distro '${distro}' not supported"
        exit 1
    ;;
esac

dos2unix ~/*.sh
chmod 755 ~/*.sh

LogMsg "Copy files to server: ${STATIC_IP2}"
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ~/perf_mongodb_server.sh ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:
if [ $? -ne 0 ]; then
    msg="Error: Unable to copy test scripts to target server machine: ${STATIC_IP2}. scp command failed."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 130
fi
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ~/constants.sh ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ~/utils.sh ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:

LogMsg "Starting mongodb configuration on server ${STATIC_IP2}"
ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@${STATIC_IP2} "/root/perf_mongodb_server.sh >> mongodb_ServerSideScript.log"
if [ $? -ne 0 ]; then
    msg="Error: Unable to start mongodb server scripts on the target server machine"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 130
fi

#
# Wait for server to be ready
#
wait_for_server=400
server_state_file=serverstate.txt
while [ $wait_for_server -gt 0 ]; do
    # Try to copy and understand server state
    scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:~/state.txt ~/${server_state_file}
    if [ -f ~/${server_state_file} ];
    then
        server_state=$(head -n 1 ~/${server_state_file})
        echo $server_state
        rm -f ~/${server_state_file}
        if [ "$server_state" == "TestCompleted" ];
        then
            scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ${SERVER_OS_USERNAME}@[${STATIC_IP2}]:~/mongodServerConsole.txt ~/mongodServerConsole.txt
            break
        fi
    fi
    sleep 5
    wait_for_server=$(($wait_for_server - 5))
done

if [ $wait_for_server -eq 0 ] ;
then
    msg="Error: mongodb server script has been triggered but might failed the configuration within ${wait_for_server} seconds."
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 135
else
    LogMsg "mongodb server is ready."
fi

#
# Download YCSB on client
#

LogMsg "Download YCSB on client VM"
curl -O --location https://github.com/brianfrankcooper/YCSB/releases/download/${YCSB_VERSION}/ycsb-${YCSB_VERSION}.tar.gz
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to download YCSB"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi
LogMsg "Extract YCSB on client VM"
tar xfvz ycsb-${YCSB_VERSION}.tar.gz
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to download YCSB"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

LogMsg "Check if MongoDB specific exports are in the .bashrc file"

grep -q "mongodb exports start" ~/.bashrc
if [ $? -ne 0 ]; then
    LogMsg "MongoDB exports not found in ~/.bashrc, adding them"
    echo "" >> ~/.bashrc
    echo "# mongo exports start" >> ~/.bashrc
    echo "export JAVA_HOME=${JAVA_HOME}" >> ~/.bashrc
    echo "# MongoDB exports end" >> ~/.bashrc
fi

#
# Sourcing the update .bashrc
#
source ~/.bashrc
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to source .bashrc"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

iptables -F
iptables -X
#Prepare mongodb.csv log
echo ${pattern[@]} >> mongodb.csv
sed -i -e 's/ /,/g' mongodb.csv

 #Generating workload
echo "recordcount=100000
operationcount=100000
readallfields=true
workload=com.yahoo.ycsb.workloads.CoreWorkload
operationcount=100000
readproportion=0.5
updateproportion=0.5
requestdistribution=zipfian
defaultdataset=8" >> workload

LogMsg "Using the asynchronous driver to load the test data"
/root/ycsb-${YCSB_VERSION}/bin/ycsb load mongodb-async -s -P workload -p mongodb.url=mongodb://${MD_SERVER}:27017/ycsb?w=0
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable load the test data"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

LogMsg "Using the asynchronous driver to load the test data"
for thread in "${threads[@]}"; do
    /root/ycsb-${YCSB_VERSION}/bin/ycsb run mongodb-async -s -P workload -p mongodb.url=mongodb://${MD_SERVER}:27017/ycsb?w=0 -threads $thread > $YCSB_LOG
    if [ $? -ne 0 ]; then
        LogMsg "Error: Unable to run test"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
    ParseResults
done

#
# If we made it here, everything worked.
#
UpdateTestState $ICA_TESTCOMPLETED
exit 0
