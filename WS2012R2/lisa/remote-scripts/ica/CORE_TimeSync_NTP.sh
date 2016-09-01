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
#     This script tests NTP time syncronization.
#
# Description
#     This script was created to automate the testing of a Linux
#     Integration services. It enables Network Time Protocol and 
#     checks if the time is in sync.
#    
#     A typical xml entry looks like this:
# 
#         <test>
#             <testName>TimeSyncNTP</testName>
#             <testScript>CORE_TimeSync_NTP.sh</testScript>
#             <files>remote-scripts/ica/CORE_TimeSync_NTP.sh</files>
#             <timeout>600</timeout>
#             <onError>Continue</onError>
#         </test>
#
########################################################################

ICA_TESTRUNNING="TestRunning"       # The test is running
ICA_TESTCOMPLETED="TestCompleted"   # The test completed successfully
ICA_TESTABORTED="TestAborted"       # Error during setup of test
ICA_TESTFAILED="TestFailed"         # Error while performing the test
maxdelay=5.0                        # max offset in seconds.
zerodelay=0.0                       # zero

#######################################################################
# Adds a timestamp to the log file
#######################################################################
function LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1}
}

#######################################################################
# Keeps track of the state of the test
#######################################################################
function UpdateTestState() {
    echo $1 > $HOME/state.txt
}

#######################################################################
# Updates the summary log file
#######################################################################
function UpdateSummary() {
    echo $1 >> ~/summary.log
}

####################################################################### 
# 
# Main script body 
# 
#######################################################################
cd ~

# Create the state.txt file so LISA knows we are running
UpdateTestState $ICA_TESTRUNNING

# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Try to restart NTP. If it fails we try to install it.
if is_fedora ; then
    # Check if ntpd is running
    service ntpd restart
    if [[ $? -ne 0 ]]; then
        echo "Info: NTPD not installed. Trying to install..."
        yum install -y ntp ntpdate
        if [[ $? -ne 0 ]] ; then
            LogMsg "ERROR: Unable to install ntpd. Aborting"
            UpdateTestState $ICA_TESTABORTED
            exit 10
        fi
        
        chkconfig ntpd on
        if [[ $? -ne 0 ]] ; then
            LogMsg "ERROR: Unable to chkconfig ntpd on. Aborting"
            UpdateTestState $ICA_TESTABORTED
            exit 10
        fi
        
        ntpdate pool.ntp.org
        if [[ $? -ne 0 ]] ; then
            LogMsg "ERROR: Unable to set ntpdate. Aborting"
            UpdateTestState $ICA_TESTABORTED
            exit 10
        fi
        
        service ntpd start
        if [[ $? -ne 0 ]] ; then
            LogMsg "ERROR: Unable to start ntpd. Aborting"
            UpdateTestState $ICA_TESTABORTED
            exit 10
        fi
        echo "Info: NTPD has been installed succesfully!"
    fi

    # set rtc clock to system time & restart NTPD
    hwclock --systohc 
    if [[ $? -ne 0 ]]; then
        LogMsg "ERROR: Unable to sync RTC clock to system time. Aborting"
        UpdateTestState $ICA_TESTABORTED
        exit 10
    fi

    service ntpd restart
    if [[ $? -ne 0 ]]; then
        LogMsg "ERROR: Unable to start ntpd. Aborting"
        UpdateTestState $ICA_TESTABORTED
        exit 10
    fi

elif is_ubuntu ; then
    # Check if ntp is running
    service ntp restart
    if [[ $? -ne 0 ]]; then
        LogMsg "NTP is not installed. Trying to install..."
        apt-get install ntp -y
        if [[ $? -ne 0 ]] ; then
            LogMsg "ERROR: Unable to install ntp. Aborting"
            UpdateTestState $ICA_TESTABORTED
            exit 10
        fi
        echo "Info: NTPD has been installed succesfully!"
    fi

    # set rtc clock to system time & restart NTPD
    hwclock --systohc 
    if [[ $? -ne 0 ]]; then
        LogMsg "ERROR: Unable to sync RTC clock to system time. Aborting"
        UpdateTestState $ICA_TESTABORTED
        exit 10
    fi

    service ntp restart
    if [[ $? -ne 0 ]]; then
        LogMsg "ERROR: Unable to restart ntpd. Aborting"
        UpdateTestState $ICA_TESTABORTED
        exit 10
    fi

