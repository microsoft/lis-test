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
# Description:
#     Configuring an APACHE server to be tested.
#
#######################################################################

ICA_TESTRUNNING="TestRunning"
ICA_APACHERunning="APACHERunning"
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
LogMsg "Starting running the script"

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
        # do nothing, init succeeded
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

#Get test synthetic interface
declare __iface_ignore

# Parameter provided in constants file
#   ipv4 is the IP Address of the interface used to communicate with the VM, which needs to remain unchanged
#   it is not touched during this test (no dhcp or static ip assigned to it)

if [ "${TEST_FILE_SIZE_IN_KB:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the TEST_FILE_SIZE_IN_KB test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

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

#
# Distro specific setup
#
GetDistro

case "$DISTRO" in
debian*|ubuntu*)

    LogMsg "Info: Running Ubuntu server"

    LogMsg "Info: -----------------------------------------"
    LogMsg "Info: Apache server installation on server side"
    apt-get update
    apt-get install -y apache2
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to install apache2."
        UpdateTestState $ICA_TESTFAILED
        exit 20      
    fi

    LogMsg "Info: Restart Apache server"
    service apache2 restart
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to start apache2 service."      
    fi

    LogMsg "Info: Change home folder"
    cd /var/www/html
    ;;
 redhat*|centos*)
    LogMsg "Info: Running RHEL server"

    LogMsg "Info: -----------------------------------------"
    LogMsg "Info: Apache server installation on server side"
    yum install -y httpd
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to install httpd."
        UpdateTestState $ICA_TESTFAILED
        exit 20    
    fi

    LogMsg "Info: Restart Apache server"        
    systemctl restart httpd.service
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to start httpd service."        
    fi
    cd /var/www/html/
    ;;
suse*)
    LogMsg "Info: Running SLES server"

    LogMsg "Info: -----------------------------------------"
    LogMsg "Info: Apache server installation on server side"
    zypper --non-interactive install apache2
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to install apache2"
        UpdateTestState $ICA_TESTFAILED
        exit 20    
    fi

    LogMsg "Info: Restart Apache server"
    service apache2 stop
    service apache2 start
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Failed to start apache2 service."        
    fi
    cd /srv/www/htdocs
    ;;
esac

LogMsg "Info: Generate test data file to Apache server www htdocs folder"
dd if=/dev/urandom of=./test.dat bs=1K count=${TEST_FILE_SIZE_IN_KB}
if [ $? -ne 0 ]; then
    LogMsg "ERROR: Failed to generate test data."
    UpdateTestState $ICA_TESTFAILED
    exit 20          
fi

# set static ips for test interfaces
declare -i __iterator=0

while [ $__iterator -lt ${#SYNTH_NET_INTERFACES[@]} ]; do
    LogMsg "Trying to set an IP Address via static on interface ${SYNTH_NET_INTERFACES[$__iterator]}"
    CreateIfupConfigFile "${SYNTH_NET_INTERFACES[$__iterator]}" "static" $APACHE_SERVER $NETMASK

    if [ 0 -ne $? ]; then
        msg="Unable to set address for ${SYNTH_NET_INTERFACES[$__iterator]} through static"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 120
    fi

    : $((__iterator++))

done

UpdateTestState $ICA_APACHERunning
LogMsg "APACHE server is now ready to run"
