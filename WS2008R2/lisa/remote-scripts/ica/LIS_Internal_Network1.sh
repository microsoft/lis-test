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

#     This script was created to automate the testing of a Linux
#     Integration services.
#     This script is used to verify that the Internal network 
#     adapter of the Guest VM cannot communicate with the 
#     external network
#     and can communicate only with the Host Internal 
#     network.
#     Steps:
#	  1. Make sure we were given a configuration file with         
#         REPOSITORY SERVER , HOST INTERNAL NETWORK IP.
#	  2. Disable all the legacy network adapters present in
#          the VM.(We are doing this step because of bug ID:132)
#      3. Ping the internal network of the HOST through the 
# 	     Synthetic Adapter card .
#      4. Ping the External network through the 
# 	     Synthetic Adapter card .(This should fail)
#      5.Enable all the legacy network adapters present in the 
#        VM.
#	 To identify objects to compare with, we source a 
#     constansts file
#     This file will be given to us from 
#     Hyper-V Host server.  
#     It contains definitions like:
#         REPOSITORY SERVER="10.200.41.67"
#         HOST_SERVER_INTERNAL_IP=152.168.0.1

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestAborted"        # Error during execution of test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

LogMsg "########################################################"
LogMsg "This is Test Case to test Internal Network"

UpdateTestState()
{
    echo $1 > ~/state.txt
}

cd ~

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

