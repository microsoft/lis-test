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
# perf_mongodb_server.sh
#
# mongo perf needs Java runtime is also installed.
#
# Description:
#    Install and configure mongodb so the mongoperf benchmark can
#    be run.  This script needs to be run on single VM.
#
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
    apt-get update
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

MONGODB_ARCHIVE="mongodb-linux-x86_64-${MONGODB_VERSION}.tgz"
MONGODB_URL="http://fastdl.mongodb.org/linux/${MONGODB_ARCHIVE}"

#Get test synthetic interface
declare __iface_ignore

# Parameter provided in constants file
#   ipv4 is the IP Address of the interface used to communicate with the VM, which needs to remain unchanged
#   it is not touched during this test (no dhcp or static ip assigned to it)

if [ "${STATIC_IP2:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter STATIC_IP2 is not defined in constants file! Make sure you are using the latest LIS code."
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
    exit 30
else
    CheckIP "$STATIC_IP2"
    if [ 0 -ne $? ]; then
        msg="Test parameter STATIC_IP2 = $STATIC_IP2 is not a valid IP Address"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateAborted
        exit 10
    fi

    # Get the interface associated with the given ipv4
    __iface_ignore=$(ip -o addr show | grep "$STATIC_IP2" | cut -d ' ' -f2)
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

# set static ips for test interfaces
declare -i __iterator=0

while [ $__iterator -lt ${#SYNTH_NET_INTERFACES[@]} ]; do
    LogMsg "Trying to set an IP Address via static on interface ${SYNTH_NET_INTERFACES[$__iterator]}"
    CreateIfupConfigFile "${SYNTH_NET_INTERFACES[$__iterator]}" "static" $MD_SERVER $NETMASK
    if [ 0 -ne $? ]; then
        msg="Unable to set address for ${SYNTH_NET_INTERFACES[$__iterator]} through static"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 10
    fi

    echo "TestInterface: ${SYNTH_NET_INTERFACES[$__iterator]}"
    : $((__iterator++))

done

#
# Distro specific setup
#
GetDistro

case "$DISTRO" in
    redhat*)
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

#
# Download MongoDB to server and start mongodb server.
#
LogMsg "Downloading MongoDB if we do not have a local copy"

if [ ! -e "/root/${MONGODB_ARCHIVE}" ]; then
    LogMsg "Downloading MongoDB from ${MONGODB_URL}"
    wget ${MONGODB_URL}
    if [ $? -ne 0 ]; then
        LogMsg "Error: Unable to download mongodb from ${MONGODB_URL}"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
    LogMsg "MongoDB successfully downloaded"
fi

#
# Untar and install MondoDB
#
LogMsg "Extracting the mongodb archive"

tar xfvz mongodb-linux-x86_64-${MONGODB_VERSION}.tgz
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to extract mongodb from its archive"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

iptables -F
iptables -X

LogMsg "Starting MongoDB"
killall mongod
mkdir -p /tmp/mongodb
/root/mongodb-linux-x86_64-${MONGODB_VERSION}/bin/mongod --dbpath /tmp/mongodb --fork --logpath mongodServerConsole.txt
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to start mongod server"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# If we made it here, everything worked.
#
UpdateTestState $ICA_TESTCOMPLETED
exit 0
