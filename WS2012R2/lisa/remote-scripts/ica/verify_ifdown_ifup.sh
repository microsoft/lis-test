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

NetInterface="eth0"
REMOTE_SERVER="8.8.4.4"
LoopCount=10
TestCount=0

PingCheck() {
    if ! ping "$REMOTE_SERVER" -c 4; then
        # On Azure ping is disabled so we need another test method
        if ! wget google.com; then
            msg = "Error: ${NetInterface} ping and wget failed on try ${1}."
            LogMsg "$msg" && UpdateSummary "$msg"
            SetTestStateFailed
            exit 1
        fi
    else
        LogMsg "Ping ${NetInterface}: Passed on try ${1}"
    fi
}

ChangeInterfaceState() {
    if ! ip link set dev "$NetInterface" "$1"; then
        msg="Error: Bringing interface ${1} ${NetInterface} failed"
        LogMsg "$msg" && UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    else
        LogMsg "Interface ${NetInterface} was put ${1}"
    fi
    sleep 5
}

ReloadNetvsc() {
    if ! modprobe $1 hv_netvsc; then
        msg="modprobe ${1} hv_netvsc : Failed"
        LogMsg "$msg" && UpdateSummary "$msg"
        SetTestStateFailed
        exit 1
    else
        sleep 1
        LogMsg "modprobe ${1} hv_netvsc : Passed"
    fi
}

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 1
}
# Source constants file and initialize most common variables
UtilsInit

### Main script ###

# Check for call traces during test run
dos2unix check_traces.sh && chmod +x check_traces.sh
./check_traces.sh &

while [ "$TestCount" -lt "$LoopCount" ]
do
    TestCount=$((TestCount+1))
    LogMsg "Test Iteration : $TestCount"

    # Unload hv_netvsc
    ReloadNetvsc "-r"

    # Load hv_netvsc
    ReloadNetvsc
done
UpdateSummary "Successful hv_netvsc reload."

# Clean all dhclient processes, get IP & try ping
LoopCount=4
TestCount=1
ChangeInterfaceState "up"
kill "$(pidof dhclient)"
dhclient -r && dhclient
sleep 15
PingCheck $TestCount

while [ "$TestCount" -lt "$LoopCount" ]
do
    TestCount=$((TestCount+1))
    LogMsg "Test Iteration : ${TestCount}"
    ChangeInterfaceState "down"
    ChangeInterfaceState "up"
    kill "$(pidof dhclient)"
    dhclient -r && dhclient
    sleep 15
    PingCheck "$TestCount"
done
UpdateSummary "Successful interface restart and ping check."

LogMsg "#########################################################"
LogMsg "Result : Test Completed Successfully"
SetTestStateCompleted
