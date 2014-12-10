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

ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
PASS="0"
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

#
# Convert any .sh files to Unix format
#
dbgprint 1 "Converting the files in the ica director to unix EOL"
dos2unix ica/*


# Source the ICA config file
if [ -e $HOME/ica/config ]; then
	. $HOME/ica/config
else
	echo "ERROR: Unable to source the Automation Framework config file."
	UpdateTestState $ICA_TESTABORTED
	exit 1
fi

### Display info on the Hyper-V modules that are loaded ###
echo -ne "#### Status of Hyper-V Kernel Modules ####\n\n"

for module in ${HYPERV_MODULES[@]}; do
	echo -e "Module:\t\t$module"
	
	load_status=$( lsmod | grep $module 2>&1)
	
	# load_status=$(modinfo $module 2>&1)
	# Check to see if the module is loaded.  It is if module name 
	# contained in the output.
	if [[ $load_status =~ $module ]]; then
		echo -e "Status:\t\tloaded"
		echo "$load_status"
		UpdateSummary " $module : Success"

		
	else
		echo -e "ERROR: Status: module '$module' is not loaded"
#		UpdateTestState $ICA_TESTABORTED
#		exit $E_HYPERVIC_MODULE_NOT_LOADED
		PASS="1"
			UpdateSummary " $module : Failed"
	fi
	echo -ne "\n\n"
done

# The benchmark tests in the 'benchmark-tests' folder need to be
# fixed/modified.  They take way to long to run during the Hyper-V automation
# testing.



#
# Let the caller know everything worked
#
if [ "1" -eq "$PASS" ] ; then
	
	dbgprint 1 "Exiting with state: TestAborted."
	UpdateTestState $ICA_TESTABORTED
else 
	dbgprint 1 "Exiting with state: TestCompleted."
	UpdateTestState $ICA_TESTCOMPLETED
fi


# Delete summary log 

exit 0
