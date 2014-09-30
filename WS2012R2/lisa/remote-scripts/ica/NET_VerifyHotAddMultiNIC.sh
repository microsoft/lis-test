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


expectedCount=0

#
# AddedNic ($ethCount)
#
function AddedNic
{
    ethCount=$1

    echo "Info : Checking the ethCount"
    if [ $ethCount -ne 2 ]; then
        echo "Error: VM should have two NICs now"
        exit 1
    fi

    #
    # Bring the new NIC online
    #
    echo "Info : Creating ifcfg-eth1"
    cp /etc/sysconfig/network/ifcfg-eth0 /etc/sysconfig/network/ifcfg-eth1

    echo "Info : Bringing up eth1"
    ifup eth1

    #
    # Verify the new NIC received an IP v4 address
    #
    echo "Info : Verify the new NIC has an IPv4 address"
    ifconfig eth1 | grep -s "inet addr:" > /dev/null
    if [ $? -ne 0 ]; then
        echo "Error: eth1 was not assigned an IPv4 address"
        exit 1
    fi

    echo "Info : eth1 is up"
}

#
# RemovedNic ($ethCount)
#
function RemovedNic
{
    ethCount=$1
    if [ $ethCount -ne 1 ]; then
        echo "Error: there are more than one eth devices"
        exit 1
    fi

    rm -f /etc/sysconfig/network/ifcfg-eth1
}


#######################################################################
#
# Main script body
#
#######################################################################

#
# Make sure the argument count is correct
#
if [ $# -ne 1 ]; then
    echo "Error: Expected one argument of 'added' or 'removed'"
    echo "       $# arguments were provided"
    exit 1
fi

#
# Determine how many eth devices the OS sees
#
ethCount=$(ifconfig -a | grep "^eth" | wc -l)
echo "ethCount = ${ethCount}"

#
# Set expectedCount based on the value of $1
#
case "$1" in
added)
    AddedNic $ethCount
    ;;
removed)
    RemovedNic $ethCount
    ;;
*)
    echo "Error: Unknow argument of $1"
    exit 1
    ;;
esac

echo "Info : test passed"
exit 0