elif is_suse ; then
    #In SLES 12 service name is ntpd, in SLES 11 is ntp
    os_RELEASE=$(echo $os_RELEASE | sed -e 's/^\(.\{2\}\).*/\1/')
    if  [ $os_RELEASE -eq 11 ]; then
        srv="ntp"
    else
        srv="ntpd"
    fi

    service $srv restart
    if [[ $? -ne 0 ]]; then
        LogMsg "NTP is not installed. Trying to install ..."
        zypper --non-interactive install ntp
        if [[ $? -ne 0 ]] ; then
            LogMsg "ERROR: Unable to install ntp. Aborting"
            UpdateTestState $ICA_TESTABORTED
            exit 10
        fi
        LogMsg "NTP installed succesfully!"
    fi

    service $srv stop

    # Edit NTP Server config and set the timeservers
    sed -i 's/^server.*/ /g' /etc/ntp.conf
    echo "
    server 0.pool.ntp.org
    server 1.pool.ntp.org
    server 2.pool.ntp.org
    server 3.pool.ntp.org
    " >> /etc/ntp.conf
    if [[ $? -ne 0 ]]; then
        LogMsg "ERROR: Unable to sync RTC clock to system time. Aborting"
        UpdateTestState $ICA_TESTABORTED
        exit 10
    fi

    # set rtc clock to system time
    hwclock --systohc 
    if [[ $? -ne 0 ]]; then
        LogMsg "ERROR: Unable to sync RTC clock to system time. Aborting"
        UpdateTestState $ICA_TESTABORTED
        exit 10
    fi

    # Restart NTP service
    service $srv restart
    if [[ $? -ne 0 ]]; then
        LogMsg "ERROR: Unable to restart ntpd. Aborting"
        UpdateTestState $ICA_TESTABORTED
        exit 10
    fi

else # other distro
    LogMsg "Warning: Distro not suported. Aborting"
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

# Now let's see if the VM is in sync with the NTP server
ntpq -p
if [[ $? -ne 0 ]]; then
    LogMsg "Error: Unable to query NTP deamon!"
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

# Variables for while loop. stopTest is the time until the test will run
isOver=false
secondsToRun=1800
stopTest=$(( $(date +%s) + secondsToRun )) 

while [ $isOver == false ]; do
    # 'ntpq -c rl' returns the offset between the ntp server and internal clock
    delay=$(ntpq -c rl | grep offset= | awk -F "=" '{print $3}' | awk '{print $1}')
    delay=$(echo $delay | sed s'/.$//')

    # Transform from milliseconds to seconds
    delay=$(echo $delay 1000 | awk '{ print $1/$2 }')

    # Using awk for float comparison
    check=$(echo "$delay $maxdelay" | awk '{if ($1 < $2) print 0; else print 1}')

    # Also check if delay is 0.0
    checkzero=$(echo "$delay $zerodelay" | awk '{if ($1 == $2) print 0; else print 1}')

    # Check delay for changes; if it matches the requirements, the loop will end
    if [[ $checkzero -ne 0 ]] && \
       [[ $check -eq 0 ]]; then
        isOver=true
    fi

    # The loop will run for half an hour if delay doesn't match the requirements
    if  [[ $(date +%s) -gt $stopTest ]]; then
        isOver=true
        if [[ $checkzero -eq 0 ]]; then
            # If delay is 0, something is wrong, so we abort.
            LogMsg "ERROR: Delay cannot be 0.000; Please check NTP sync manually."
            UpdateTestState $ICA_TESTABORTED
            exit 10
        elif [[ 0 -ne $check ]] ; then    
            LogMsg "ERROR: NTP Time out of sync. Test Failed"
            LogMsg "NTP offset is $delay seconds."
            UpdateTestState $ICA_TESTFAILED
            exit 10
        fi
    fi
    sleep 1
done

# If we reached this point, time is synced.
LogMsg "Test passed. NTP offset is $delay seconds."

UpdateTestState $ICA_TESTCOMPLETED
exit 0
