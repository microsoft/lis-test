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
########################################################################


########################################################################
#
# Description:
#    This script will be started automatically when the root user
#    is logged in.  It assumes the root user is configured for
#    autologin which implies this script will run automatically
#    after the system boots up.
#
#    The script will verify there are not eth devices present on
#    the system.  If true, a KVP item with a key name = HotAddTest
#    and a value of 'NoNICs' will be created.  This will allow
#    the test case script, NET_BootNoNICHotAddNIC.ps1 to to continue.
#
#    After creating the HotAddTest KVP item, this script will enter
#    a loop, looking for the creation of an eth device.
#
#    Once the test script NET_BootNoNICHotAddNIC.ps1 detects the
#    HotAddTest KVP item, it will continue running and do a Hot Add
#    of a Synthetic NIC.
#
#    Once this script detects the creation of an eth device, it
#    will try to configure the device.  If an IP address is successfully
#    assigned to the eth device, this script will modify the
#    value of the HotAddTest KVP item to 'NICUp'
#
#    The test case script NET_BootNoNICHotAddNIC.ps1 will be looping
#    waiting for the value of the HotAddTest KVP item to change to a
#    value of 'NICUp'
#
#    Once the test case script NET_BootNoNICHotAddNIC.ps1 detects the
#    change, it will do a hot remove of the NIC.
#
#    After doing the hot remove of the NIC, the test case script
#    NET_BootNoNICHotAddNIC.ps1 will loop waiting for the HotAddTest
#    KVP item value to change to 'NoNICs'
#
#    Once the test case script NET_BootNoNICHotAddNIC.ps1 detects the
#    KVP value of 'NoNICs' the test case script will stop the VM,
#    apply a snapshot to restore the original VM configuration, and
#    then start the VM.
#
########################################################################


########################################################################
#
# LogMsg()
#
########################################################################
LogMsg()
{
    echo `date "+%a %b %d %T %Y"` ": ${1}" >> /root/hotaddnic.log
}


########################################################################
#
# Main script body
#
########################################################################

LogMsg "Info : Changing current directory to /root"
cd /root/

if [ ! -e ./kvp_client ]; then
    LogMsg "Error: the file /root/kvp_client does not exist"
    exit 1
fi

LogMsg "Info : chmod 755 ./kvp_client"
chmod 755 ./kvp_client

#
# Verify there are no eth devices
#
LogMsg "Info : Check count of eth devices"
ethCount=$(ifconfig -a | grep '^eth' | wc -l)

LogMsg "Info : ethCount = ${ethCount}"
if [ $ethCount -ne 0 ]; then
    LogMsg "Error: eth device count is not zero: ${ethCount}"
    exit 1
fi

#
# Create a nonintrinsic HotAddTest KVP item with a value of 'NoNICs'
#
LogMsg "Info : Creating HotAddTest key with value of 'NoNICS'"
./kvp_client append 1 'HotAddTest' 'NoNICs'

#
# Loop waiting for an eth device to appear
#
LogMsg "Info : Waiting for an eth device to appear"
timeout=300
noEthDevice=1
while [ $noEthDevice -eq 1 ]
do
    ethCount=$(ifconfig -a | grep '^eth' | wc -l)
    if [ $ethCount -eq 1 ]; then
        LogMsg "Info : an eth device was detected"
        break
    fi

    timeout=$((timeout-10))
    sleep 10
    if [ $timeout -le 0 ]; then
        LogMsg "Error: Timed out waiting for eth device to be created"
        exit 1
    fi
done

#
# Configure the new eth device
#
LogMsg "Info : ifup eth0"
ifup eth0

#echo "Info : dhclient eth0"
#dhclient eth0

#
# Verify the eth device received an IP address
#
LogMsg "Info : Verify the new NIC received an IPv4 address"
ifconfig eth0 | grep -s "inet addr:" > /dev/null
if [ $? -ne 0 ]; then
    LogMsg "Error: eth0 was not assigned an IPv4 address"
    exit 1
fi

LogMsg "Info : eth0 is up"

#
# Modify the KVP HotAddTest value to 'NICUp'
#
LogMsg "Info : Updating HotAddTesk KVP item to 'NICUp'"
./kvp_client append 1 'HotAddTest' 'NICUp'

#
# Loop waiting for the eth device to disappear
#
LogMsg "Info : Waiting for the eth device to be deleted"
timeout=300
noEthDevice=1
while [ $noEthDevice -eq 1 ]
do
    ethCount=$(ifconfig -a | grep '^eth' | wc -l)
    if [ $ethCount -eq 0 ]; then
        LogMsg "Info : eth count is zero"
        break
    fi

    timeout=$((timeout-10))
    sleep 10
    if [ $timeout -le 0 ]; then
        LogMsg "Error: Timed out waiting for eth device to be hot removed"
        exit 1
    fi
done

#
# Modify the KVP HotAddTest value to 'NoNICs'
#
LogMsg "Info : Setting HotAddTest value to 'NoNICs'"
./kvp_client append 1 'HotAddTest' 'NoNICs'

#
# exit
#
LogMsg "Info : Test complete - exiting"
exit 0

