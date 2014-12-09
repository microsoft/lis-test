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
#     Integration services.this script test the if   
#     network adapter is present inside guest vm and is equal to
#     Hyper-V setting pane by performing the following
#     steps:
#	  1. Make sure we were given a configuration file with no. #of NIC present
#	  2. Get the Network adapter count inside Linux VM 
#         3. Compare it with the Network adapter count in constants file.
#         4.Disable all the legacy network adapters present in the 
#           VM.(We are doing this step because of bug ID :132 )
#	  5.For  Fedora we need to update the route table (Note : 
#           Route can be updated only once and only for one        
#           Synthetic network Adapter.If there are multiple              
#          synthetic network Adapters present then route command    
#        won't work)
#      6.Ping the external network through the Synthetic network Adapter
#        card
#      7.Enable all the legacy network adapters present in the 
#        VM.
#	 To identify objects to compare with, we source a 
#     constansts file
#     named.   This file will be given to us from 
#     Hyper-V Host server.  It contains definitions like:
#         VCPU=1
#         Memory=2000


ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

LogMsg "########################################################"
LogMsg "This is Test Case to Verify If Network adapter can ping external network "

cd ~

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

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
    LogMsg "$msg"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi


#Check for Testcase count
if [ ! ${TC_COUNT} ]; then
    LogMsg "The TC_COUNT variable is not defined."
	echo "The TC_COUNT variable is not defined." >> ~/summary.log
    LogMsg "Terminating the test."
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

echo "Covers : ${TC_COUNT}" >> ~/summary.log

## Check if Variable in Const file is present or not
if [ ! ${NW_ADAPTER} ]; then
	LogMsg "The NW_ADAPTER variable is not defined."
	echo "The NW_ADAPTER variable is not defined." >> ~/summary.log
	UpdateTestState $ICA_TESTABORTED
	exit 30
fi

if [ ! ${GATEWAY} ]; then
	LogMsg "The GATEWAY variable is not defined."
	echo "The GATEWAY variable is not defined." >> ~/summary.log
	UpdateTestState $ICA_TESTABORTED
	exit 30
fi


#Since it require to ping external network external network ip must be defined
if [ ! ${REPOSITORY_SERVER} ]; then
	LogMsg "The REPOSITORY_SERVER variable is not defined."
	echo "The REPOSITORY_SERVER variable is not defined." >> ~/summary.log
	UpdateTestState $ICA_TESTABORTED
	exit 40
fi

# Constant file path
#NET_PATH="/sys/devices/vmbus_0_0"
NO_NW_ADAPTER=`find /sys/devices -name net | grep vmbus* | wc -l`

i=1
while [ $i -le  $NO_NW_ADAPTER ] 
do
NET_PATH=`find /sys/devices -name net | grep vmbus* | sed -n ${i}p`
if [ ! -e ${NET_PATH} ]; then
    LogMsg "Network device path $NET_PATH does not exists"
    echo "Network device path $NET_PATH does not exists" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
	exit 50
fi 
cd $NET_PATH
DEVICE=`ls`

LogMsg " No. of adapter inside  VM is $NO_NW_ADAPTER  "
LogMsg " NW_ADAPTER in Constant.sh file  is $NW_ADAPTER "

if [[ "$NW_ADAPTER" -eq "$NO_NW_ADAPTER" ]] ; then
   LogMsg  "Number of network adapter present inside VM is correct"
else
   LogMsg "Number of network adapter present inside VM is incorrect"
   echo "Number of network adapter present inside VM is incorrect" >> ~/summary.log
   UpdateTestState $ICA_TESTFAILED
   exit 60
fi

# to check the Synthetic Network Adapter
    ifconfig $DEVICE  >/dev/null 2>&1
    sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "Network Adapter : $DEVICE , is not correctly configure in VM. "
		LogMsg "ifconfig <$DEVICE> fialed: ${sts}"
	    echo "ifconfig <$DEVICE> fialed: ${sts}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
		exit 90
    else
        LogMsg  "Synthetic network adapter $DEVICE is present inside VM  "
		echo "Synthetic network adapter is : $DEVICE " >> ~/summary.log
    fi
	
	# check for fedora
    if [ -f /etc/redhat-release ] ; then
	  	ifconfig $DEVICE up >/dev/null 2>&1
	else
		#Its OpenSUSE
		ifup $DEVICE >/dev/null 2>&1
    fi
	sleep 2

    IP_ADDRESS=( `ifconfig $DEVICE | grep Bcast | awk '{print $2}' | cut -f 2 -d ":"`  )
	if [[ "$IP_ADDRESS" == "" ]] ; then
	    LogMsg "System Does not got IP Address"
		echo "System Does not got IP Address" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
		exit 100
    else
	    LogMsg "IP Address of this system is  :$IP_ADDRESS"
		echo "Synthetic network adapter IP is :$IP_ADDRESS" >> ~/summary.log
	fi

		
    # end of  route table updation for fedora
    LogMsg "We are going to Test if IP address can ping other network or not"
    # if the return is Not Equal to 0 (successful)...
	
	sleep 2
	ping -I $DEVICE -c 5 $REPOSITORY_SERVER > /dev/null 2>&1
    if [ "$?" -ne "0" ]; then
        LogMsg "Network adapter card can not ping external, update route"
				
		#
        # Update the route table
        # Note : The route table can be updated for only one Synthetic Network Adapter
        route add default gw $GATEWAY $DEVICE
        sts=$?
        LogMsg  "route table updation status for $DEVICE = $sts"
        if [ 0 -ne ${sts}  ]; then
           LogMsg "Route table is not updated correctly for $DEVICE. "
           LogMsg "route add for <$DEVICE> failed: ${sts}" 
        #echo "route add for <$DEVICE> failed: ${sts}" >> ~/summary.log
        #UpdateTestState $ICA_TESTFAILED
        #exit 100
        else
            LogMsg  "Route table for $DEVICE  is updated successfully  inside VM  "        
        fi
		ping -I $DEVICE -c 5 $REPOSITORY_SERVER > /dev/null 2>&1
        if [ "$?" -ne "0" ]; then
		LogMsg "Network adapter card can not ping external!"
		echo "Network adapter card can not ping external!" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
		exit 120
        else
            LogMsg  "Network adapter card inside  VM can ping external network !! "
		    echo "ping -I $DEVICE -c 10 $REPOSITORY_SERVER :  success" >> ~/summary.log
	    fi
		# check for fedora
        if [ -f /etc/redhat-release ] ; then
	  	ifconfig $DEVICE down >/dev/null 2>&1
	    else
		#Its OpenSUSE
		    ifdown $DEVICE >/dev/null 2>&1
        fi
	sleep 2
    fi
	i=$[$i+1]
done

#Clean up system
rm -rf ~/tmp.txt

LogMsg "#########################################################"
LogMsg "Exiting with state: TestCompleted."
UpdateTestState $ICA_TESTCOMPLETED
exit 0