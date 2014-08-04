#!/bin/bash

################################################################
# 
# KVP_BasicTest.sh
# This script will verify that the KVP daemon is started at the boot of the VM. 
# This script will install and run the KVP client tool to verify that the KVP
# pools are created and accessible.
# Make sure we have kvptool.tar.gz file in Automation\..\lisa\Tools folder 
# 
################################################################
ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error while performing the test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

cd ~

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}
if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

# Source the constants file
if [ -e ~/${CONSTANTS_FILE} ]; then
    source ~/${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    echo $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi


#
# Make sure constants.sh contains the variables we expect
#
if [ "${TC_COVERED:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter TC_COVERED is not defined in ${CONSTANTS_FILE}"
    echo $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

#
# Echo TCs we cover
#
echo "Covers ${TC_COVERED}" > ~/summary.log

#
# Verify that the KVP Daemon is running
#
pgrep -lf "hypervkvpd|hv_kvp_daemon"
if [ $? -ne 0 ]; then
	LogMsg "KVP Daemon is not running by default"
	echo "KVP daemon not running, basic test: Failed" >> ~/summary.log
	UpdateTestState $ICA_TESTFAILED
	exit 10
fi	
LogMsg "KVP Daemon is started on boot and it is running"

#
# Extract and install the KVP client tool.
#
mkdir kvptool
tar -xvf kvp*.gz -C kvptool
if [ $? -ne 0 ]; then
	LogMsg "Failed to extract the KVP tool tar file"
	echo "Installing KVP tool: Failed" >> ~/summary.log
	UpdateTestState $ICA_TESTFAILED
	exit 10
fi
gcc -o kvptool/kvp_client kvptool/kvp_client.c
mv ~/kvptool/kvp_client ~/
chmod 755 ~/kvp_client

#
# Run the KVP client tool and verify that the data pools are created and accessible
#
poolcount="`~/kvp_client | grep Pool | wc -l`"
if [ $poolcount -ne 5 ]; then
	LogMsg "pools are not created properly"
	echo "Pools are not listed properly, KVP Basic test: Failed" >> ~/summary.log
	UpdateTestState $ICA_TESTFAILED
	exit 10
fi
LogMsg "Verified that the 0-4 all the 5 data pools are listed properly"  
echo "KVP Daemon is running and data pools are listed -KVP Basic test : Passed" >>  ~/summary.log
LogMsg "Updating test case state to completed"
UpdateTestState $ICA_TESTCOMPLETED
exit 0
