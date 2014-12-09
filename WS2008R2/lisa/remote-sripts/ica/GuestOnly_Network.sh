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


echo "########################################################"
echo "This is Test Case to perform Guest Only Network Check"

DEBUG_LEVEL=3

dbgprint()
{
    if [ $1 -le $DEBUG_LEVEL ]; then
        echo "$2"
    fi
}

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

cd ~

if [ -e ~/summary.log ]; then
    dbgprint 1 "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

UpdateSummary()
{
    echo $1 >> ~/summary.log
}

#
# Convert any .sh files to Unix format
#

dos2unix -f ica/* > /dev/null  2>&1

# Source the constants file

if [ -e $HOME/constants.sh ]; then
 . $HOME/constants.sh
else
 echo "ERROR: Unable to source the constants file."
 exit 1
fi

# Check if VM_GUEST_ONLY_IP Variable in Constant file is present # or not
# Since it requires to ping Guest only of other VM, Guest only  
# IP of other VM mus be defined 
if [ ! ${VM_GUEST_ONLY_IP} ]; then
	dbgprint 1 "The VM_GUEST_ONLY_IP  variable is not defined."
	dbgprint 1 "aborting the test."
	UpdateTestState "TestAborted"
	exit 1
fi


# Check if REPOSITORY_SERVER Variable in Constant file is present or not
#Since it requires to ping external network external network ip must be defined
if [ ! ${REPOSITORY_SERVER} ]; then
	dbgprint 1 "The REPOSITORY_SERVER variable is not defined."
	dbgprint 1 "aborting the test."
	UpdateTestState "TestAborted"
	exit 1
fi

if [ ! ${PRIVATE_STATIC_IP} ]; then
    PRIVATE_STATIC_IP=192.168.0.2
    dbgprint 1 "PRIVATE_STATIC_IP is not defined. Fallback to $PRIVATE_STATIC_IP"
fi
if [ ! ${PRIVATE_NETWORK_MASK} ]; then
    PRIVATE_NETWORK_MASK=255.255.255.0
    dbgprint 1 "PRIVATE_NETWORK_MASK is not defined. Fallback to $PRIVATE_NETWORK_MASK"
fi

# Check if HOST_SERVER_INTERNAL_IP Variable in Constant file is present or not
#Since it require to ping internal network , host server internal network IP must be defined
if [ ! ${HOST_SERVER_INTERNAL_IP} ]; then
	dbgprint 1 "The HOST_SERVER_INTERNAL_IP variable is not defined."
	dbgprint 1 "aborting the test."
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
    dbgprint 6 "Network device path $NET_PATH does not exists"
    dbgprint 6 "Exiting test as aborted "
    UpdateTestState "TestAborted"
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

echo " No of adapter inside  VM is $NO_NW_ADAPTER  "
echo " Const file  is $NW_ADAPTER "

if [[ "$NW_ADAPTER" -eq "$NO_NW_ADAPTER" ]] ; then
        dbgprint 1  "Number of network adapter present inside VM is correct"
else
	dbgprint 1  "Number of network adapter present inside VM is incorrect"
	UpdateTestState "TestAborted"
	exit 1

fi


# Define the Flag variable 
# Flag variable is used to track the status of the Test
# 1 (Test PASS) 0 (Test Fail)
# Initially the flag variable will be set to 1 (PASS)
PASS=1

# to check the Synthetic Network Adapter
for DEVICE in  ${NET_DEVICE[@]} ; do

        ifconfig $DEVICE  >/dev/null 2>&1
        sts=$?
        if [ 0 -ne ${sts} ]; then
                echo -e "Network Adapter : $DEVICE , is not correctly configure in VM. "
			dbgprint 1 "ifconfig <$DEVICE> failed: ${sts}"
	        	dbgprint 1 "Aborting test."
        		UpdateTestState "TestAborted"
			exit 1
        else
                dbgprint 1  "Synthetic network adapter $DEVICE is present inside VM  "
          
        fi

        # Make sure it's not affected by NetworkManager or other scripts
        ifdown $DEVICE

        IP_ADDRESS=( `ifconfig $DEVICE | grep Bcast | awk '{print $2}' | cut -f 2 -d ":"`  )
	if [[ "$IP_ADDRESS" != "" ]] ; then
			dbgprint 1 "IP Address of this system is  :$IP_ADDRESS"

	           dbgprint 1 "System has got IP Address $IP_ADDRESS : Invalid Case"
			dbgprint 1 "Aborting test."
                UpdateTestState "TestAborted"
                exit 1
	fi

# Assign Static IP to the  Guest only Network Adapter
static_ip=${PRIVATE_STATIC_IP}
network_mask=${PRIVATE_NETWORK_MASK}
ifconfig $DEVICE $static_ip
ifconfig $DEVICE netmask $network_mask
sts=$?
             if [ 0 -ne ${sts} ]; then
             		dbgprint 1 "Static IP is not assiged to $DEVICE. "
             		dbgprint 1 "Assign Static IP for <$DEVICE> failed: ${sts}" 
				dbgprint 1 "Cannot Proceed further with the test" 

             		dbgprint 1 "Aborting test."
             		UpdateTestState "TestAborted"
				UpdateSummary "Static IP set to $static_ip : Failed"      

             		exit 1
        		else
             		dbgprint 1  "Static IP: $static_ip set to $DEVICE : Success"  
			     UpdateSummary "Static IP set to : $static_ip "      
        		fi
ifconfig $DEVICE up

# Guest only Network Test

dbgprint 1 "We are going to Test if IP address can ping Other VM's GUEST ONLY IP (Guest Only Network) : $VM_GUEST_ONLY_IP ......."

# if the return is Not Equal to 0 (successful)...
	ping -I $DEVICE -c 10 $VM_GUEST_ONLY_IP > /dev/null 2>&1
sts=$?
        if [ ${sts} -ne "0" ]; then
		dbgprint 1  "Network adapter card :$DEVICE  cannot ping Other VM's GUEST ONLY IP (Guest Only Network) : $VM_GUEST_ONLY_IP"
		PASS=0
		UpdateSummary "Ping to Guest Only Network : Failed"
        else
		dbgprint 1  "Network adapter card : $DEVICE  can ping Other VM's GUEST ONLY IP (Guest Only Network) : $VM_GUEST_ONLY_IP!!"
		UpdateSummary "Ping to Guest Only Network : Success"      
		             
	  fi

# Internal Network Test

dbgprint 1 "We are going to Test if IP address can ping the HOST SERVER INTERNAL IP (Internal Network) : $HOST_SERVER_INTERNAL_IP ......."

# if the return is Not Equal to 0 (successful)...
	ping -I $DEVICE -c 10 $HOST_SERVER_INTERNAL_IP > /dev/null 2>&1
sts=$?
        if [ ${sts} -ne "0" ]; then
		dbgprint 1  "Guest Only Network adapter card : $DEVICE  cannot ping the HOST SERVER INTERNAL IP :$HOST_SERVER_INTERNAL_IP"
          UpdateSummary "Ping to Internal Network should fail : Success" 
		
        else
		dbgprint 1  "Guest Only Network adapter card : $DEVICE  can ping the HOST SERVER INTERNAL IP :$HOST_SERVER_INTERNAL_IP  !!"
		PASS=0     
		UpdateSummary "Ping to Internal Network : Success"                 
	  fi

# External Network Test
  
dbgprint 1 "We are going to Test if IP address can ping the REPOSITORY SERVER (External Network) : $REPOSITORY_SERVER "

# if the return is Not Equal to 0 (successful)...
	ping -I $DEVICE -c 10 $REPOSITORY_SERVER > /dev/null 2>&1
	sts=$?
	
        if [ ${sts} -ne "0" ]; then
			dbgprint 1  "Guest Only Network adapter card cannot ping the REPOSITORY SERVER :$REPOSITORY_SERVER "
               UpdateSummary "Ping to External Network should Fail : Success"      
        else
			PASS=0
                dbgprint 1  "Guest Only Network adapter card inside  VM can ping REPOSITORY SERVER : $REPOSITORY_SERVER !!"
		UpdateSummary "Ping to External Network  : Success"      
	  fi


done # end of Outer For loop

#Clean up system
rm -rf ~/tmp.txt

echo "#########################################################"
echo -e "PASS=$PASS"
if [ 1 == ${PASS} ]; then
		echo "Result : Test Completed Succesfully"
		dbgprint 1 "Exiting with state: TestCompleted."
		UpdateTestState "TestCompleted"
else      
		echo "Result : Test Failed"
		dbgprint 1 "Exiting with state: TestAborted."
		UpdateTestState "TestAborted"
            		        
fi




















