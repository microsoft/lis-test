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

# Make sure the constants.sh file exists
if [ ! -e ./constants.sh ];
then
    LogMsg "Cannot find constants.sh file."
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

# Source the constants file
if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
else
    LogMsg "ERROR: Unable to source the constants file."
    exit 1
fi

# Check if Variable in Const file is present or not
if [ ! ${FILESYS} ]; then
    LogMsg "No FILESYS variable in constants.sh"
    UpdateTestState "TestAborted"
    exit 1
fi

# Count the Number of partition present in added new Disk . 
count=0
for disk in $(cat /proc/partitions | grep sd | awk '{print $4}')
do
        if [[ "$disk" != "sda"* ]];
        then
                ((count++))
        fi
done

((count--))

# Format, Partition and mount all the new disk on this system.
firstDrive=1
for drive in $(find /sys/devices/ -name 'sd*' | grep 'sd.$' | sed 's/.*\(...\)$/\1/')
do
    #
    # Skip /dev/sda
    #
    if [ $drive != "sda"  ] ; then 

    driveName="${drive}"
    # Delete the exisiting partition

    for (( c=1 ; c<=count; count--))
        do
            (echo d; echo $c ; echo ; echo w) |  fdisk /dev/$driveName
        done


# Partition Drive
    (echo n; echo p; echo 1; echo ; echo +500M; echo ; echo w) |  fdisk /dev/$driveName 
    (echo n; echo p; echo 2; echo ; echo; echo ; echo w) |  fdisk /dev/$driveName 
    sts=$?
  if [ 0 -ne ${sts} ]; then
      echo "Error:  Partitioning disk Failed ${sts}"
      UpdateTestState "TestAborted"
      UpdateSummary " Partitioning disk $driveName : Failed"
      exit 1
  else
      echo "Partitioning disk $driveName : Sucsess"
      UpdateSummary " Partitioning disk $driveName : Sucsess"
  fi

   sleep 1

# Create file sytem on it . 
   echo "y" | mkfs.$FILESYS /dev/${driveName}1  ; echo "y" | mkfs.$FILESYS /dev/${driveName}2  
   sts=$?
        if [ 0 -ne ${sts} ]; then
            LogMsg "Error:  creating filesystem  Failed ${sts}"
            UpdateTestState "TestAborted"
            UpdateSummary " Creating FileSystem $filesys on disk $driveName : Failed"
            exit 1
        else
            LogMsg "Creating FileSystem $FILESYS on disk  $driveName : Sucsess"
            UpdateSummary " Creating FileSystem $FILESYS on disk $driveName : Sucsess"
        fi

   sleep 1

# mount the disk .
   MountName=${driveName}1
   if [ ! -e ${MountName} ]; then
     mkdir $MountName
   fi
   MountName1=${driveName}2
   if [ ! -e ${MountName1} ]; then
     mkdir $MountName1
   fi
   mount  /dev/${driveName}1 $MountName ; mount  /dev/${driveName}2 $MountName1
   sts=$?
       if [ 0 -ne ${sts} ]; then
            LogMsg "Error:  mounting disk Failed ${sts}"
            UpdateTestState "TestAborted"
            UpdateSummary " Mounting disk $driveName on $MountName: Failed"
            exit 1
       else
            LogMsg "mounting disk ${driveName}1 on ${MountName}"
            LogMsg "mounting disk ${driveName}2 on ${MountName1}"
            UpdateSummary " Mounting disk ${driveName}1 : Sucsess"
            UpdateSummary " Mounting disk ${driveName}2 : Sucsess"
       fi

    # Now Freeze one of the volume.
    fsfreeze -f $MountName1
    sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "Error:  fsfreeze disk Failed ${sts}"
        UpdateTestState "TestAborted"
        UpdateSummary "Failed to fsfreeze $MountName1"
        exit 1
    else
        LogMsg "fsfreeze succeed"
        UpdateSummary "fsfreeze $MountName1: Success"

  fi
fi
done

UpdateTestState $ICA_TESTCOMPLETED

exit 0