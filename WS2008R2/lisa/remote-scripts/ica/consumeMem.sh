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

# Usage:  ./consumeMem.sh percentage timeout
#
#  percentage is a number between 1 and 99
#  timeout is a number between 1 and 600

if [ $# -ne 2 ]; then
    echo "Usage: ./consumeMem.sh percentage timeout"
    exit 1
fi

#
# Make sure the percentage is with in limits
#
percent=$1
if [ $percent -lt 1 ]; then
    echo "Percent must be greater than 0"
    exit 10
fi

if [ $percent -gt 99 ]; then
    echo  "Percent must be less than 100"
    exit 20
fi

#
# Make sure the timeout is within limits
#
timeout=$2
if [ $timeout -lt 1 ]; then
    echo "Tiemout must be greater than 0"
    exit 30
fi

if [ $timeout -gt 600 ]; then
    echo "Timeout must be <= 600 (10 minutes)"
    exit 40
fi

#
# Use /proc/meminfo to get the MemFree value
#
fMem=`cat /proc/meminfo | grep MemFree`
freeMem=`echo $fMem | cut -f 2 -d ' '`

#
# Convert from KB to bytes
#
freeMem=$((freeMem * 1024))

#
# Compute the requested percentage of free memory
#
mem=`echo "$freeMem * 0.${percent}" | bc`

#
# Convert to MB
#
mem=`echo "$mem / 1048576" | bc`
mem=`echo $mem | cut -f 1 -d '.'`
#echo "Mem = $mem"

#
# Add the stress
#
echo "stressapptest -M $mem -s $timeout"
stressapptest -M $mem -s $timeout

exit 0
