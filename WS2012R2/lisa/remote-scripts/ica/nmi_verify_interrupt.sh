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
# nmi_verify_interrupt.sh
# Description:
#	This script was created to automate the testing of a Linux
#	Integration services. This script will verify if a NMI sent
#	from Hyper-V is received  inside the Linux VM, by checking the
#	/proc/interrupts file.
#	The test performs the following steps:
#	 1. Make sure we have a constants.sh file.
#	 2. Looks for the NMI property of each CPU.
#	 3. For 2012R2, verifies if each CPU has received a NMI.
#  4. For 2016, verifies only cpu0 has received a NMI.
#
#	 To pass test parameters into test cases, the host will create
#	 a file named constants.sh.  This file contains one or more
#	 variable definition.
#
################################################################

dos2unix utils.sh
# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 1
}

# Source constants file and initialize most common variables
UtilsInit

#
# Getting the CPUs NMI property count
#
cpu_count=$(grep CPU -o /proc/interrupts | wc -l)

LogMsg "${cpu_count} CPUs found"
echo "${cpu_count} CPUs found" >> ~/summary.log
#
# Check host version:
# Prior to WS2016 the NMI is injected to all CPUs of the guest and
# WS1026 injects it to CPU0 only.
#
while read line
do
    if [[ $line = *NMI* ]]; then
        for ((  i=0 ;  i<=$cpu_count-1;  i++ ))
        do
            nmiCount=`echo $line | cut -f $(( $i+2 )) -d ' '`
            LogMsg "CPU ${i} interrupt count = ${nmiCount}"

            # CPU0 or 2012R2(14393 > BuildNumber >= 9600) all CPUs should receive NMI
            if [ $i -eq 0 ] || ([ $BuildNumber -lt 14393 ] && [ $BuildNumber -ge 9600 ]); then
                if [ $nmiCount -ne 0 ]; then
                    LogMsg "Info: NMI received at CPU ${i}"
                    echo "Info: NMI received at CPU ${i}" >> ~/summary.log
                else
                    LogMsg "Error: CPU {$i} did not receive a NMI!"
                    echo "Error: CPU {$i} did not receive a NMI!" >> ~/summary.log
                    SetTestStateFailed
                    exit 10
                fi
            # only not CPU0 and 2016 (BuildNumber >= 14393) should not receive NMI
            elif [ $BuildNumber -ge 14393 ]; then
                if [ $nmiCount -eq 0 ]; then
                    LogMsg "Info: CPU {$i} did not receive a NMI, this is expected"
                    echo "Info: CPU {$i} did not receive a NMI, this is expected" >> ~/summary.log
                else
                    LogMsg "Error: CPU {$i} received a NMI!"
                    echo "Error: CPU {$i} received a NMI!" >> ~/summary.log
                    SetTestStateFailed
                    exit 10
                fi
            # lower than 9600, return skipped
            else
                SetTestStateSkipped
            fi

        done
    fi
done < "/proc/interrupts"

LogMsg "Test completed successfully"
SetTestStateCompleted
exit 0
