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
count=0

#######################################################################
# Adds a timestamp to the log file
#######################################################################
LogMsg()
{
    echo $(date "+%a %b %d %T %Y") : ${1}
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
# Checks what Linux distro we are running
#######################################################################
LinuxRelease()
{
    DISTRO=$(grep -ihs "buntu\|Suse\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux" /etc/{issue,*release,*version})

    case $DISTRO in
        *buntu*)
            echo "UBUNTU";;
        Fedora*)
            echo "FEDORA";;
        CentOS*)
            echo "CENTOS";;
        *suse*)
            echo "SLES";;
        Red*Hat*)
            echo "RHEL";;
        Debian*)
            echo "DEBIAN";;
        *)
            LogMsg "Unknown Distro"
            UpdateTestState "TestAborted"
            UpdateSummary "Unknown Distro, test aborted"
            exit 1
            ;; 
    esac
}
#######################################################################
# Connects to a iscsi target. It takes the target ip as an argument. 
#######################################################################
iscsiConnect()
{
        # Start the iscsi service. This is distro-specific.
        case $(LinuxRelease) in
        "SLES")
            /etc/init.d/open-iscsi start
            sts=$?
            if [ 0 -ne ${sts} ]; then
                LogMsg "Error: iSCSI start failed. Please check if iSCSI initiator is installed"
                UpdateTestState "TestAborted"
                UpdateSummary " iSCSI service: Failed"
                exit 1
            else
                LogMsg "iSCSI start: Success"
                UpdateSummary "iSCSI start: Success"
            fi
        ;;
            
        "DEBIAN" | "UBUNTU")
            service open-iscsi restart
            sts=$?
            if [ 0 -ne ${sts} ]; then
                LogMsg "Error: iSCSI start failed. Please check if iSCSI initiator is installed"
                UpdateTestState "TestAborted"
                UpdateSummary " iSCSI service: Failed"
                exit 1
            else
                LogMsg "iSCSI start: Success"
                UpdateSummary "iSCSI start: Success"
            fi
        ;;

        "RHEL" | "CENTOS")
            service iscsi restart
            sts=$?
            if [ 0 -ne ${sts} ]; then
                LogMsg "Error: iSCSI start failed. Please check if iSCSI initiator is installed"
                UpdateTestState "TestAborted"
                UpdateSummary " iSCSI service: Failed"
                exit 1
            else
                LogMsg "iSCSI start: Success"
                UpdateSummary "iSCSI start: Success"
            fi
        ;;

        *)
            LogMsg "Distro not supported"
            UpdateTestState "TestAborted"
            UpdateSummary "Distro not supported, test aborted"
            exit 1
        ;;
        esac

        # Check if IQN Variable in constants.sh file is present. 
        # If not, select the first target
        if [ ! ${IQN} ]; then
            # Discover the IQN
            iscsiadm -m discovery -t st -p ${1}
            if [ 0 -ne $? ]; then
                LogMsg "Error: iSCSI discovery failed. Please check the target IP address (${1})"
                UpdateTestState "TestAborted"
                UpdateSummary " iSCSI service: Failed"
                exit 1
            else
                # We take the first IQN target
                IQN=`iscsiadm -m discovery -t st -p ${1} | head -n 1 | cut -d ' ' -f 2` 
                LogMsg "iSCSI discovery: Success"
                UpdateSummary "iSCSI discovery: Success"
            fi
        fi
    
        # Now we have all data necesary to connect to the iscsi target
        iscsiadm -m node -T $IQN -p  ${1} -l
        sts=$?
        if [ 0 -ne ${sts} ]; then
            LogMsg "Error:  iSCSI connection failed ${sts}"
            UpdateTestState "TestAborted"
            UpdateSummary "iSCSI connection: Failed"
            exit 1
        else
            LogMsg "iSCSI connection: Success"
            UpdateSummary " SCSI connection: Success"
        fi
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
else
    LogMsg "File System: ${FILESYS}"
fi

if [ ! ${TargetIP} ]; then
    LogMsg "No TargetIP variable in constants.sh"
    UpdateTestState "TestAborted"
    exit 1
else
    LogMsg "Target IP: ${TargetIP}"
fi

if [ ! ${IQN} ]; then
    LogMsg "No IQN variable in constants.sh. Will try to autodiscover it"
else
    LogMsg "IQN: ${IQN}"
fi

# Connect to the iSCSI Target  
iscsiConnect $TargetIP
sts=$?
if [ 0 -ne ${sts} ]; then
    LogMsg "Error: iSCSI connect failed ${sts}"
    UpdateTestState "TestAborted"
    UpdateSummary "iSCSI connection to $TargetIP: Failed"
    exit 1
else
    LogMsg "iSCSI connection to $TargetIP: Success"
fi

# Count the Number of partition present in added new Disk . 
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
            (echo d; echo $c ; echo ; echo w) | fdisk /dev/$driveName
        done


    # Partition Drive
    (echo n; echo p; echo 1; echo ; echo +500M; echo ; echo w) | fdisk /dev/$driveName 
    (echo n; echo p; echo 2; echo ; echo; echo ; echo w) | fdisk /dev/$driveName 
    sts=$?
	if [ 0 -ne ${sts} ]; then
	    echo "Error:  Partitioning disk Failed ${sts}"
	    UpdateTestState "TestAborted"
	    UpdateSummary " Partitioning disk $driveName : Failed"
	    exit 1
	else
	    LogMsg "Partitioning disk $driveName : Sucsess"
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
fi
done

UpdateTestState $ICA_TESTCOMPLETED
exit 0
