#!bin/bash
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
# SCRIPT DESCRIPTION: This script will run ltp_client.sh and after
# all setups it will run the tests mentioned in LTP_net.xml.
#
# NOTES: On Ubuntu: - rpc test will fail on rup testcase because 
# the version of rup existent does not have the options called
# in rup01 script; rpc01 testcase may fail but if you run in again will PASS.
#                   - multicast test will fail on mc_commo testcase
#                   - tcp test will fail on sendfile01 testcase
# because of automation and xinetd01 testcase because of ipv6 address.
# If any other test fails, run it manually, it might work.
################################################################

ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` ": ${1}"
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}


#######################################################################
#
# Main script body
#
#######################################################################

cd ~
UpdateTestState $ICA_TESTRUNNING
LogMsg "Starting test"

#
# Delete any old steps.log file
#
LogMsg "Cleaning up old steps.log"
if [ -e ~/steps.log ]; then
    rm -f ~/steps.log
fi

touch ~/steps.log

dos2unix utils.sh

echo "Changing permisions for needed files" >> steps.log
chmod +x utils.sh
chmod +x ltp_client.sh
chmod +x rsh_config.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}


# Source constants file and initialize most common variables
echo "Source constants..."
UtilsInit

chmod +x constants.sh
./constants.sh

echo "Running ltp on client" >> steps.log
./ltp_client.sh $LTP_SERVER_IP $SERVER_PASSWORD $SERVER_USERNAME $CLIENT_PASSWORD $SSH_PRIVATE_KEY

echo "Starting Tests..." >> steps.log
for test in ${TESTS[@]}; do
    case "$test" in
        n | nfs )
            /opt/ltp/testscripts/networktests.sh -n > nfs.log
            msg=$(tail -1 nfs.log)
            test="nfs: "
            msg=$test$msg
            UpdateSummary "$msg"
                        ;;
        r | rpc )
            /opt/ltp/testscripts/networktests.sh -r > rpc.log
            msg=$(tail -1 rpc.log)
            test="rpc: "
            msg=$test$msg
            UpdateSummary "$msg"
                        ;;
                   
        m | multicast )
            /opt/ltp/testscripts/networktests.sh -m > multicast.log
            msg=$(tail -1 multicast.log)
            test="multicast: "
            msg=$test$msg
            UpdateSummary "$msg"
                        ;;
        t | tcp )
            /opt/ltp/testscripts/networktests.sh -t > tcp.log
            msg=$(tail -1 tcp.log)
            test="tcp: "
            msg=$test$msg
            UpdateSummary "$msg"
                        ;;
        s | sctp )
            /opt/ltp/testscripts/networktests.sh -s > sctp.log
            msg=$(tail -1 sctp.log)
            test="sctp: "
            msg=$test$msg
            UpdateSummary "$msg"
                        ;;
        esac
   
done

UpdateSummary "LTP Network Tests ended"
LogMsg "Result: Test Completed"
UpdateTestState "TestCompleted"