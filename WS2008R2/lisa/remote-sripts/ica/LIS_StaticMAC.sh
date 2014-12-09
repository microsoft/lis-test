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

#  This script try checks that static MAC is relected exactly as set in hyper-v
#   
#   Test parameter :
#     NIC: It shows the apdator to be attach is of which network type and uses which network name
#         Example: NetworkAdaptor,External,External_Net
#
#     TARGET_ADDR: It is the ip address to be pinged
#
#     MAC: MAC address of NIC

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}


#
# Create the state.txt file so ICA knows we are running
#
echo "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

rm -f ~/summary.log
touch ~/summary.log

#
# Source the constants.sh file to pickup definitions from
# the ICA automation
#
if [ -e ~/${CONSTANTS_FILE} ]; then
    source ~/${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    echo $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

#
# Make sure constants.sh contains the variables we expect
#
if [ "${NIC:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter NIC is not defined in ${CONSTANTS_FILE}"
    echo $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

if [ "${TC_COVERED:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter TC_COVERED is not defined in ${CONSTANTS_FILE}"
    echo $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

if [ "${TARGET_ADDR:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter TARGET_ADDR is not defined in ${CONSTANTS_FILE}"
    echo $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 40
fi

if [ "${MAC:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter TARGET_ADDR is not defined in ${CONSTANTS_FILE}"
    echo $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 50
fi

#
# Echo TCs we cover
#
echo "Covers ${TC_COVERED}" > ~/summary.log


enable_leg()
{
for LEGACY_DEVICE in ${LEGACY_NET_DEVICE[@]} ; do
    ifconfig $LEGACY_DEVICE up >/dev/null 2>&1
    sts=$?
    LogMsg  "ifup status for $LEGACY_DEVICE = $sts"
    if [ 0 -ne ${sts} ]; then
        LogMsg "LEGACY Network Adapter : $LEGACY_DEVICE , is not correctly configured in VM. "
        LogMsg "ifup <$LEGACY_DEVICE> failed: ${sts}" 
        echo "ifup <$LEGACY_DEVICE> failed: ${sts}"  >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 90
    else
        LogMsg  "$LEGACY_DEVICE  is enabled successfully  inside VM  "        
    fi     
done
}

#
# Constant file path
#
#NET_PATH="/sys/devices/vmbus_0_0"
NET_PATH=`find /sys/devices -name net | grep vmbus*`
if [ ! -e ${NET_PATH} ]; then
    LogMsg "Network device path $NET_PATH does not exists"
    echo "Network device path $NET_PATH does not exists" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
	exit 50
fi

#
# If tmp file is present please delter it do the apporpriate 
# 
rm -rf ~/tmp.txt

cd $NET_PATH
#find -name eth* | cut -f 4 -d "/"  > ~/tmp.txt
ls > /root/tmp.txt

#NET_PATH=( `cat ~/tmp.txt | tr '.' ' ' `)
NET_DEVICE=( `cat ~/tmp.txt `)

LogMsg "Net device is: $NET_DEVICE"

#
# to check the Synthetic Network Adapter
#
for DEVICE in  ${NET_DEVICE[@]} ; do
    ifconfig $DEVICE  >/dev/null 2>&1
    sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "Network Adapter : $DEVICE , is not correctly configure in VM. "
        LogMsg "ifconfig <$DEVICE> fialed: ${sts}"
        echo "ifconfig <$DEVICE> fialed: ${sts}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
		enable_leg
        exit 80
    else
        LogMsg  "Synthetic network adapter $DEVICE is present inside VM  "
        echo "Synthetic network adapter is : $DEVICE " >> ~/summary.log
    fi

    IP_ADDRESS=( `ifconfig $DEVICE | grep Bcast | awk '{print $2}' | cut -f 2 -d ":"`  )
    if [[ "$IP_ADDRESS" == "" ]] ; then
        LogMsg "System Does not got IP Address"
        echo "System Does not got IP Address" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
		enable_leg
        exit 90
    else
        LogMsg "IP Address of this system is  :$IP_ADDRESS"
        echo "Synthetic network adapter IP is :$IP_ADDRESS" >> ~/summary.log
    fi

    for j in 1 2 3 4 5 6
    do
        i=`ifconfig $DEVICE | grep HWaddr | cut -d " " -f 11 | cut -d ":" -f $j`
        Mac=`echo $MAC | cut -d ":" -f $j`
        if [ "$i" = "$Mac" ] ; then
            LogMsg "digits matched $i, $Mac"
        else
            LogMsg "MAC address differs, Test : Failed"
	        echo "MAC address differs, Test : Failed" >> ~/summary.log
	        UpdateTestState $ICA_TESTFAILED
			enable_leg
	        exit 70
        fi
    done
    LogMsg "MAC address is the same"

    #
    # Test the ping
    #
    LogMsg "ping -c 5 ${TARGET_ADDR}"
    ping -c 5 ${TARGET_ADDR} > ~/pingdata
	
	loss=`cat ~/pingdata | grep "packet loss" | cut -d " " -f 6`
	LogMsg "Packet loss is : ${loss}"
	if [ "${loss}" != "0%" ] ; then
        LogMsg "Ping failed"
	    echo "Ping failed with packet loss $loss" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
		enable_leg
	    exit 80
    else
	    LogMsg "Ping Successful"
		sleep 1
	fi

    echo "MAC address is the same and also ping is successful, Test : Passed" >> ~/summary.log

done

#
# To enable the Legacy network Adapters
#
enable_leg

#
#If we are here test passed
#
LogMsg "Test case completed successfully"
UpdateTestState $ICA_TESTCOMPLETED

exit 0
