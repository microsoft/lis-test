#####################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
#####################################################################

interface="eth1"

#
# Functions definitions
#
LogMsg()
{
    # To add the time-stamp to the log file
    echo `date "+%a %b %d %T %Y"` ": ${1}"
}

UpdateTestState()
{
    echo $1 >> ~/state.txt
}

function ConfigureVxlan ()
{
    ip link add vxlan0 type vxlan id 999 local $3 group $4 dev $1
    if [ 0 -ne $? ]; then
        msg="Failed to add vxlan0."
        LogMsg "$msg"
        echo "$msg" >> summary.log
        UpdateTestState "TestAborted"
        exit 12
    else
        LogMsg "Successfully added vxlan0"
        echo "Successfully added vxlan0" >> summary.log
    fi  
    ip l set vxlan0 up
    if [ $2 == "local" ]; then
        ip addr add 242.0.0.12/24 dev vxlan0
    else
        ip addr add 242.0.0.11/24 dev vxlan0
    fi  
    if [ 0 -ne $? ]; then
        msg="Failed to asociate an address for vxlan0."
        LogMsg "$msg"
        echo "$msg" >> summary.log
        UpdateTestState "TestAborted"
        exit 13
    else
        LogMsg "Successfully added an address for vxlan0."
        echo "Successfully added an address for vxlan0." >> summary.log
    fi
}

function CreateTestFolder ()
{   
    LogMsg "Creating test directory..."
    mkdir /root/test
    if [ $? -ne 0 ]; then
        echo "Failed to create test directory." >> summary.log
        UpdateTestState "TestAborted"
        exit 10
    fi

    dd if=/dev/zero of=/root/test/data bs=7M count=1024
    if [ $? -ne 0 ]; then
        echo "Failed to create test file." >> summary.log
        UpdateTestState "TestAborted"
        exit 11
    fi

    dd if=/dev/zero of=/root/test/data2 bs=3M count=1024
    if [ $? -ne 0 ]; then
        echo "Failed to create test file." >> summary.log
        UpdateTestState "TestAborted"
        exit 12
    fi
}


#####################################################################################
#
# Main script
#
#####################################################################################
ip_local=$1
vm=$2
ip_group=`ip maddress show $interface | grep inet | head -n1 | awk '{print $2}'`

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

GetDistro
case "$DISTRO" in
    suse*)
       /sbin/rcSuSEfirewall2 stop
        if [ $? -ne 0 ]; then
            echo "Failed to stop FIREWALL." >> summary.log
            exit 12
        fi
        service atd start
        ;;
    ubuntu*)
        ufw disable
        ;;
    redhat* | centos*)
        iptables -F
        iptables -X
        ;;
        *)
            msg="ERROR: OS Version not supported!"
            LogMsg "$msg"
            UpdateSummary "$msg"
            SetTestStateFailed
            exit 10
        ;;
esac

# configure vxlan
ConfigureVxlan $interface $vm $ip_local $ip_group

if [ $vm == "local" ]; then
    CreateTestFolder
fi