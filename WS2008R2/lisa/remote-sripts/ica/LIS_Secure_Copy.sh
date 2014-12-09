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
#     This script is used to verify that the network does'nt 
#     loose connection by copying a large file(~10GB)file 
#     between two VM's with IC installed.
#     Steps:
#	  1. Make sure we were given a configuration file with         
#         REPOSITORY SERVER and FILE PATH
#	  2. Disable all the legacy network adapters present in
#          the VM.(We are doing this step because of bug ID:132)
#	  3. Update the route table (Note : Route can be updated 
#         only once and only for one Synthetic network 
#         Adapter.if there are multiple              
#        synthetic network Adapters presend then route command     
#        won't work)
#      4.Ping the external network through the Synthetic Adapter 
#        card
#      5.Copy data from repository server to the VM.
#      6.Copy data from VM to repository server.
#      7.Enable all the legacy network adapters present in the 
#        VM.
#	 To identify objects to compare with, we source a 
#     constansts file
#     This file will be given to us from 
#     Hyper-V Host server.  
#     It contains definitions like:
#         REPOSITORY SERVER="10.200.41.67"
#         FILE_PATH="/tmp/Data"


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
LogMsg "This is Test Case to perform Secure Copy"

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

#
# Source the constants file
#
if [ -e ~/${CONSTANTS_FILE} ]; then
    source ~/${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    LogMsg "$msg"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

#
#Check for Testcase count
#
if [ ! ${TC_COUNT} ]; then
    LogMsg "The TC_COUNT variable is not defined."
	echo "The TC_COUNT variable is not defined." >> ~/summary.log
    LogMsg "Terminating the test."
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

echo "Covers : ${TC_COUNT}" >> ~/summary.log

#
# Check if Variable in Const file is present or not
# 
#Since it require to ping external network external network ip must be defined
if [ ! ${REPOSITORY_SERVER} ]; then
	LogMsg "The REPOSITORY_SERVER variable is not defined."
	echo "The REPOSITORY_SERVER variable is not defined." >> ~/summary.log
	UpdateTestState $ICA_TESTABORTED
	exit 30
fi

if [ ! ${REPOSITORY_EXPORT} ]; then
    LogMsg "Error: constants did not define the variable REPOSITORY_EXPORT"
	echo "Error: constants did not define the variable REPOSITORY_EXPORT" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 40
fi


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
        exit 150
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
	# check for fedora
    #if [ -f /etc/redhat-release ] ; then
	#  	ifconfig $DEVICE up >/dev/null 2>&1
	#else
		#Its OpenSUSE
	#	ifup $DEVICE >/dev/null 2>&1
   # fi
	#sleep 2
	

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

     
    LogMsg "We are going to Test if IP address can ping the REPOSITORY SERVER : $REPOSITORY_SERVER ......."
    ping -I $DEVICE -c 10 $REPOSITORY_SERVER > /dev/null 2>&1
    if [ "$?" -ne "0" ]; then
        LogMsg "Network adapter card cannot ping the REPOSITORY SERVER so we cannot perform secure copy test"
        echo "Network adapter card cannot ping the REPOSITORY SERVER so we cannot perform secure copy test" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
		enable_leg
        exit 110
    else
        LogMsg  "Network adapter card inside  VM can ping REPOSITORY SERVER : $REPOSITORY_SERVER !!"
    fi
	
	    #
        # To copy from the Repository Server to VM
        #
        LogMsg  "Copying data from Repository Server:$REPOSITORY_SERVER to VM........ "
        mkdir /nfs
		mount -o nolock ${REPOSITORY_SERVER}:${REPOSITORY_EXPORT} /nfs
        sts=$?
	    if [ 0 -ne ${sts} ]; then
            LogMsg "Mounting <REPOSITORY SERVER> Failed : ${sts}" 
            UpdateTestState $ICA_TESTFAILED
			enable_leg
            echo "Copying large files from external server to VM : Failed" >> ~/summary.log
            exit 120
        else
            LogMsg  "REPOSITORY SERVER Mounted successfully "   
        fi
		
		cp /nfs/test/md5sum /root
		sts=$?
        if [ 0 -ne ${sts} ]; then
            umount /mnt
            msg="Unable to copy md5sum from nfs export : ${sts}"
            LogMsg "$msg"
            echo $msg >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
			enable_leg
            exit 70
        fi
		
		cp /nfs/test/large_file /usr
		sts=$?
        LogMsg  "Copy from <REPOSITORY SERVER> to <VM> status = $sts"
        if [ 0 -ne ${sts} ]; then
            LogMsg "Copy from <REPOSITORY SERVER> to <VM> Failed : ${sts}" 
            UpdateTestState $ICA_TESTFAILED
			enable_leg
            echo "Copying large files from external server to VM : Failed" >> ~/summary.log
            exit 120
        else
            LogMsg  "Data has been copied successfully from REPOSITORY SERVER to VM  "   
            echo "Copying large files from external server to VM : success " >> ~/summary.log
        fi
	#
    # Check the MD5Sum
    #
    LogMsg "Checking the md5sum of the file"

    sum=`cat /root/md5sum | cut -f 4 -d ' '`
    fileSum=`md5sum /usr/large_file | cut -f 1 -d ' '`
	LogMsg "$sum and $fileSum"
    if [ "$sum" != "$fileSum" ]; then
        msg="md5sum of copied file does not match"
        LogMsg "$msg"
        echo $msg >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
		enable_leg
        exit 90
    fi
done

rm -rf /usr/large_file

#
# To enable the Legacy network Adapters
#
enable_leg

#
#Clean up system
#
rm -rf ~/tmp.txt

LogMsg "#########################################################"
LogMsg "Result : Test Completed Succesfully"
LogMsg "Exiting with state: TestCompleted."
UpdateTestState $ICA_TESTCOMPLETED
exit 0