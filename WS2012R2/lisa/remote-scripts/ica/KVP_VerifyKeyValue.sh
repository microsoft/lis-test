#!/bin/bash
#
# VerifyKeyValue.sh
#
# This script will verify a key is present in the speicified pool or not. 
# The Parameters provided are - Test case number, Key Name. Value, Pool number
# This test should be run after the KVP Basic test.
#
#############################################################


ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error while performing the test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}


UpdateTestState()
{
    echo $1 > ~/state.txt
}

#
# Create the state.txt file so ICA knows we are running
#
LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING



#
# Delete any summary.log files from a previous run
#
rm -f ~/summary.log
touch ~/summary.log

#
# Source the constants.sh file to pickup definitions from
# the ICA automation
#
if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

#
# Make sure constants.sh contains the variables we expect
#
if [ "${TC_COVERED:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter TC_COVERED is not defined in ${CONSTANTS_FILE}"
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

if [ "${Key:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter Key is not defined in ${CONSTANTS_FILE}"
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

if [ "${Value:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter Value is not defined in ${CONSTANTS_FILE}"
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 40
fi

if [ "${Pool:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter Pool number is not defined in ${CONSTANTS_FILE}"
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 50
fi

#
# Echo TCs we cover
#
echo "Covers ${TC_COVERED}" > ~/summary.log

#
# Make sure we have the kvp_client tool
#
if [ ! -e ~/kvp_client ]; then
    msg="Error: kvp_client tool is not on the system"
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 60
fi

chmod 755 ~/kvp_client

#
# verify that the Key Value is present in the specified pool or not.
#
~/kvp_client $Pool | grep "${Key}; Value: ${Value}"
if [ $? -ne 0 ]; then
        msg="Error: the KVP item is not in the pool"
	LogMsg "$msg"
	echo "$msg" >> ~/summary.log
	UpdateTestState $ICA_TESTFAILED
	exit 70
fi

LogMsg "Updating test case state to completed"
UpdateTestState $ICA_TESTCOMPLETED

exit 0
