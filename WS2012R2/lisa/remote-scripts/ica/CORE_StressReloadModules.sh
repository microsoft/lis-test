
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

########################################################################
#
# CORE_StressReloadModules.sh
# Description:
#    This script will first check the existence of Hyper-V kernel modules.
#    Then it will reload the modules 500 times to stress the system.
#    It also checks that hyperv_fb cannot be unloaded.
#    When done it will bring up the eth0 interface and check again for 
#    the presence of Hyper-V modules.
#     
#    To pass test parameters into test cases, the host will create
#    a file named constants.sh. This file contains one or more
#    variable definition.
#
################################################################

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

UpdateSummary()
{
    echo $1 >> ~/summary.log
}

VerifyModules()
{
	MODULES=~/modules.txt
    lsmod | grep hv_* > $MODULES

    #
    # Did VMBus load
    #
    LogMsg "Checking if hv_vmbus loaded..."

    grep -q "vmbus" $MODULES
    if [ $? -ne 0 ]; then
        msg="hv_vmbus not loaded"
        LogMsg "Error: ${msg}"
        echo $msg >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 20
    fi
    LogMsg "hv_vmbus loaded OK"
	
    #
    # Did storvsc load
    #
    LogMsg "Checking if storvsc loaded..."

    grep -q "storvsc" $MODULES
    if [ $? -ne 0 ]; then
        msg="hv_storvsc not loaded"
        LogMsg "Error: ${msg}"
        echo $msg >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 30
    fi
    LogMsg "hv_storvsc loaded OK"
	
    #
    # Did netvsc load
    #
    LogMsg "Checking if hv_netvsc loaded..."

    grep -q "hv_netvsc" $MODULES
    if [ $? -ne 0 ]; then
        msg="hv_netvsc not loaded"
        LogMsg "Error: ${msg}"
        echo $msg >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 30
    fi
    LogMsg "hv_netvsc loaded OK"

    #
    # Did utils load
    #
    LogMsg "Checking if hv_utils loaded..."

    grep -q "utils" $MODULES
    if [ $? -ne 0 ]; then
        msg="hv_utils not loaded"
        LogMsg "Error: ${msg}"
        echo $msg >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 30
    fi
    LogMsg "hv_utils loaded OK"
}

cd ~
UpdateTestState "TestRunning"

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

if [ -e $HOME/constants.sh ]; then
	. $HOME/constants.sh
else
	LogMsg "ERROR: Unable to source the constants file."
	UpdateTestState "TestAborted"
	exit 1
fi

#Check for Testcase covered
if [ ! ${TC_COVERED} ]; then
    LogMsg "Error: The TC_COVERED variable is not defined."
	echo "Error: The TC_COVERED variable is not defined." >> ~/summary.log
    UpdateTestState "TestAborted"
    exit 1
fi

echo "Covers : ${TC_COVERED}" >> ~/summary.log

#
# Start the test 
#
LogMsg "Starting test"

VerifyModules

modprobe -r hyperv_fb
if [ $? -eq 0 ]; then
    msg="hyperv_fb could be disabled."
    LogMsg "Error: ${msg}"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 30
fi
pass=0
START=$(date +%s)
while [ $pass -lt 500 ]
do
    modprobe -r hv_netvsc
    modprobe hv_netvsc
    modprobe -r hv_utils
    modprobe hv_utils
    sleep 1
    modprobe -r hid_hyperv
    modprobe hid_hyperv
    pass=$((pass+1))
    echo $pass
done
END=$(date +%s)
DIFF=$(echo "$END - $START" | bc)
echo $DIFF
echo "Finished testing, bringing up eth0"
ifdown eth0
ifup eth0
VerifyModules
 
echo "Test ran for ${DIFF} seconds" >> ~/summary.log

LogMsg "#########################################################"
LogMsg "Result : Test Completed Successfully"
LogMsg "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"
