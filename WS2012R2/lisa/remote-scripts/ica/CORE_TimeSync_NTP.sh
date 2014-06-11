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
#
# Synopsis
#     This tests Network Time Protocol sync.
#
# Description
#     This script was created to automate the testing of a Linux
#     Integration services. It enables Network Time Protocol and 
#     checks if the time is in sync.
#    
#     
#     A typical xml entry looks like this:
# 
#         <test>
#             <testName>TimeSyncNTP</testName>
#             <testScript>CORE_TimeSync_NTP.sh</testScript>
#             <files>remote-scripts/ica/CORE_TimeSync_NTP.sh</files>
#             <timeout>600</timeout>
#             <onError>Continue</onError>
#             <testParams>
#                 <param>TZONE=Europe/Berlin</param>
#             </testParams>
#         </test>
#    
#
# Parameter TZONE
#       The TZONE param is using the IANA Timezone definition.
#       http://en.wikipedia.org/wiki/List_of_tz_database_time_zones
#
#       Example:
#       TZONE=Europe/Berlin
#
#       Important:
#       The TZONE param has to be the same timzone as the host, in any
#       other situation the test will fail.   
#
########################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error while performing the test

########################################################################
# Adds a timestamp to the log file
########################################################################
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
        *suse*)
            echo "SLES";;
        Red*Hat*)
            echo "RHEL";;
        Debian*)
            echo "DEBIAN";;
    esac
}

#######################################################################
# Adds a timestamp to the log file
#######################################################################
LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

#######################################################################
# Keeps track of the state of the test
#######################################################################
UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

cd ~

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

#######################################################################
# Updates the summary log file
#######################################################################
UpdateSummary()
{
    echo $1 >> ~/summary.log
}

####################################################################### 
# 
# Main script body 
# 
#######################################################################

# Create the state.txt file so LISA knows we are running
UpdateTestState $ICA_TESTRUNNING

# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

# Make sure the constants.sh file exists
if [ ! -e ./constants.sh ];
then
    echo "Cannot find constants.sh file."
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

# Source the constants file
if [ -e $HOME/constants.sh ]; then
 . $HOME/constants.sh
else
 echo "ERROR: Unable to source the constants file."
 exit 1
fi

# Convert any .sh files to Unix format 
dos2unix ~/* > /dev/null  2>&1

LogMsg "This script tests NTP time syncronization"
LogMsg "VM is $(LinuxRelease) `uname`"

# Check if the timezone variable is in constants
if [ ! ${TZONE} ]; then
    echo "No TZONE variable in constants.sh"
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

# Let's check if the NTP service is installed 
service ntp restart 1> /dev/null 2> /dev/null
sts=$?      
    if [ 0 -ne ${sts} ]; then
    service ntpd restart 1> /dev/null 2> /dev/null
    sts=$?      
        if [ 0 -ne ${sts} ]; then
        LogMsg "No NTP service detected. Please install NTP before running this test"
        LogMsg "Aborting test."
        UpdateTestState $ICA_TESTABORTED
        
        exit 1
        fi
    fi
 
# Now we set the corect timezone for the test. This is distro-specific
case $(LinuxRelease) in
    "DEBIAN" | "UBUNTU")
    sed -i 's#^Zone.*# Zone="$TZONE" #g' /etc/timezone
    sts=$?      
        if [ 0 -ne ${sts} ]; then
            LogMsg "Unable to sed Zone: ${sts}"
            LogMsg "Aborting test."
            UpdateTestState $ICA_TESTABORTED
            exit 1
        fi
    sed -i 's/^UTC.*/ UTC=False /g' /etc/timezone
    sts=$?      
        if [ 0 -ne ${sts} ]; then
            LogMsg "Unable to sed UTC: ${sts}"
            LogMsg "Aborting test."
            UpdateTestState $ICA_TESTABORTED
            exit 1
        fi
    # delete old localtime 
    rm -f /etc/localtime
    #Create soft link.
    ln -s /usr/share/zoneinfo/"$TZONE" /etc/localtime
    sts=$?      
        if [ 0 -ne ${sts} ]; then
            LogMsg "Unable to softlink: ${sts}"
            LogMsg "Aborting test."
            UpdateTestState $ICA_TESTABORTED
            exit 1
        fi

        ;;
    "CENTOS" | "SLES" | "RHEL")
    sed -i 's#^Zone.*# Zone="$TZONE" #g' /etc/sysconfig/clock
    sts=$?      
        if [ 0 -ne ${sts} ]; then
            LogMsg "Unable to sed Zone: ${sts}"
            LogMsg "Aborting test."
            UpdateTestState "TestAborted"
            exit 1
        fi
    sed -i 's/^UTC.*/ UTC=False /g' /etc/sysconfig/clock
    sts=$?      
        if [ 0 -ne ${sts} ]; then
            LogMsg "Unable to sed UTC: ${sts}"
            LogMsg "Aborting test."
            UpdateTestState $ICA_TESTABORTED
            exit 1
        fi

    
    rm -f /etc/localtime # delete old localtime 
    
    ln -s /usr/share/zoneinfo/"$TZONE" /etc/localtime # Create soft link.
    sts=$?      
        if [ 0 -ne ${sts} ]; then
            LogMsg "Unable to softlink: ${sts}"
            LogMsg "Aborting test."
            UpdateTestState $ICA_TESTABORTED
            exit 1
        fi
    ;;
    *)
    LogMsg "Distro not supported"
    UpdateTestState $ICA_TESTABORTED
    UpdateSummary " Distro not supported, test aborted"
    exit 1
    ;; 
esac

# Edit NTP Server config and set the timeservers
sed -i 's/^server.*/ /g' /etc/ntp.conf
echo "
server 0.us.pool.ntp.org
server 1.us.pool.ntp.org
server 2.us.pool.ntp.org
server 3.us.pool.ntp.org
" >> /etc/ntp.conf
 
sts=$?      
    if [ 0 -ne ${sts} ]; then
        LogMsg "Unable to sed Server: ${sts}"
        LogMsg "Aborting test."
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi

# Restart ntp service.
service ntp restart 2> /dev/null
service ntpd restart 2> /dev/null 

# Check if the timezone
tz=`date +%Z`
LogMsg "Timezone is $tz"

# We wait 5 seconds for the ntp server to sync
sleep 5

# Now let's test if the VM is in sync with ntp server
ntpdc -p
sts=$?      
    if [ 0 -ne ${sts} ]; then
        LogMsg "Unable to query NTP deamon: ${sts}"
        LogMsg "Aborting test."
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi

delay=`ntpdc -p | awk 'NR==3 {print $6}'`
LogMsg "NTP delay: $delay"

    if [[ $a < 5.00000 ]]; then

        LogMsg  "NTP Time: synced"
        UpdateSummary "Timesync NTP: Success"
    else
        LogMsg  "NTP Time out of sync"
        UpdateSummary "Timesync NTP: Failed"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

LogMsg "Result: Test Completed Succesfully"
LogMsg "Exiting with state: TestCompleted."
UpdateTestState $ICA_TESTCOMPLETED
exit 0