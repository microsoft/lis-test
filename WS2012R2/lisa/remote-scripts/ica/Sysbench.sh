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
#       This script installs and runs Sysbench Test on a guest VM
#
#       Steps:
#       1. Installs dependencies
#       2. Compiles and installs sysbench
#       3. Runs sysbench
#       4. Collects results
#
#       No optional parameters needed
#
########################################################################
ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error while performing the test
NO_THREAD="1"                     # Number of threads for testing
CPU="cpu"                         # Test name
TEST_FILE="seqwr"                 # Test file type

CONSTANTS_FILE="constants.sh"

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
# Updates the summary.log file
#######################################################################
function UpdateSummary()
{
    echo $1 >> ~/summary.log
}

#######################################################################
# Keeps track of the state of the test
#######################################################################
function UpdateTestState()
{
    echo $1 > ~/state.txt
}

LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi
#######################################################################
#
# Main script body
#
#######################################################################
ROOT_DIR="/root"
pushd $ROOT_DIR
LogMsg "Cloning sysbench"
git clone https://github.com/akopytov/sysbench.git
if [ $? -gt 0 ]; then
    LogMsg "Failed to cloning sysbench."
    UpdateSummary "Compiling sysbench failed."
    UpdateTestState $ICA_TESTFAILED
    exit 10
fi
pushd "$ROOT_DIR/sysbench"
# Create the state.txt file so LISA knows we are running
UpdateTestState $ICA_TESTRUNNING

# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi
LogMsg "This script tests sysbench on VM."

if is_fedora ; then
    # Installing dependencies of sysbench on fedora.
     yum install -y mysql-devel
    if [ $? -eq 0 ]; then
        LogMsg "Dependecies are installed ..."
        bash ./autogen.sh
        bash ./configure
        make
        make install
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Unable to install sysbench. Aborting..."
            UpdateTestState $ICA_TESTABORTED
            exit 10
        fi
        LogMsg "Sysbench installed successfully."
    fi
 elif is_ubuntu ; then
     # Installing sysbench on ubuntu
     apt-get install -y sysbench
    if [ $? -ne 0 ]; then
             LogMsg "ERROR: Unable to install sysbench. Aborting..."
             UpdateTestState $ICA_TESTABORTED
             exit 10
    fi
        LogMsg "Sysbench installed successfully!"

 elif is_suse ; then
    LogMsg "Dependecies are installed ..."
        bash ./autogen.sh
        bash ./configure --without-mysql
        make
        make install
        if [ $? -ne 0 ]; then
            LogMsg "ERROR: Unable to install sysbench. Aborting..."
            UpdateTestState $ICA_TESTABORTED
            exit 10
        fi
        LogMsg "Sysbench installed successfully."
    fi
 #else # other distro's
  #   LogMsg "Distro not suported. Aborting"
  #   UpdateTestState $ICA_TESTABORTED
  #   exit 10
# fi

 CPU_PASS=-1
 FILEIO_PASS=-1
  function cputest ()
{
    LogMsg "Creating cpu.log."
    sysbench --test=cpu --num-threads=1 run > /root/cpu.log
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Unable to exectute sysbench CPU. Aborting..."
        UpdateTestState $ICA_TESTABORTED
    fi
        PASS_VALUE_CPU=`cat /root/cpu.log |awk '/approx./ {print $2;}'`
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Cannot find cpu.log."
        UpdateTestState $ICA_TESTABORTED
    fi
        RESULT_VALUE=$((PASS_VALUE_CPU+0))
    if  [ $RESULT_VALUE -gt 80 ]; then
         CPU_PASS=0
        LogMsg "CPU Test passed. "
        UpdateTestState $ICA_TESTCOMPLETED

    fi
   return "$CPU_PASS"
}
cputest
LogMsg "CputestPAss= $CPU_PASS"

function fileio ()
 {
    LogMsg " Testing fileio. Creating fileio.log."
    sysbench --test=fileio --num-threads=1 --file-test-mode=seqwr run > /root/fileio.log
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Unable to exectute sysbench fileio. Aborting..."
        UpdateTestState $ICA_TESTFAILED
    fi
        PASS_VALUE_FILEIO=`cat /root/fileio.log |awk '/approx./ {print $2;}'`
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Cannot find fileio.log."
        UpdateTestState $ICA_TESTFAILED
    fi
        RESULT_VALUE_FILEIO=$((PASS_VALUE_FILEIO+0))
    if  [ $RESULT_VALUE_FILEIO -gt 80 ]; then
        FILEIO_PASS=0
        LogMsg "Fileio Test passed. "
        UpdateTestState $ICA_TESTCOMPLETED

    fi
    return "$FILEIO_PASS"
 }

fileio
LogMsg "FILE PASS= $FILEIO_PASS"

if [ "$FILEIO_PASS" = "$CPU_PASS" ]; then
    LogMsg "Test succesfully."
    UpdateTestState $ICA_TESTCOMPLETED
else
    LogMsg "Test Failed."
    UpdateTestState $ICA_TESTFAILED
fi
