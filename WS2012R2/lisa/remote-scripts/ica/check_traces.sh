#!/bin/bash
#####################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
#####################################################################
#
# Description:
# This script checks if "Call Trace" message or hot add errors
# appear in the system logs.
# It should be called to run in background for the entire duration
# of a test run.
#
#####################################################################

# Initializing variables
summary_log=$1
errorHasOccured=0
callTraceHasOccured=0
[[ -f "/var/log/syslog" ]] && logfile="/var/log/syslog" || logfile="/var/log/messages"
[[ -n $summary_log ]] || summary_log="/root/summary.log"

# Checking logs
while true; do
    # Check for hot add errors in dmesg
    dmesg | grep -q "Memory hot add failed"
    if [[ $? -eq 0 ]] && \
        [[ $errorHasOccured -eq 0 ]]; then
        echo "ERROR: 'Memory hot add failed' message is present in dmesg" >> ~/HotAddErrors.log 2>&1
        errorHasOccured=1
    fi

    # Check for call traces in /var/log
    content=$(grep -i "Call Trace" $logfile)
    if [[ -n $content ]] && \
        [[ $callTraceHasOccured -eq 0 ]]; then
        echo "ERROR: System shows Call Trace in $logfile" >> $summary_log 2>&1
        callTraceHasOccured=1
        break
    fi
    sleep 4
done

exit 0