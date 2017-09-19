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
fi

echo "This script covers test case: ${TC_COVERED}" >> ~/summary.log

### Display info on the Hyper-V modules that are loaded ###
LogMsg "#### Status of Hyper-V Kernel Modules ####"

#Check if VMBus module exist and if exist continue checking the other modules
hv_string=$(dmesg | grep "Vmbus version:")
if [[ ( $hv_string == "" ) || !( $hv_string == *"hv_vmbus:"*"Vmbus version:"* ) ]]; then
    LogMsg "Error! Could not find the VMBus protocol string in dmesg."
	echo "Error! Could not find the VMBus protocol string in dmesg." >> ~/summary.log
	LogMsg "Exiting with state: TestAborted."
	UpdateTestState $ICA_TESTABORTED
	exit 1
fi
# Check to see if each module is loaded.
for module in ${HYPERV_MODULES[@]}; do
    LogMsg "Module: $module"
	load_module=$(dmesg | grep "hv_vmbus: registering driver $module")
	if [[ $load_module == "" ]];then
		echo LogMsg "ERROR: Status: $module is not loaded"
	    PASS="1"
		echo "$module : Failed" >> ~/summary.log
	else
		LogMsg "$load_module"
	    LogMsg "Status: $module loaded!"
		echo "$module : Succes" >> ~/summary.log
    fi
	echo -ne "\n\n"
done



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
