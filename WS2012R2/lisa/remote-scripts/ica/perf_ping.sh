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
# Description:
#    Perform a number of pings to approximately measure
#    network latency.
#
#    This test script is passed the follow parameters
#    via the constants.sh file:
#
#        TC_COVERED
#            This lists the test covered by the
#            test case script.
#
#        TARGET_IP
#            The IP address of the machine to 
#            connect to.
#
#        PING_COUNT       
#            The number of ping operations to 
#            perform.
#
#    The output of the ping commands is saved to a file
#    named ~/ping.log
#
#    A typical xml test case definition for this test case
#    script would look similar the following:
#
#       <test>
#           <testName>TCPing</testName>
#           <testScript>perf_ping.sh</testScript>
#           <timeout>600</timeout>
#           <onError>Continue</onError>
#           <noReboot>True</noReboot>
#           <testparams>
#               <param>TC_COVERED=PERF-TCPing-01</param>
#               <param>TARGET_IP="192.168.1.101"</param>
#               <param>PING_COUNT="10"</param
#           </testparams>
#           <uploadFiles>
#               <file>ping.log</file>
#           </uploadFiles>
#       </test>
#
###########################################################

ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"


#
# Function definitons
#

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` ": ${1}"   # Add time stamp to message
}


UpdateTestState()
{
    echo $1 > ~/state.txt
}


###########################################################
#
# Main body of script
#
###########################################################

cd ~
UpdateTestState $ICA_TESTRUNNING
LogMsg "Starting test"

#
# Set default ping count before sourcing constants.sh
#
PING_COUNT="4"

#
# delete any old symmary.log files
#
LogMsg "Cleaning up previous copies of summary.log"
if [ -e ~/summary.log ]; then
    rm -f ~/summary.log
fi
touch ~/summary.log

#
# We need the required arguments from the constants.sh file.
# Make sure the file exists, then source it.
#
LogMsg "Sourcing constants.sh"
if [ -e ~/constants.sh ]; then
    . ~/constants.sh
else
    msg="Error: ~/constants.sh does not exist"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

if [ "${TC_COVERED:="UNDEFINED"}" == "UNDEFINED" ]; then
    msg="Test covers : ${TC_COVERED}"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ "${TARGET_IP:="UNDEFINED"}" == "UNDEFINED" ]; then
    msg="Error: Test parameter TARGET_IP not in constants.sh"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

#
# For debug, display the parameters to be used:
#
LogMsg "Info : TARGET_IP  = ${TARGET_IP}"
LogMsg "Info : PING_COUNT = ${PING_COUNT}"

#
# Perform the pings, and redirect output to ping.log
#
if [ "${PING_TOOL:="UNDEFINED"}" == "ping6" ]; then
    ping6 -c ${PING_COUNT} ${TARGET_IP} > ~/ping.log
else
    ping -c ${PING_COUNT} ${TARGET_IP} > ~/ping.log
fi

if [ $? -ne 0 ]; then
    msg="Error: ping -c ${PING_COUNT} ${TARGET_IP} failed"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 50
else
    LogMsg "Test completed successfully"
    UpdateTestState $ICA_TESTCOMPLETED
fi

exit 0

