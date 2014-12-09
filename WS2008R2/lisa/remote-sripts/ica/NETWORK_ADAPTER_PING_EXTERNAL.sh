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

echo "########################################################"
echo "This is Test Case to Verify If Network adapter can ping external network "

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

## Check if Variable in Const file is present or not
if [ ! ${NW_ADAPTER} ]; then
	dbgprint 1 "The NW_ADAPTER variable is not defined."
	dbgprint 1 "aborting the test."
	UpdateTestState "TestAborted"
	exit 1
fi
if [ ! ${NW_FEDORA_SET_GATEWAY} ]; then
	# To keep compatibility with old behavior. Redmond lab needs
	# this to always set default gateway.
	NW_FEDORA_SET_GATEWAY=1
fi


#Since it require to ping external network external network ip must be defined
if [ ! ${REPOSITORY_SERVER} ]; then
	dbgprint 1 "The REPOSITORY_SERVER variable is not defined."
	dbgprint 1 "aborting the test."
	UpdateTestState "TestAborted"
	exit 1
fi


#
# Create the state.txt file so the ICA script knows
# we are running


UpdateTestState "TestRunning"

# Constant file path
#NET_PATH="/sys/devices/vmbus_0_0"
NET_PATH=`find /sys/devices -name net | grep vmbus*`
if [ ! -e ${NET_PATH} ]; then
    dbgprint 3 "Network device path $NET_PATH does not exists"
    dbgprint 3 "Exiting test as aborted "
    UpdateTestState "TestAborted"
	exit 1

fi


#f tmp file is present please delter it do the apporpriate check by if and all.

rm -rf ~/tmp.txt

cd $NET_PATH
#find -name eth* | cut -f 4 -d "/"  > ~/tmp.txt
ls > /root/tmp.txt

#NET_PATH=( `cat ~/tmp.txt | tr '.' ' ' `)
NET_DEVICE=( `cat ~/tmp.txt `)

#now compare the no. of network adapter is equal to the added adpeter
NO_NW_ADAPTER=( `cat ~/tmp.txt | wc -l `)

echo " No. of adapter inside  VM is $NO_NW_ADAPTER  "
echo " NW_ADAPTER in Constant.sh file  is $NW_ADAPTER "

if [[ "$NW_ADAPTER" -eq "$NO_NW_ADAPTER" ]] ; then
        dbgprint 1  "Number of network adapter present inside VM is correct"
else
	dbgprint 1  "Number of network adapter present inside VM is incorrect"
	UpdateTestState "TestAborted"
	exit 1

fi

# To disable all the Legacy network Adapters present in the VM

NET_LEGACY_PATH="/sys/devices/pci0000:00"

if [ ! -e ${NET_LEGACY_PATH} ]; then
     dbgprint 6 "Network device path $NET_LEGACY_PATH does not exists"
     dbgprint 6 "Exiting test as aborted "
     UpdateTestState "TestAborted"
     exit 1
fi

#if tmp file is present please delter it do the apporpriate check by if and all.

rm -rf ~/tmp.txt
cd $HOME
cd $NET_LEGACY_PATH

find . -name eth* | cut -f 4 -d "/"  > ~/tmp.txt

LEGACY_NET_DEVICE=( `cat ~/tmp.txt | tr '.' ' ' `)

# Disable all the legacy network adpaters one by one
for LEGACY_DEVICE in ${LEGACY_NET_DEVICE[@]} ; do
     # check for fedora
     if  [ -f /etc/redhat-release ] ; then
	  	ifconfig $LEGACY_DEVICE down >/dev/null 2>&1
	  else
		#Its OpenSUSE
		 ifdown $LEGACY_DEVICE >/dev/null 2>&1
     fi
        dbgprint 1  "Legacy Device = $LEGACY_DEVICE" 
        sts=$?
        dbgprint 1  "ifdown result for $LEGACY_DEVICE= $sts"
        if [ 0 -ne ${sts} ]; then
             dbgprint 1 "LEGACY Network Adapter : $LEGACY_DEVICE , is not correctly configured in VM. "
	       dbgprint 1 "ifdown <$LEGACY_DEVICE> failed: ${sts}"
	       dbgprint 1 "Aborting test."
             UpdateTestState "TestAborted"
		exit 1
        else
            dbgprint 1  "$LEGACY_DEVICE  is  successfully disabled inside VM  "
           
       fi
done

