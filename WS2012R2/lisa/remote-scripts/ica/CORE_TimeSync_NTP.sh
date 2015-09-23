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
#         </test>
#
########################################################################

ICA_TESTRUNNING="TestRunning"       # The test is running
ICA_TESTCOMPLETED="TestCompleted"   # The test completed successfully
ICA_TESTABORTED="TestAborted"       # Error during setup of test
ICA_TESTFAILED="TestFailed"         # Error while performing the test
maxdelay=5.0                        # max offset in seconds.
zerodelay=0.0                       # zero
declare os_VENDOR os_RELEASE os_UPDATE os_PACKAGE os_CODENAME

########################################################################
# Determine what OS is running
########################################################################
# GetOSVersion
function GetOSVersion {

    # Figure out which vendor we are
    if [[ -x "`which sw_vers 2>/dev/null`" ]]; then
        # OS/X
        os_VENDOR=`sw_vers -productName`
        os_RELEASE=`sw_vers -productVersion`
        os_UPDATE=${os_RELEASE##*.}
        os_RELEASE=${os_RELEASE%.*}
        os_PACKAGE=""
        if [[ "$os_RELEASE" =~ "10.7" ]]; then
            os_CODENAME="lion"
        elif [[ "$os_RELEASE" =~ "10.6" ]]; then
            os_CODENAME="snow leopard"
        elif [[ "$os_RELEASE" =~ "10.5" ]]; then
            os_CODENAME="leopard"
        elif [[ "$os_RELEASE" =~ "10.4" ]]; then
            os_CODENAME="tiger"
        elif [[ "$os_RELEASE" =~ "10.3" ]]; then
            os_CODENAME="panther"
        else
            os_CODENAME=""
        fi
    elif [[ -x $(which lsb_release 2>/dev/null) ]]; then
        os_VENDOR=$(lsb_release -i -s)
        os_RELEASE=$(lsb_release -r -s)
        os_UPDATE=""
        os_PACKAGE="rpm"
        if [[ "Debian,Ubuntu,LinuxMint" =~ $os_VENDOR ]]; then
            os_PACKAGE="deb"
        elif [[ "SUSE LINUX" =~ $os_VENDOR ]]; then
            lsb_release -d -s | grep -q openSUSE
            if [[ $? -eq 0 ]]; then
                os_VENDOR="openSUSE"
            fi
        elif [[ $os_VENDOR == "openSUSE project" ]]; then
            os_VENDOR="openSUSE"
        elif [[ $os_VENDOR =~ Red.*Hat ]]; then
            os_VENDOR="Red Hat"
        fi
        os_CODENAME=$(lsb_release -c -s)
    elif [[ -r /etc/redhat-release ]]; then
        # Red Hat Enterprise Linux Server release 5.5 (Tikanga)
        # Red Hat Enterprise Linux Server release 7.0 Beta (Maipo)
        # CentOS release 5.5 (Final)
        # CentOS Linux release 6.0 (Final)
        # Fedora release 16 (Verne)
        # XenServer release 6.2.0-70446c (xenenterprise)
        os_CODENAME=""
        for r in "Red Hat" CentOS Fedora XenServer; do
            os_VENDOR=$r
            if [[ -n "`grep \"$r\" /etc/redhat-release`" ]]; then
                ver=`sed -e 's/^.* \([0-9].*\) (\(.*\)).*$/\1\|\2/' /etc/redhat-release`
                os_CODENAME=${ver#*|}
                os_RELEASE=${ver%|*}
                os_UPDATE=${os_RELEASE##*.}
                os_RELEASE=${os_RELEASE%.*}
                break
            fi
            os_VENDOR=""
        done
        os_PACKAGE="rpm"
    elif [[ -r /etc/SuSE-release ]]; then
        for r in openSUSE "SUSE Linux"; do
            if [[ "$r" = "SUSE Linux" ]]; then
                os_VENDOR="SUSE LINUX"
            else
                os_VENDOR=$r
            fi

            if [[ -n "`grep \"$r\" /etc/SuSE-release`" ]]; then
                os_CODENAME=`grep "CODENAME = " /etc/SuSE-release | sed 's:.* = ::g'`
                os_RELEASE=`grep "VERSION = " /etc/SuSE-release | sed 's:.* = ::g'`
                os_UPDATE=`grep "PATCHLEVEL = " /etc/SuSE-release | sed 's:.* = ::g'`
                break
            fi
            os_VENDOR=""
        done
        os_PACKAGE="rpm"
    # If lsb_release is not installed, we should be able to detect Debian OS
    elif [[ -f /etc/debian_version ]] && [[ $(cat /proc/version) =~ "Debian" ]]; then
        os_VENDOR="Debian"
        os_PACKAGE="deb"
        os_CODENAME=$(awk '/VERSION=/' /etc/os-release | sed 's/VERSION=//' | sed -r 's/\"|\(|\)//g' | awk '{print $2}')
        os_RELEASE=$(awk '/VERSION_ID=/' /etc/os-release | sed 's/VERSION_ID=//' | sed 's/\"//g')
    fi
    export os_VENDOR os_RELEASE os_UPDATE os_PACKAGE os_CODENAME
}

########################################################################
# Determine if current distribution is a Fedora-based distribution
########################################################################
function is_fedora {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "Fedora" ] || [ "$os_VENDOR" = "Red Hat" ] || \
        [ "$os_VENDOR" = "CentOS" ] || [ "$os_VENDOR" = "OracleServer" ]
}

########################################################################
# Determine if current distribution is a SUSE-based distribution
########################################################################
function is_suse {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "openSUSE" ] || [ "$os_VENDOR" = "SUSE LINUX" ]
}

########################################################################
# Determine if current distribution is an Ubuntu-based distribution
########################################################################
function is_ubuntu {
    if [[ -z "$os_PACKAGE" ]]; then
        GetOSVersion
    fi
    [ "$os_PACKAGE" = "deb" ]
}

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

LogMsg "This script tests NTP time syncronization"

# Try to restart NTP. If it fails we try to install it.
# We check this distro specific.
if is_fedora ; then
    # Check if ntpd is running.
    service ntpd restart
    if [[ $? -ne 0 ]]; then
        echo "NTPD not installed. Trying to install ..."
        yum install -y ntp ntpdate ntp-doc
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
        echo "NTPD installed succesfully!"
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
        LogMsg "NTP is not installed. Trying to install ..."
        apt-get install ntp -y
        if [[ $? -ne 0 ]] ; then
            LogMsg "ERROR: Unable to install ntp. Aborting"
            UpdateTestState $ICA_TESTABORTED
            exit 10
        fi
        LogMsg "NTP installed succesfully!"
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
    service ntpd restart
    if [[ $? -ne 0 ]]; then
        LogMsg "NTP is not installed. Trying to install ..."
        zypper install ntp -y
        if [[ $? -ne 0 ]] ; then
            LogMsg "ERROR: Unable to install ntp. Aborting"
            UpdateTestState $ICA_TESTABORTED
            exit 10
        fi
        LogMsg "NTP installed succesfully!"
    fi

    service ntpd stop

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
    service ntpd restart
    if [[ $? -ne 0 ]]; then
        LogMsg "ERROR: Unable to restart ntpd. Aborting"
        UpdateTestState $ICA_TESTABORTED
        exit 10
    fi

else # other distro
    LogMsg "Distro not suported. Aborting"
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

# Now let's see if the VM is in sync with ntp server
ntpq -p
if [[ $? -ne 0 ]]; then
    LogMsg "Unable to query NTP deamon!"
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

# Variables for while loop. stopTest is the time until the test will run
isOver=false
secondsToRun=1800
stopTest=$(( $(date +%s) + secondsToRun )) 

while [ $isOver == false ]; do
    # loopinfo returns the offset between the ntp server and internal clock
    delay=$(ntpdc -c loopinfo | awk 'NR==1 {print $2}')

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
done

# If we reached this point, time is synced.
LogMsg "NTP offset is $delay seconds."
LogMsg "SUCCESS: NTP time synced!"

UpdateTestState $ICA_TESTCOMPLETED
exit 0
