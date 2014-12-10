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

echo "########################################################"
echo "This is Test Case to perform Secure Copy"

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
#Since it require to ping external network external network ip must be defined
if [ ! ${REPOSITORY_SERVER} ]; then
	dbgprint 1 "The REPOSITORY_SERVER variable is not defined."
	dbgprint 1 "aborting the test."
	UpdateTestState "TestAborted"
	exit 1
fi

# Check if FILE_PATH variable in Const file is present or not
# FILE_PATH variable contains the file to be copied along with
# its path
if [ ! ${FILE_PATH} ]; then
	dbgprint 1 "The FILE_PATH variable is not defined."
	dbgprint 1 "aborting the test."
	UpdateTestState "TestAborted"
	exit 1
fi



# Create the state.txt file so the ICA script knows
# we are running


UpdateTestState "TestRunning"

# Constant file path
NET_PATH="/sys/devices/vmbus_0_0"
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
find -name eth* | cut -f 4 -d "/"  > ~/tmp.txt

#NET_PATH=( `cat ~/tmp.txt | tr '.' ' ' `)
NET_DEVICE=( `cat ~/tmp.txt `)

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
     	  	ifconfig $LEGACY_DEVICE down >/dev/null 2>&1  
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
		dbgprint 1 "ifconfig <$DEVICE> failed: ${sts}"
	        dbgprint 1 "Aborting test."
        	UpdateTestState "TestAborted"
		exit 1
        else
                dbgprint 1  "Synthetic network adapter $DEVICE is present inside VM  "
          
        fi

        IP_ADDRESS=( `ifconfig $DEVICE | grep Bcast | awk '{print $2}' | cut -f 2 -d ":"`  )
	if [[ "$IP_ADDRESS" == "" ]] ; then
	          dbgprint 1 "System has not got IP Address"
			dbgprint 1 "Aborting test."
                UpdateTestState "TestAborted"
                exit 1
	else
	        dbgprint 1 "IP Address of this system is  :$IP_ADDRESS"
	fi

# Update the route table
# Note : The route table can be updated for only one Synthetic    # Network Adapter
	  	route add default gw 10.200.48.1 $DEVICE 
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

# end of  route table updation 
     
dbgprint 1 "We are going to Test if IP address can ping the REPOSITORY SERVER : $REPOSITORY_SERVER ......."
# if the return is Not Equal to 0 (successful)...
	ping -I $DEVICE -c 10 $REPOSITORY_SERVER > /dev/null 2>&1
        if [ "$?" -ne "0" ]; then
                dbgprint 1  "Network adapter card cannot ping the REPOSITORY SERVER so we cannot perform secure copy test"
			dbgprint 1 "Aborting test."
                UpdateTestState "TestAborted"
                exit 1
        else
                dbgprint 1  "Network adapter card inside  VM can ping REPOSITORY SERVER : $REPOSITORY_SERVER !!"


# To copy from the Repository Server to VM
dbgprint 1  "Copying data from Repository Server:$REPOSITORY_SERVER to VM........ "
scp -i /root/.ssh/ica_repos_id_rsa -l 8192 -v -r root@$REPOSITORY_SERVER:$FILE_PATH /tmp/
sts=$?
                dbgprint 1  "scp <REPOSITORY SERVER> to <VM> status = $sts"
         		if [ 0 -ne ${sts} ]; then
             		dbgprint 1 "SCP <REPOSITORY SERVER> to <VM> Failed : ${sts}" 
                     dbgprint 1 "Aborting test."
             		UpdateTestState "TestAborted"
				UpdateSummary "Copying large files from external server to VM : Failed"

             		exit 1
        		else
             		dbgprint 1  "Data has been copied successfully from REPOSITORY SERVER to VM  "   
				UpdateSummary "Copying large files from external server to VM : success "
     
        		fi

#To copy data from VM to REPOSITORY SERVER
dbgprint 1  "Copying data from VM to Repository Server........ "
scp -i /root/.ssh/ica_repos_id_rsa -l 8192 -v -r $FILE_PATH root@$REPOSITORY_SERVER:/tmp/DataCopy
sts=$?
         		dbgprint 1  "scp <VM> to <SERVER> status = $sts"
         		if [ 0 -ne ${sts} ]; then
             		dbgprint 1 "SCP  <VM> to <REPOSITORY SERVER> Failed : ${sts}" 
                     dbgprint 1 "Aborting test."
             		UpdateTestState "TestAborted"
				UpdateSummary "Copying large files from VM to external server: Failed"

             		exit 1
        		else
             		dbgprint 1  "Data has been copied successfully from VM to Repository Server"     
				UpdateSummary "Copying large files from VM to external server: success"
   
        		fi
       fi

# To clean up the repository server
ssh -i /root/.ssh/ica_repos_id_rsa root@$REPOSITORY_SERVER rm -rf /tmp/DataCopy
sts=$?
         		dbgprint 1  "ssh status = $sts"
         		if [ 0 -ne ${sts} ]; then
             		dbgprint 1 " ssh : delete file from Repository server Failed : ${sts}" 
                     dbgprint 1 "Aborting test."
             		UpdateTestState "TestAborted"
             		exit 1
        		else
             		dbgprint 1  "DataCopy file has been deleted successfully from the Repository Server"        
        		fi

done

# To enable the Legacy network Adapters
for LEGACY_DEVICE in ${LEGACY_NET_DEVICE[@]} ; do
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
	            
done


#Clean up system
rm -rf ~/tmp.txt

echo "#########################################################"
echo "Result : Test Completed Succesfully"
dbgprint 1 "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"



















