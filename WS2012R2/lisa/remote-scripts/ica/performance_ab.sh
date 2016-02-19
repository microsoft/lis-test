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

#######################################################################
#
# performance_ab.sh
#
# Description:
#     Run Apache Benchmark (ab) tool.
#
# Parameters:
#      APACHE_SERVER:               the Apache server name or ip address 
#      APACHE_TEST_NUM_REQUESTS:    specify how many http request will be tested
#      APACHE_TEST_NUM_CONCURRENCY: specify the number of concurrency
#
#######################################################################



ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"


#
# Function definitions
#

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` ": ${1}"
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

#######################################################################
#
# LinuxRelease()
#
#######################################################################
LinuxRelease()
{
    DISTRO=`grep -ihs "buntu\|Suse\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux" /etc/{issue,*release,*version}`

    case $DISTRO in
        *buntu*)
            echo "UBUNTU";;
        Fedora*)
            echo "FEDORA";;
        CentOS*)
            echo "CENTOS";;
        *SUSE*)
            echo "SLES";;
        Red*Hat*)
            echo "RHEL";;
        Debian*)
            echo "DEBIAN";;
    esac
}

######################################################################
#
# DoSlesAB()
#
# Description:
#    Perform distro specific Apache and tool installation steps for SLES
#    and then run the benchmark tool
#
#######################################################################
DoSlesAB()
{
    #
    # Note: A number of steps will use SSH to issue commands to the
    #       APACHE_SERVER.  This requires that the SSH keys be provisioned
    #       in advanced, and strict mode be disabled for both the SSH
    #       server and client.
    #

    LogMsg "Info: Running SLES"

    LogMsg "Info: -----------------------------------------"
    LogMsg "Info: Apache server installation on server side"
    ssh root@${APACHE_SERVER} "zypper --non-interactive install apache2"
    LogMsg "Info: Generate test data file to Apache server www htdocs folder"
    ssh root@${APACHE_SERVER} "dd if=/dev/urandom of=./test.dat bs=1K count=${TEST_FILE_SIZE_IN_KB}"
    LogMsg "Info: Restart APache server"
    ssh root@${APACHE_SERVER} "service apache2 stop"
    ssh root@${APACHE_SERVER} "service apache2 start"
    
    LogMsg "Info: -----------------------------------------"
    LogMsg "Info: Apache utility tool installation on client side"
    zypper --non-interactive install apache2-utils
    
    LogMsg "Info: -----------------------------------------"
    LogMsg "Info: Run the benchmark "
    ab2 -n ${APACHE_TEST_NUM_REQUESTS} -c ${APACHE_TEST_NUM_CONCURRENCY} http://${APACHE_SERVER}/test.dat > abtest.log
}

DoUbuntuAB()
{
    #
    # Note: A number of steps will use SSH to issue commands to the
    #       APACHE_SERVER.  This requires that the SSH keys be provisioned
    #       in advanced, and strict mode be disabled for both the SSH
    #       server and client.
    #

    LogMsg "Info: Running Ubuntu"

    LogMsg "Info: -----------------------------------------"
    LogMsg "Info: Apache server installation on server side"
    ssh root@${APACHE_SERVER} "apt-get install -y apache2"
    LogMsg "Info: Generate test data file to Apache server www htdocs folder"
    ssh root@${APACHE_SERVER} "dd if=/dev/urandom of=./test.dat bs=1K count=${TEST_FILE_SIZE_IN_KB}"
    LogMsg "Info: Restart APache server"
    ssh root@${APACHE_SERVER} "service apache2 stop"
    ssh root@${APACHE_SERVER} "service apache2 start"

    LogMsg "Info: -----------------------------------------"
    LogMsg "Info: Apache utility tool installation on client side"
    apt-get install -y apache2-utils

    LogMsg "Info: -----------------------------------------"
    LogMsg "Info: Run the benchmark "
    ab -n ${APACHE_TEST_NUM_REQUESTS} -c ${APACHE_TEST_NUM_CONCURRENCY} http://${APACHE_SERVER}/test.dat > abtest.log
}

DoRhelAB()
{
    #
        # Note: A number of steps will use SSH to issue commands to the
        #       APACHE_SERVER.  This requires that the SSH keys be provisioned
        #       in advanced, and strict mode be disabled for both the SSH
        #       server and client.
        #

    LogMsg "Info: Running RHEL"

    LogMsg "Info: -----------------------------------------"
    LogMsg "Info: Apache server installation on server side"
    ssh root@${APACHE_SERVER} "yum install -y httpd"
    LogMsg "Info: Generate test data file to Apache server www htdocs folder"
    ssh root@${APACHE_SERVER} "dd if=/dev/urandom of=./test.dat bs=1K count=${TEST_FILE_SIZE_IN_KB}"
    LogMsg "Info: Restart APache server"        
    ssh root@${APACHE_SERVER} "systemctl restart httpd.service"

    LogMsg "Info: -----------------------------------------"
    LogMsg "Info: Apache utility tool installation on client side"
    yum install -y httpd-tools

    LogMsg "Info: -----------------------------------------"
    LogMsg "Info: Run the benchmark "
    ab -n ${APACHE_TEST_NUM_REQUESTS} -c ${APACHE_TEST_NUM_CONCURRENCY} http://${APACHE_SERVER}/test.dat > abtest.log
}

#######################################################################
#
# Main script body
#
#######################################################################

cd ~
UpdateTestState $ICA_TESTRUNNING
LogMsg "Starting test"

#
# Delete any old summary.log file
#
LogMsg "Cleaning up old summary.log"
if [ -e ~/summary.log ]; then
    rm -f ~/summary.log
fi

touch ~/summary.log

#
# Source the constants.sh file
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

#
# Make sure the required test parameters are defined
#
if [ "${APACHE_SERVER:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the APACHE_SERVER test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${APACHE_TEST_NUM_REQUESTS:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the APACHE_TEST_NUM_REQUESTS test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${APACHE_TEST_NUM_CONCURRENCY:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the APACHE_TEST_NUM_CONCURRENCY test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

echo "APACHE_SERVER               = ${APACHE_SERVER}"
echo "APACHE_TEST_NUM_REQUESTS    = ${APACHE_TEST_NUM_REQUESTS}"
echo "APACHE_TEST_NUM_CONCURRENCY = ${APACHE_TEST_NUM_CONCURRENCY}"

#
# Install Apache and benchmark tool - this has distro specific behaviour
#
distro=`LinuxRelease`
case $distro in
    "CENTOS" | "RHEL")
        DoRhelAB
    ;;
    "UBUNTU")
        DoUbuntuAB
    ;;
    "DEBIAN")
        DoDebianAB
    ;;
    "SLES")
        DoSlesAB
    ;;
     *)
        msg="Error: Distro '${distro}' not supported"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState "TestAborted"
        exit 1
    ;; 
esac

#
# If we made it here, everything worked.
# Indicate success
#
LogMsg "Test completed successfully"
UpdateTestState $ICA_TESTCOMPLETED

exit 0