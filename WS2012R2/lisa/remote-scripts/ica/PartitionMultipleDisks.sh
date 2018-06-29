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

# Make sure the constants.sh file exists
if [ ! -e ./constants.sh ];
then
    LogMsg "Cannot find constants.sh file." >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

# Source the constants file
if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
else
    LogMsg "ERROR: Unable to source the constants file." >> ~/summary.log
    exit 1
fi

# Check if Variable in Const file is present or not
if [ ! ${fileSystems} ]; then
    LogMsg "No fileSystems variable in constants.sh" >> ~/summary.log
    UpdateTestState "TestAborted"
    exit 1
fi

# Dictionary to be used in case testing one of the filesystems needs to be skipped
declare -A fsSkipped

# Check if tools for all the filesystems are installed
for fs in "${fileSystems[@]}"
do
    LogMsg "FileSystem check for $fs" >> ~/summary.log
    command -v mkfs.$fs >> ~/summary.log
    if [ $? -ne 0 ]; then
        # UpdateSummary "Error: Tools for filesystem $fs are not installed. Test will be skipped."
        echo "Error: Tools for filesystem $fs are not installed. Test will be skipped." >> ~/summary.log
        fsSkipped[$fs]=1
    else
        # UpdateSummary "Info: Tools for $fs are installed."
        echo "Info: Tools for $fs are installed." >> ~/summary.log
        fsSkipped[$fs]=0
    fi
done

# Count total number of partitions on system, excepting sda
count=$(grep -c 'sd[b-z][0-9]' /proc/partitions)

LogMsg "Total number of partitions ${count}" >> ~/summary.log

for driveName in /dev/sd*[^0-9]
do
    #
    # Skip /dev/sda
    #
    if [ $driveName != "/dev/sda" ]
    then
        drives+=($driveName)

        # Delete existing partition
        for (( c=1 ; c<=count; count--))
        do
            (echo d; echo $c ; echo ; echo w) |  fdisk $driveName &>~/summary.log
            sleep 5
        done

        # Partition drive
        (echo n; echo p; echo 1; echo ; echo +500M; echo ; echo w) | fdisk $driveName &>~/summary.log
        sleep 5
        (echo n; echo p; echo 2; echo ; echo; echo ; echo w) | fdisk $driveName &>~/summary.log
        sleep 5
        sts=$?

        if [ 0 -ne ${sts} ]; then
            echo "Error:  Partitioning disk Failed ${sts}" >> ~/summary.log
            UpdateTestState "TestAborted"
            exit 1
        else
            echo "Partitioning disk $driveName : Success" >> ~/summary.log
        fi

        # Create filesystem on it
        for fs in "${fileSystems[@]}"
        do
            if [ ${fsSkipped[$fs]} -eq 0 ]
            then
                echo "$fs is NOT skipped" >> ~/fsCheck.log
                fsSkipped[$fs]=1
                echo "y" | mkfs.$fs ${driveName}1  &>~/summary.log; echo "y" | mkfs.$fs ${driveName}2 &>~/summary.log
                sts=$?
                if [ 0 -ne ${sts} ]
                then
                    LogMsg "Warning: creating filesystem Failed ${sts}" >> ~/summary.log
                    LogMsg "Warning: test for $fs will be skipped" >> ~/summary.log
                else
                    LogMsg "Creating FileSystem $fs on disk  $driveName : Success" >> ~/summary.log
                fi
                break
            else
                echo "$fs is skipped" >> ~/fsCheck.log
            fi
        done

        sleep 1
    fi

    fs=${fs//,}
    filename="summary-$fs.log"
    cp ~/summary.log ~/$filename

done

UpdateTestState $ICA_TESTCOMPLETED
exit 0
