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

#######################################################################
# Adds a timestamp to the log file
#######################################################################
LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}
}

#######################################################################
# Updates the summary.log file
#######################################################################
UpdateSummary()
{
    echo $1 >> ~/summary.log
}

#######################################################################
# Keeps track of the state of the test
#######################################################################
UpdateTestState()
{
    echo $1 > ~/state.txt
}

####################################################################### 
# 
# Main script body 
# 
#######################################################################

# Create the state.txt file so ICA knows we are running
UpdateTestState $ICA_TESTRUNNING

# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

ORIGIFS=${IFS} # save the default internal field separator (IFS)
NL='
'
IFS=${NL}  # set the "internal field separator" (IFS) to something else than space for the loop argument splitting

for udevfile in $(find / -name "*.rules*"); do #search for all the .rules files on the system 
    IFS=${ORIGIFS}
    grep "SUBSYSTEM==\"memory\"" $udevfile | grep "ACTION==\"add\"" | grep "ATTR{state}=\"online\"" > /dev/null 2>&1 # grep for the udev rule
    sts=$?
    if [ 0 -eq ${sts} ]; then
        filelist=("${filelist[@]}" $udevfile) # populate a array with the results
    fi
done

# restore the default internal field separator (IFS)
IFS=${ORIGIFS}

# Now let's check the results
if [ ${#filelist[@]} -gt 0 ]; then # check if we found anything
    if [ ${#filelist[@]} -gt 1 ]; then # check if we found multiple file
        LogMsg "Error: More than one udev rules found. Aborting test"
        LogMsg "Following files were found:"
        # list the files 
        for rulefile in ${filelist[@]}; do
            LogMsg $rulefile
        done
        UpdateTestState $ICA_TESTABORTED
        UpdateSummary "Hot-Add udev rule present: Failed"
        exit 1
    else
        LogMsg "Hot-Add udev rule present: Success"
        LogMsg "File is:"
        LogMsg ${filelist[@]}
    fi
else
    LogMsg "Error: No Hot-Add udev rules found on the System!"
    UpdateTestState $ICA_TESTABORTED
    UpdateSummary "Hot-Add udev rules: Failed"
    exit 1
fi

UpdateTestState $ICA_TESTCOMPLETED
exit 0