# to check the Synthetic Network Adapter
for DEVICE in  ${NET_DEVICE[@]} ; do

        ifconfig $DEVICE  >/dev/null 2>&1
        sts=$?
        if [ 0 -ne ${sts} ]; then
                echo -e "Network Adapter : $DEVICE , is not correctly configure in VM. "
		dbgprint 1 "ifconfig <$DEVICE> fialed: ${sts}"
	        dbgprint 1 "Aborting test."
        	UpdateTestState "TestAborted"
		exit 1
        else

                dbgprint 1  "Synthetic network adapter $DEVICE is present inside VM  "
		UpdateSummary "Synthetic network adapter is : $DEVICE "

           
        fi

        IP_ADDRESS=( `ifconfig $DEVICE | grep Bcast | awk '{print $2}' | cut -f 2 -d ":"`  )
	if [[ "$IP_ADDRESS" == "" ]] ; then
	        dbgprint 1 "System Does not got IP Address"
		dbgprint 1 "Aborting test."
                UpdateTestState "TestAborted"
                exit 1

	else
	        dbgprint 1 "IP Address of this system is  :$IP_ADDRESS"
		UpdateSummary "Synthetic network adapter IP is :$IP_ADDRESS"

	fi

# For fedora update the route table
# Note : The route table can be updated for only one Synthetic    
# Network Adapter
if  [ -f /etc/redhat-release ] ; then
	if [ "${NW_FEDORA_SET_GATEWAY}" != "0" ]; then
	  	route add default gw $GATEWAY $DEVICE 
	        sts=$?
         	dbgprint 1  "route table updation status for $DEVICE = $sts"
         		if [ 0 -ne ${sts} ]; then
             		dbgprint 1 "Route table is not updated correctly for $DEVICE. "
             		dbgprint 1 "route add for <$DEVICE> failed: ${sts}" 
             		dbgprint 1 "Aborting test."
             		UpdateTestState "TestAborted"
             		exit 1
        		else
             		dbgprint 1  "Route table for $DEVICE  is updated successfully  inside VM  "        
        		fi
	fi
fi

# end of  route table updation for fedora

     dbgprint 1 "We are going to Test if IP address can ping other network or not"
# if the return is Not Equal to 0 (successful)...
	ping -I $DEVICE -c 10 $REPOSITORY_SERVER > /dev/null 2>&1
        if [ "$?" -ne "0" ]; then
                dbgprint 1  " Network adapter card can not ping external! "
		dbgprint 1 "Aborting test."
                UpdateTestState "TestAborted"
                exit 1

        else
                dbgprint 1  "Network adapter card inside  VM can ping external network !! "
		UpdateSummary "ping -I $DEVICE -c 10 $REPOSITORY_SERVER :  success"

        fi


done

# To enable the Legacy network Adapters
for LEGACY_DEVICE in ${LEGACY_NET_DEVICE[@]} ; do
         # check for fedora
     	    if  [ -f /etc/redhat-release ] ; then
	  		ifconfig $LEGACY_DEVICE up >/dev/null 2>&1
			sts=$?
         		dbgprint 1  "ifup status for $LEGACY_DEVICE = $sts"
         		if [ 0 -ne ${sts} ]; then
             		dbgprint 1 "LEGACY Network Adapter : $LEGACY_DEVICE , is not correctly configured in VM. "
             		dbgprint 1 "ifdown <$LEGACY_DEVICE> failed: ${sts}" 
             		dbgprint 1 "Aborting test."
             		UpdateTestState "TestAborted"
             		exit 1
        		else
             		dbgprint 1  "$LEGACY_DEVICE  is enabled successfully  inside VM  "        
        		fi
	    else
			#Its OpenSUSE
		 	ifup $LEGACY_DEVICE >/dev/null 2>&1
			sts=$?
         		dbgprint 1  "ifup status for $LEGACY_DEVICE = $sts"
                        # Handle a special case in Redmond lab.
                        if [ "${sts}" = "3" ]; then
                            sts=0
                        fi
         		if [ 0 -ne ${sts} ]; then
             		dbgprint 1 "LEGACY Network Adapter : $LEGACY_DEVICE , is not correctly configured in VM. "
             		dbgprint 1 "ifdown <$LEGACY_DEVICE> failed: ${sts}" 
             		dbgprint 1 "Aborting test."
             		UpdateTestState "TestAborted"
            	     exit 1
                else
             		dbgprint 1  "$LEGACY_DEVICE  is enabled successfully  inside VM  "        
        		fi
	 fi
	         
done


#Clean up system
rm -rf ~/tmp.txt

echo "#########################################################"
echo "Result : Test Completed Succesfully"
dbgprint 1 "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"



















