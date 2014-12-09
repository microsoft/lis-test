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

#  This script try to set mtu up to 65536 and shows max mtu that can be set
#  Also tries to ping with different packet sizes while max mtu is set
#   
#   Test parameter :
#     NIC: It shows the apdator to be attach is of which network type and uses which network name
#         Example: NetworkAdaptor,External,External_Net
#
#     TARGET_ADDR: It is the ip address to be pinged

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
LogMsg "Updating test case state to running"
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
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

#
# Make sure constants.sh contains the variables we expect
#
if [ "${NIC:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter NIC is not defined in ${CONSTANTS_FILE}"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

if [ "${TC_COVERED:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter TC_COVERED is not defined in ${CONSTANTS_FILE}"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

if [ "${TARGET_ADDR:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter TARGET_ADDR is not defined in ${CONSTANTS_FILE}"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 40
fi

#
# Echo TCs we cover
#
echo "Covers ${TC_COVERED}" > ~/summary.log

#
# Check that we have a eth device
#
numVMBusNics=`ifconfig | egrep "^eth" | wc -l`
if [ $numVMBusNics -gt 0 ]; then
    LogMsg "Number of VMBus NICs (eth) found = ${numVMBusNics}"
else
    msg="Error: No VMBus NICs found"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 50
fi

eth=`ifconfig | egrep "^eth" | cut -d " " -f 1`

i=4096
while [ $i -le 65536 ]
do 
#
# Set mtu
#
    ifconfig ${eth} mtu ${i}
    ifconfig ${eth} | grep MTU | cut -d ":" -f 2 > ~/mtu
	j=`grep Metric ~/mtu | cut -d " " -f 1`
    LogMsg "Current MTU is : ${j}"
    sleep 1
    i=$[$i+4096]
done

echo "Max MTU that can be set is : ${j}" >> ~/summary.log

#
# Ping with different packet sizes
#
rm -f ~/pingdata
for pkt in 0 1 2 4 16 32 128 256 512 1024 1471 1472 1473 25152 25153
do LogMsg "ping -s ${pkt} -c 5 ${TARGET_ADDR}"
    ping -s ${pkt} -c 5 ${TARGET_ADDR} > ~/pingdata
	
	loss=`cat ~/pingdata | grep "packet loss" | cut -d " " -f 6`
	LogMsg "Packet loss is : ${loss}"
	if [ "${loss}" != "0%" ] ; then
        LogMsg "Ping failed for packet size ${pkt} and MTU ${j}"
	    echo "Ping failed for packet size ${pkt} and MTU ${j}" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
	    exit 60
    else
	    LogMsg "Ping Successful"
		sleep 1
	fi
done

#
# Set back default mtu that is 1500
#
ifconfig ${eth} mtu 1500
ifconfig ${eth} | grep -q 1500
if [ $? -eq 0 ] ; then
    LogMsg "Default MTU is set"
    echo "Default MTU is set" >> ~/summary.log
else
    LogMsg "Default mtu setting failed"
	echo "Default mtu setting failed" >> ~/summary.log
	UpdateTestState $ICA_TESTFAILED
	exit 70
fi

#
#If we are here test passed
#
UpdateTestState $ICA_TESTCOMPLETED

exit 0
