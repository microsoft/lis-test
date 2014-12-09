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

# Description:
#     This script was created to automate the testing of a Linux
#     Integration services.
#     This script is used to verify that the Guest Only network 
#     adapter of the Guest VM cannot communicate with the 
#     External Network ,Internal Network
#     and can communicate only with other VM's Guest Only 
#     network.
#     Steps:
#	  1. Make sure we were given a configuration file with         
#         REPOSITORY SERVER , HOST INTERNAL NETWORK IP  and 
#	     VM_GUEST_ONLY_IP
#	  2. Disable all the legacy network adapters present in
#          the VM.(We are doing this step because of bug ID:132)
#	  3. Ping the Guest Only network of other VM through the 
# 	     Synthetic Network Adapter card .
#      4. Ping the Internal network of the HOST through the 
# 	     Synthetic Network Adapter card .(This should fail)
#      5. Ping the External network through the 
# 	     Synthetic Network Adapter card .(This should fail)
#      6. Enable all the legacy network adapters present in the 
#         VM.
#	 To identify objects to compare with, we source a 
#     constansts file
#     This file will be given to us from 
#     Hyper-V Host server.  
#     It contains definitions like:
#         REPOSITORY SERVER="10.200.41.67"
#         HOST_SERVER_INTERNAL_IP=152.168.0.1
#	     VM_GUEST_ONLY_IP=152.168.0.3

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

LogMsg "########################################################"
LogMsg "This is Test Case to test Guest only Network"

UpdateTestState()
{
    echo $1 > ~/state.txt
}

cd ~

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

# Source the constants file

if [ -e ~/constants.sh ]; then
 . ~/constants.sh
else
 LogMsg "ERROR: Unable to source the constants file."
 exit 1
fi


# Check if VM_GUEST_ONLY_IP Variable in Constant file is present # or not
# Since it requires to ping Guest only of other VM, Guest only  
# IP of other VM mus be defined 
if [ ! ${VM_GUEST_ONLY_IP} ]; then
	LogMsg "The VM_GUEST_ONLY_IP  variable is not defined."
	echo "The VM_GUEST_ONLY_IP variable is not defined." >> ~/summary.log
	UpdateTestState "TestAborted"
	exit 1
fi


# Check if REPOSITORY_SERVER Variable in Constant file is present or not
#Since it requires to ping external network external network ip must be defined
if [ ! ${REPOSITORY_SERVER} ]; then
	LogMsg "The REPOSITORY_SERVER variable is not defined."
	echo "The REPOSITORY_SERVER variable is not defined." >> ~/summary.log
	UpdateTestState "TestAborted"
	exit 1
fi

if [ ! ${PRIVATE_STATIC_IP} ]; then
    PRIVATE_STATIC_IP=192.168.0.2
    LogMsg "PRIVATE_STATIC_IP is not defined. Fallback to $PRIVATE_STATIC_IP"
fi
if [ ! ${PRIVATE_NETWORK_MASK} ]; then
    PRIVATE_NETWORK_MASK=255.255.255.0
    LogMsg "PRIVATE_NETWORK_MASK is not defined. Fallback to $PRIVATE_NETWORK_MASK"
fi

# Check if HOST_SERVER_INTERNAL_IP Variable in Constant file is present or not
#Since it require to ping internal network , host server internal network IP must be defined
if [ ! ${HOST_SERVER_INTERNAL_IP} ]; then
	LogMsg "The HOST_SERVER_INTERNAL_IP variable is not defined."
	echo "The HOST_SERVER_INTERNAL_IP variable is not defined." >> ~/summary.log
	UpdateTestState "TestAborted"
	exit 1
fi

#Check if Number of VMbus devices is defined or not
if [ ! ${NW_ADAPTER} ]; then
	LogMsg "The NW_ADAPTER variable is not defined."
	echo "The NW_ADAPTER variable is not defined." >> ~/summary.log
	UpdateTestState "TestAborted"
	exit 1
fi

# Create the state.txt file so the ICA script knows
# we are running


UpdateTestState "TestRunning"

# Constant file path
#NET_PATH="/sys/devices/vmbus_0_0"

NET_PATH=`find /sys/devices -name net | grep vmbus*`
if [ ! -e ${NET_PATH} ]; then
    LogMsg "Network device path $NET_PATH does not exists"
    echo "Network device path $NET_PATH does not exists" >> ~/summary.log
    UpdateTestState "TestFailed"
	exit 1
fi

# If tmp file is present please delter it do the apporpriate 
# check by if and all.

rm -rf ~/tmp.txt

cd $NET_PATH
#find -name eth* | cut -f 4 -d "/"  > ~/tmp.txt