# Source the constants file
if [ -e ~/${CONSTANTS_FILE} ]; then
    source ~/${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    echo $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

# Check if REPOSITORY_SERVER Variable in Constant file is present or not
#Since it require to ping external network ,external network ip must be defined
if [ ! ${REPOSITORY_SERVER} ]; then
    LogMsg "The REPOSITORY_SERVER variable is not defined."
    echo "The REPOSITORY_SERVER variable is not defined." >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

#Check if Number of VMbus devices is defined or not
if [ ! ${NW_ADAPTER} ]; then
    LogMsg "The NW_ADAPTER variable is not defined."
    echo "The NW_ADAPTER variable is not defined." >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

# Check if HOST_SERVER_INTERNAL_IP Variable in Constant file is present or not
#Since it require to ping internal network , host server internal network IP must be defined
if [ ! ${HOST_SERVER_INTERNAL_IP} ]; then
    LogMsg "The HOST_SERVER_INTERNAL_IP variable is not defined."
    echo "The HOST_SERVER_INTERNAL_IP variable is not defined." >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 40
fi

if [ ! ${PRIVATE_STATIC_IP} ]; then
    PRIVATE_STATIC_IP=192.168.0.2
    LogMsg "PRIVATE_STATIC_IP is not defined. Fallback to $PRIVATE_STATIC_IP"
fi
if [ ! ${PRIVATE_NETWORK_MASK} ]; then
    PRIVATE_NETWORK_MASK=255.255.255.0
    LogMsg "PRIVATE_NETWORK_MASK is not defined. Fallback to $PRIVATE_NETWORK_MASK"
fi

#Check for Testcase count
if [ ! ${TC_COUNT} ]; then
    LogMsg "The TC_COUNT variable is not defined."
    echo "The TC_COUNT variable is not defined." >> ~/summary.log
    LogMsg "Terminating the test."
    UpdateTestState $ICA_TESTABORTED
    exit 50
fi

echo "Covers : ${TC_COUNT}" >> ~/summary.log

# Constant file path
#NET_PATH="/sys/devices/vmbus_0_0"

NET_PATH=`find /sys/devices -name net | grep vmbus*`
if [ ! -e ${NET_PATH} ]; then
    LogMsg "Network device path $NET_PATH does not exists"
    LogMsg "Exiting test as aborted "
    UpdateTestState $ICA_TESTABORTED
    exit 60
fi

# If tmp file is present please delter it do the apporpriate 
# check by if and all.

rm -rf ~/tmp.txt

cd $NET_PATH
#find -name eth* | cut -f 4 -d "/"  > ~/tmp.txt

ls > /root/tmp.txt

NET_DEVICE=( `cat ~/tmp.txt `)

#now compare the no. of network adapter is equal to the added adpeter
NO_NW_ADAPTER=( `cat ~/tmp.txt | wc -l `)

LogMsg " No of adapter inside  VM is $NO_NW_ADAPTER  "
LogMsg " No of adapter defined is $NW_ADAPTER "

if [[ "$NW_ADAPTER" -eq "$NO_NW_ADAPTER" ]] ; then
    LogMsg  "Number of network adapter present inside VM is correct"
else
	LogMsg  "Number of network adapter present inside VM is incorrect"
	echo "Number of network adapter present inside VM is incorrect" >> ~/summary.log
	UpdateTestState $ICA_TESTFAILED
	exit 70
fi

# to check the Synthetic Network Adapter
for DEVICE in  ${NET_DEVICE[@]} ; do

    ifconfig $DEVICE  >/dev/null 2>&1
    sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "Network Adapter : $DEVICE , is not correctly configure in VM. "
        LogMsg "ifconfig <$DEVICE> failed: ${sts}"
        echo "ifconfig <$DEVICE> failed: ${sts}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 80
    else
        LogMsg  "Synthetic network adapter $DEVICE is present inside VM  "
    fi

	# Make sure it's not affected by NetworkManager or other scripts
    ifdown $DEVICE
    IP_ADDRESS=( `ifconfig $DEVICE | grep Bcast | awk '{print $2}' | cut -f 2 -d ":"`  )
    if [[ "$IP_ADDRESS" != "" ]] ; then
        LogMsg "IP Address of this system is  :$IP_ADDRESS"
        LogMsg "System has got IP Address $IP_ADDRESS : Invalid Case"
        echo "System has got IP Address $IP_ADDRESS : Invalid Case" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 90
	fi

    # Assign Static IP to the Network Adapter
    static_ip=${PRIVATE_STATIC_IP}
    network_mask=${PRIVATE_NETWORK_MASK}
    ifconfig $DEVICE $static_ip
    ifconfig $DEVICE netmask $network_mask
    sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "Static IP is not assiged to $DEVICE. "
        LogMsg "Assign Static IP for <$DEVICE> failed: ${sts}" 
        LogMsg "Cannot Proceed further with the test"
        echo "Static IP for internal network is : Failed"  >> ~/summary.log		
        UpdateTestState $ICA_TESTFAILED
        exit 100
    else
        LogMsg  "Static IP: $static_ip set to $DEVICE : Success"  
        echo "Static IP for internal network is set to : $static_ip"  >> ~/summary.log   
    fi

    ifconfig $DEVICE up

    LogMsg "We are going to Test if IP address can ping the HOST SERVER INTERNAL IP (Internal Network) : $HOST_SERVER_INTERNAL_IP ......."

    # if the return is Not Equal to 0 (successful)...
    ping -I $DEVICE -c 10 $HOST_SERVER_INTERNAL_IP > /dev/null 2>&1
    sts=$?
    if [ ${sts} -ne "0" ]; then
        LogMsg  "Internal Network adapter card : $DEVICE  cannot ping the HOST SERVER INTERNAL IP :$HOST_SERVER_INTERNAL_IP"
        echo "Ping to Internal Network : Failed" >> ~/summary.log	
        UpdateTestState $ICA_TESTFAILED
        exit 110	
    else
        LogMsg  "Internal Network adapter card : $DEVICE  can ping the HOST SERVER INTERNAL IP :$HOST_SERVER_INTERNAL_IP  !!"
        echo "Ping to Internal Network : Success"   >> ~/summary.log		
    fi
  
    LogMsg "We are going to Test if IP address can ping the REPOSITORY SERVER(External Network) : $REPOSITORY_SERVER "

    # if the return is Not Equal to 0 (successful)...
    ping -I $DEVICE -c 10 $REPOSITORY_SERVER > /dev/null 2>&1
    sts=$?
    if [ ${sts} -ne "0" ]; then
        LogMsg  "Internal Network adapter card : $DEVICE  cannot ping the REPOSITORY SERVER :$REPOSITORY_SERVER "
        echo "Ping to External Network should Fail : Success"  >> ~/summary.log			
    else
        LogMsg  "Internal Network adapter card : $DEVICE can ping REPOSITORY SERVER : $REPOSITORY_SERVER !!"
        echo "Ping to External Network : Success "  >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 120	
    fi
done # end of Outer For loop

#Clean up system
rm -rf ~/tmp.txt

LogMsg "#########################################################"
LogMsg "Exiting with state: TestCompleted."
UpdateTestState $ICA_TESTCOMPLETED