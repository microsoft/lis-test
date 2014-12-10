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
#     Integration services.this script test the if network mode #     can be setup to "normal" and "promiscous" mode.
#     
#     steps:
#	 1. Make sure we were given a configuration file.
#	 2. Verify LIC modules netvsc is loaded.
#     3. This script should be run only after LIC is installed.
#	 5. Make sure by default network is set to Normal mode.     
#     6. Make sure you can change the mode to promiscous.

DEBUG_LEVEL=3
        
cd ~

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

dbgprint()
{
    if [ $1 -le $DEBUG_LEVEL ]; then
        echo "$2"
    fi
}

if [ -e ~/summary.log ]; then
    dbgprint 1 "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

#
# Convert any .sh files to Unix format
#

dbgprint 1 "Converting the files in the ica director to unix EOL"
dos2unix -f ica/* > /dev/null  2>&1

if [ -e $HOME/ica/config ]; then
	. $HOME/ica/config
else
	echo "ERROR: Unable to source the Automation Framework config file."
	UpdateTestState "TestAborted"
	exit 1
fi



UpdateTestState "TestRunning"

#Source the FTM Framework script
if [ -e $ICA_BASE_DIR/FTM-FRAMEWORK.sh ]; then
 . $ICA_BASE_DIR/FTM-FRAMEWORK.sh
else
 echo "ERROR: Unable to source the FRAMEWORK file."
 exit 1
fi

#Determine wheather vmbus modules is loaded or not

verifymodule hv_netvsc 
sts=$?
if [ 0 -ne ${sts} ]; then
	dbgprint 1 "netvsc Failed to load on the system, please check if you have LIC installed"
	dbgprint 1 "Aborting test."
	UpdateTestState "TestAborted"
	exit 1
else
	dbgprint 1 "netvsc Module is up and running inside guest VM. "\n
fi

## Clear the Log in /var/log/messages

sleep 3
echo -n > /var/log/messages
 
#remove the NETVSC module


rmmod hv_netvsc
sts=$?
if [ 0 -ne ${sts} ]; then
        dbgprint 1 "netvsc Failed to Unload on the system, something went wrong"
        dbgprint 1 "Aborting test."
        UpdateTestState "TestAborted"
        exit 1
else
        dbgprint 1 "Unloaded netvsc Module Succesfully."
fi

sleep 3
modprobe hv_netvsc
sts=$?
if [ 0 -ne ${sts} ]; then
        dbgprint 1 "netvsc Failed to load on the system, something went wrong"
        dbgprint 1 "Aborting test."
        UpdateTestState "TestAborted"
	exit 1
else
        dbgprint 1 "netvsc module loaded Succesfully."
	sleep 5 
	log=$(cat /var/log/messages | grep NETVSC:) 
	if [[ $log =~ "normal mode" ]]; then
		dbgprint 1 "Result 1 : Test PASS : Using  netvsc promisc_mode=0 Network is set to Normal Mode."
	else
		dbgprint 1 "Test Fail : Network mode is not set to  Normal Mode."\n
		dbgprint 1 "Something went wrong please check manually why normal mode is not active. probebly network mode is not supported"
		UpdateTestState "TestAborted"
		exit 1
	fi	
fi


## Clear the Log in /var/log/messages
sleep 3
echo -n > /var/log/messages

#remove the NETVSC module
rmmod hv_netvsc
sts=$?
if [ 0 -ne ${sts} ]; then
        dbgprint 1 "netvsc Failed to Unload on the system, something went wrong"
        dbgprint 1 "Aborting test."
        UpdateTestState "TestAborted"
        exit 1
else
        dbgprint 1 "Unloaded netvsc Module Succesfully."
fi

sleep 3
# Load the netvsc module
modprobe hv_netvsc promisc_mode=1
sts=$?
if [ 0 -ne ${sts} ]; then
        dbgprint 1 "netvsc Failed to load on the system, something went wrong"
        dbgprint 1 "Aborting test."
        UpdateTestState "TestAborted"
        exit 1
else
        dbgprint 1 "netvsc module loaded Succesfully."
	sleep 5 
        log=$(cat /var/log/messages | grep NETVSC)
	if [[ $log =~ "promiscuous mode" ]]; then
		dbgprint 1 "Result 2 : Test PASS : Using promisc_mode=1 Network is set to Promiscous Mode."
                UpdateTestState "TestRunning"
        else
                dbgprint 1 "Test Fail : Using promisc_mode=1 Network is not set to  Promiscous Mode."
                dbgprint 1 "Something went wrong please check manually why normal mode is not active."
                UpdateTestState "TestAborted"
                exit 1
        fi
fi

## Clear the Log in /var/log/messages

sleep 3
echo -n > /var/log/messages

#remove the NETVSC module
rmmod hv_netvsc
sts=$?
if [ 0 -ne ${sts} ]; then
        dbgprint 1 "netvsc Failed to Unload on the system, something went wrong"
        dbgprint 1 "Aborting test."
        UpdateTestState "TestAborted"
        exit 1
else
        dbgprint 1 "Unloaded netvsc Module Succesfully."
fi

# Load the netvsc module
# This section will test if any value other then 0 and 1 is used network should set to normal mode

sleep 3
modprobe hv_netvsc promisc_mode=100
sts=$?
if [ 0 -ne ${sts} ]; then
        dbgprint 1 "netvsc Failed to load on the system, something went wrong"
        dbgprint 1 "Aborting test."
        UpdateTestState "TestAborted"
        exit 1
else
        dbgprint 1 "netvsc module loaded Succesfully."
	sleep 5
        log=$(cat /var/log/messages | grep NETVSC)
	if [[ $log =~ "normal mode" ]]; then
                dbgprint 1 "Result 3 : Test PASS : Using promisc_mode=100 Network is set to normal Mode."
                UpdateTestState "TestRunning"
        else
                dbgprint 1 "Test Fail : Using promisc_mode=100 Network is not set to normal Mode."
                dbgprint 1 "Something went wrong please check manually why normal mode is not active."
                UpdateTestState "TestAborted"
                exit 1
        fi
fi

echo "#########################################################"
echo "Result : Test Completed Succesfully"
echo "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"

