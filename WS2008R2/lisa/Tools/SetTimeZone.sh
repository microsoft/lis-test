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
set -x

EXPECTED_ARGS=1

if [ $# -ne $EXPECTED_ARGS ]
then
  echo "Not enough args. Usage: $0 TZONE"
  echo "Aborting."
  exit 1
fi

TZONE=${1} # Timezone to be used
ActualTimezone="None set!"

LinuxRelease()
{
    DISTRO=$(grep -ihs "buntu\|Suse\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux" /etc/{issue,*release,*version})

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


case $(LinuxRelease) in
    "DEBIAN" | "UBUNTU")
    sed -i 's#^Zone.*# Zone="$TZONE" #g' /etc/timezone
    sts=$?      
        if [ 0 -ne ${sts} ]; then
            echo "Unable to sed Zone: ${sts}"
            echo "Aborting."
            exit 1
        fi
    sed -i 's/^UTC.*/ UTC=False /g' /etc/timezone
    sts=$?      
        if [ 0 -ne ${sts} ]; then
            echo "Unable to sed UTC: ${sts}"
            echo "Aborting."
            exit 1
        fi
    # delete old localtime 
    rm -f /etc/localtime
    #Create soft link.
    ln -s /usr/share/zoneinfo/"$TZONE" /etc/localtime
    sts=$?      
        if [ 0 -ne ${sts} ]; then
            echo "Unable to softlink: ${sts}"
            echo "Aborting."
            exit 1
        fi
    ActualTimezone=$(cat /etc/timezone)
        ;;
    "CENTOS" | "SLES" | "RHEL")
    sed -i 's#^Zone.*# Zone="$TZONE" #g' /etc/sysconfig/clock
    sts=$?      
        if [ 0 -ne ${sts} ]; then
            echo "Unable to sed Zone: ${sts}"
            echo "Aborting."
            exit 1
        fi
    sed -i 's/^UTC.*/ UTC=False /g' /etc/sysconfig/clock
    sts=$?      
        if [ 0 -ne ${sts} ]; then
            echo "Unable to sed UTC: ${sts}"
            echo "Aborting test."
            exit 1
        fi

    
    rm -f /etc/localtime # delete old localtime 
    
    ln -s /usr/share/zoneinfo/"$TZONE" /etc/localtime # Create soft link.
    sts=$?      
        if [ 0 -ne ${sts} ]; then
            echo "Unable to softlink: ${sts}"
            echo "Aborting test."
            exit 1
        fi
    ActualTimezone=$(cat /etc/sysconfig/clock)
    ;;
    *)
    echo "Distro not supported, test aborted"
    exit 1
    ;; 
esac

echo "Timezone set to $ActualTimezone" 
exit 0