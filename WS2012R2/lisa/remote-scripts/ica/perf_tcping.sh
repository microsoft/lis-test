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
# Desctiption:
#    Run tcpng to measure network latency.
#
#    This test script is passed the follown parameters
#    via the constants.sh file:
#        TC_COVERED
#            This lists the test covered by the
#            test case script.
#
#        TCPING_PACKAGE
#            Name of the tar archive with the
#            tcping source code.
#
#        TARGET_IP
#            The IP address of the machine to 
#            connect to.
#
#        TARGET_PORT
#            The port number to connecto on the
#            target host.
#
#    A typical xml test case definition for this test case
#    script would look similar the following:
#
#       <test>
#           <testName>TCPing</testName>
#           <testScript>perf_tcping.sh</testScript>
#           <files>remote-scripts\ica\perf_tcping.sh,tools\listcping-1.3.5.tar.gz</files>
#           <timeout>600</timeout>
#           <onError>Continue</onError>
#           <noReboot>True</noReboot>
#           <testparams>
#               <param>TC_COVERED=PERF-TCPing-01</param>
#               <param>TCPING_PACKAGE=listcping-1.3.5.tar.gz</param>
#               <param>TARGET_IP="192.168.1.106"</param>
#               <param>TARGET_PORT="22"</param
#           </testparams>
#           <uploadFiles>
#               <file>tcping.log</file>
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

if [ "${TC_COVERED}" ]; then
    msg="Test covers : ${TC_COVERED}"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
fi

if [ ! ${TCPING_PACKAGE} ]; then
    msg="Error: Test parameter TCP_PACKAGE not in constants.sh"
    LogMsg "${msg}"
    echo "${msg}"
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

if [ ! ${TARGET_IP} ]; then
    msg="Error: Test parameter TARGET_IP not in constants.sh"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

if [ ! ${TARGET_PORT} ]; then
    msg="Error: Test parameter TARGET_PORT not in constants.sh"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 40
fi

#
# Make sure the tcping tar file is present.
# Then untar the archive, build tcping,
# and copy the executable to /usr/bin
#
LogMsg "Verifying tcping package '${TCPING_PACKAGE}' exists"

if [ ! -e ./${TCPING_PACKAGE} ]; then
    msg="Error: The tcping tar archive (./${TCPING_PACKAGE} does not exist"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 50
fi

#
# Extract the source and build tcping
#
LogMsg "Extracting contents of ${TCPING_PACKAGE}"

tar -xzf ./${TCPING_PACKAGE}
if [ $? -ne 0 ]; then
    msg="Error: Unable to untar file '${TCPING_PACKAGE}'"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 60
fi

rootdir=$(tar -tzf ./${TCPING_PACKAGE} | sed -e 's@/.*@@' | uniq)
if [ ! $rootdir ]; then
    msg="Error: Unable to determins root dir from tar file"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 70
fi

LogMsg "Building tcping"
cd $rootdir
make tcping.linux
if [ $? -ne 0 ]; then
    msg="Error: Unable to build the tcping utility"
    LogMsg "${msg}"
    echo "${msg}"
    UpdateTestState $ICA_TESTFAILED
    exit 80
fi

LogMsg "Copying tcping to /usr/bin"
cp ./tcping /usr/bin/
if [ $? -ne 0 ]; then
    msg="Error: Unable to copy tcping to /usr/bin"
    LogMsg "${msg}"
    echo "${msg}"
    UpdateTestState $ICA_TESTFAILED
    exit 90
fi

cd ~

#
# run tcping and direct output to a log file
#
LogMsg "running tcping"
LogMsg "tcping -t 20 -n 1000 ${TARGET_IP} ${TARGET_PORT}"

tcping -t 20 -n 1000 ${TARGET_IP} ${TARGET_PORT} > ~/tcping.log
if [ $? -ne 0 ]; then
    msg="Error: tcping failed"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 100
fi

LogMsg "Test completed successfully"

UpdateTestState $ICA_TESTCOMPLETED

exit 0

