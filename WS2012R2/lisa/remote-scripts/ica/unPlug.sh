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
# SCRIPT DESCRIPTION: 
################################################################


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
UpdateTestState "TestRunning"
cd ~

dos2unix utils.sh

chmod +x utils.sh

# Source utils.sh
. utils.sh || {
    LogMsg "Error: unable to source utils.sh!"
    UpdateTestState "TestAborted" 
    exit 2
}


# Source constants file and initialize most common variables
echo "Source constants..."
UtilsInit

chmod +x constants.sh
./constants.sh

msg=$(blockdev --getsize64 /dev/sdb)
echo "$msg" > unPlug_summary.log
UpdateTestState "TestCompleted" 