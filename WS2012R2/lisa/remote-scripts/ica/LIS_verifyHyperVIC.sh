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


LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

# adding check for summary.log
if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

#
# Create the state.txt file so the ICA script knows
# we are running
#
UpdateTestState $ICA_TESTRUNNING

if [ -e $HOME/constants.sh ]; then
	. $HOME/constants.sh
else
	LogMsg "ERROR: Unable to source the constants file."
	UpdateTestState "TestAborted"
	exit 1
fi

#Check for Testcase count
if [ ! ${TC_COVERED} ]; then
    LogMsg "The TC_COVERED variable is not defined."
	echo "The TC_COVERED variable is not defined." >> ~/summary.log
    LogMsg "Terminating the test."
    UpdateTestState "TestAborted"
    exit 1
fi

echo "Covers : ${TC_COVERED}" >> ~/summary.log

### Display info on the Hyper-V modules that are loaded ###
LogMsg "#### Status of Hyper-V Kernel Modules ####\n"

for module in ${HYPERV_MODULES[@]}; do
	LogMsg "Module: $module"
	module_alt=`echo $module|sed -n s/-/_/p`
	load_status=$( lsmod | grep $module 2>&1)
        module_name=$module
	if [ "$module_alt" != "" ]; then
		# Some of our drivers, such as hid-hyperv.ko, is shown as
		# "hid_hyperv" from lsmod output. We have to replace all
		# "-" to "_".
		load_status=$( lsmod | grep $module_alt 2>&1)
		module_name=$module_alt
	fi
	
	# load_status=$(modinfo $module 2>&1)
	# Check to see if the module is loaded.  It is if module name 
	# contained in the output.
	if [[ $load_status =~ $module_name ]]; then
		LogMsg "Status: loaded"
		LogMsg "$load_status"
		echo  " $module : Success" >> ~/summary.log
	else
		LogMsg "ERROR: Status: module '$module' is not loaded"
#		UpdateTestState $ICA_TESTABORTED
#		exit $E_HYPERVIC_MODULE_NOT_LOADED
		PASS="1"
		echo  " $module : Failed" >> ~/summary.log
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
	
	LogMsg "Exiting with state: TestAborted."
	UpdateTestState $ICA_TESTABORTED
else 
	LogMsg "Exiting with state: TestCompleted."
	UpdateTestState $ICA_TESTCOMPLETED
fi