ls > /root/tmp.txt

#NET_PATH=( `cat ~/tmp.txt | tr '.' ' ' `)
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
	UpdateTestState "TestFailed"
	exit 1
fi

# to check the Synthetic Network Adapter
for DEVICE in  ${NET_DEVICE[@]} ; do

    ifconfig $DEVICE  >/dev/null 2>&1
    sts=$?
        if [ 0 -ne ${sts} ]; then
            LogMsg "Network Adapter : $DEVICE , is not correctly configure in VM. "
			LogMsg "ifconfig <$DEVICE> failed: ${sts}"
	        echo "Network Adapter : $DEVICE , is not correctly configure in VM. " >> ~/summary.log
            UpdateTestState "TestFailed"
			exit 1
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
        UpdateTestState "TestFailed"
        exit 1
	fi

# Assign Static IP to the  Guest only Network Adapter
static_ip=${PRIVATE_STATIC_IP}
network_mask=${PRIVATE_NETWORK_MASK}
ifconfig $DEVICE $static_ip
ifconfig $DEVICE netmask $network_mask
sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "Static IP is not assiged to $DEVICE. "
        LogMsg "Assign Static IP for <$DEVICE> failed: ${sts}" 
		LogMsg "Cannot Proceed further with the test" 
        echo "Static IP set to $static_ip : Failed" >> ~/summary.log
		UpdateTestState "TestFailed"
  		exit 1
    else
        LogMsg "Static IP: $static_ip set to $DEVICE : Success"  
		echo "Static IP set to : $static_ip "  >> ~/summary.log       
    fi
ifconfig $DEVICE up

# Guest only Network Test

LogMsg "We are going to Test if IP address can ping Other VM's GUEST ONLY IP (Guest Only Network) : $VM_GUEST_ONLY_IP ......."

# if the return is Not Equal to 0 (successful)...
ping -I $DEVICE -c 10 $VM_GUEST_ONLY_IP > /dev/null 2>&1
sts=$?
    if [ ${sts} -ne "0" ]; then
		LogMsg  "Network adapter card :$DEVICE  cannot ping Other VM's GUEST ONLY IP (Guest Only Network) : $VM_GUEST_ONLY_IP"
		echo "Ping to Guest Only Network : Failed" >> ~/summary.log 
		UpdateTestState "TestFailed"
		exit 1
    else
		LogMsg  "Network adapter card : $DEVICE  can ping Other VM's GUEST ONLY IP (Guest Only Network) : $VM_GUEST_ONLY_IP!!"
		echo "Ping to Guest Only Network : Success"  >> ~/summary.log                 
	fi

# Internal Network Test

LogMsg "We are going to Test if IP address can ping the HOST SERVER INTERNAL IP (Internal Network) : $HOST_SERVER_INTERNAL_IP ......."

# if the return is Not Equal to 0 (successful)...
ping -I $DEVICE -c 10 $HOST_SERVER_INTERNAL_IP > /dev/null 2>&1
sts=$?
    if [ ${sts} -ne "0" ]; then
		LogMsg "Guest Only Network adapter card : $DEVICE  cannot ping the HOST SERVER INTERNAL IP :$HOST_SERVER_INTERNAL_IP"
        echo "Ping to Internal Network should Fail : Success" >> ~/summary.log 
    else
		LogMsg "Guest Only Network adapter card : $DEVICE  can ping the HOST SERVER INTERNAL IP :$HOST_SERVER_INTERNAL_IP  !!"
		echo "Ping to Internal Network : Success" >> ~/summary.log  
        UpdateTestState "TestFailed"
        exit 1		
	fi

# External Network Test
  
LogMsg "We are going to Test if IP address can ping the REPOSITORY SERVER (External Network) : $REPOSITORY_SERVER "

# if the return is Not Equal to 0 (successful)...
ping -I $DEVICE -c 10 $REPOSITORY_SERVER > /dev/null 2>&1
sts=$?
	if [ ${sts} -ne "0" ]; then
		LogMsg "Guest Only Network adapter card cannot ping the REPOSITORY SERVER :$REPOSITORY_SERVER "
        echo "Ping to External Network should Fail : Success" >> ~/summary.log     
    else
	    LogMsg  "Guest Only Network adapter card inside  VM can ping REPOSITORY SERVER : $REPOSITORY_SERVER !!"
		echo "Ping to External Network  : Success" >> ~/summary.log 
        UpdateTestState "TestFailed"
        exit 1		
	fi

done # end of Outer For loop

#Clean up system
rm -rf ~/tmp.txt

LogMsg "#########################################################"
LogMsg "Result : Test Completed Succesfully"
LogMsg "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"