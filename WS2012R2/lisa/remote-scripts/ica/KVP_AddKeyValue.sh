#!/bin/bash
#
# KVP_AddKeyValue.sh
# 
# This script will add a key value to the specified pool. 
# Parameters to be passed are - Test case number, Key Name, Value, Pool Number 
# This test should be run after the KVP Basic test, which will install the KVP client tool.
#
#############################################################


ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

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
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

#
# Make sure constants.sh contains the variables we expect
#
if [ "${TC_COVERED:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter TC_COVERED is not defined in ${CONSTANTS_FILE}"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi
if [ "${Key:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter Key is not defined in ${CONSTANTS_FILE}"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi
if [ "${Value:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter Value is not defined in ${CONSTANTS_FILE}"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi
if [ "${Pool:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter Pool number is not defined in ${CONSTANTS_FILE}"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi
#
# Echo TCs we cover
#
echo "Covers ${TC_COVERED}" > ~/summary.log
	
	
#
# Add tbe Key Value to the Pool.
#

./kvp_client append $Pool $Key $Value

./kvp_client $Pool | grep $Key
if [ $? -ne 0 ]; then
LogMsg "Key Value pair is not added successfully to the Pool"
echo "Adding key Value to the Pool: Failed" >> ~/summary.log
UpdateTestState $ICA_TESTFAILED
exit 10
fi

echo "The Key value pair is added to the Pool:${Pool} successfully" >> ~/summary.log
LogMsg "Updating test case state to completed"
UpdateTestState $ICA_TESTCOMPLETED
exit 0
