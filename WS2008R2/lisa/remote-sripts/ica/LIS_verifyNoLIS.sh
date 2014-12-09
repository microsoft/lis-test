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

# This test verifies the LIS modules not installed

ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"


DEBUG_LEVEL=3


dbgprint()
{
    if [ $1 -le $DEBUG_LEVEL ]; then
        echo "$2"
    fi
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

UpdateSummary()
{
    echo $1 >> ~/summary.log
}

# adding check for summary.log
if [ -e ~/summary.log ]; then
    dbgprint 1 "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

#
# Create the state.txt file so the ICA script knows
# we are running
#
UpdateTestState $ICA_TESTRUNNING

# Source the ICA constants file
if [ -e $HOME/constants.sh ]; then
	. $HOME/constants.sh
else
	dbgprint 0 "ERROR: Unable to source  constants file."
	UpdateTestState $ICA_TESTABORTED
	exit 1
fi

if [ ! ${TC_COUNT} ]; then
    dbgprint 0 "The TC_COUNT variable is not defined."
    dbgprint 0 "Aborting the test."
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi


UpdateSummary "Covers ${TC_COUNT}"



### Display info on the Hyper-V modules that are loaded ###
echo -ne "#### Status of Hyper-V Kernel Modules ####\n\n"

for module in ${HYPERV_MODULES[@]}; do
	dbgprint 0  "Module:$module"
	
	load_status=$( lsmod | grep $module 2>&1)
	
	# load_status=$(modinfo $module 2>&1)
	# Check to see if the module is loaded.  It is if module name 
	# contained in the output.
	if [[ $load_status =~ $module ]]; then
		dbgprint 0 "Status: module '$module' is loaded"
		dbgprint 0 "$load_status"
		UpdateSummary "$module should not load : Failed"
		UpdateTestState $ICA_TESTFAILED
        exit 1
		
	else
		dbgprint 0 "Status: module '$module' is not loaded"
		UpdateSummary "$module should not load: Success"
	fi
	echo -ne "\n\n"
done

#
# Let the caller know everything worked
#

	dbgprint 1 "Exiting with state: TestCompleted."
	UpdateTestState $ICA_TESTCOMPLETED



exit 0
