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
#!/bin/bash
#
# Test case for TC6 - Attach synthetic network adapter
#

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
if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
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

#
# Echo TCs we cover
#
echo "Covers ${TC_COVERED}" > ~/summary.log

#
# Check that we have a hn device
#
numVMBusNics=`ifconfig | egrep "^hn" | wc -l`
if [ $numVMBusNics -gt 0 ]; then
    echo "Number of VMBus NICs (hn) found = ${numVMBusNics}"
else
    msg="Error: No VMBus NICs found"
    echo $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 50
fi

i=1152
while [ $i -le 65521 ]
do 
ifconfig hn0 mtu ${i}
j=`ifconfig hn0 | grep mtu | cut -c 70-75`
LogMsg "Current mtu is : ${j}"
sleep 1
i=$[$i*2]
done

echo "Max mtu that can be set is : ${j}" >> ~/summary.log

for pkt in 0 1 48 64 512 1440 1500 1505 4096 4192 25152 
do LogMsg "ping -s $pkt -c ${TARGET_ADDR}"
ping -s $pkt -c 5 ${TARGET_ADDR}
if [ $? -ne 0 ] ; then
    LogMsg "Ping failed for paket size ${pkt} and MTU ${j}"
	echo "Ping failed for paket size ${pkt} and MTU ${j}" >> ~/summary.log
    sleep 1 
	UpdateTestState $ICA_TESTFAILED
	exit 60
fi
done

ifconfig hn0 mtu 1500
ifconfig hn0 | grep -q 1500
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
