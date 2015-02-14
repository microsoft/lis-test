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
# GetOSVersion
#######################################################################
function GetOSVersion {

    # Figure out which vendor we are
    if [[ -x "`which sw_vers 2>/dev/null`" ]]; then
        # OS/X
        os_VENDOR=`sw_vers -productName`
        os_RELEASE=`sw_vers -productVersion`
        os_UPDATE=${os_RELEASE##*.}
        os_RELEASE=${os_RELEASE%.*}
        os_PACKAGE=""
        if [[ "$os_RELEASE" =~ "10.7" ]]; then
            os_CODENAME="lion"
        elif [[ "$os_RELEASE" =~ "10.6" ]]; then
            os_CODENAME="snow leopard"
        elif [[ "$os_RELEASE" =~ "10.5" ]]; then
            os_CODENAME="leopard"
        elif [[ "$os_RELEASE" =~ "10.4" ]]; then
            os_CODENAME="tiger"
        elif [[ "$os_RELEASE" =~ "10.3" ]]; then
            os_CODENAME="panther"
        else
            os_CODENAME=""
        fi
    elif [[ -x $(which lsb_release 2>/dev/null) ]]; then
        os_VENDOR=$(lsb_release -i -s)
        os_RELEASE=$(lsb_release -r -s)
        os_UPDATE=""
        os_PACKAGE="rpm"
        if [[ "Debian,Ubuntu,LinuxMint" =~ $os_VENDOR ]]; then
            os_PACKAGE="deb"
        elif [[ "SUSE LINUX" =~ $os_VENDOR ]]; then
            lsb_release -d -s | grep -q openSUSE
            if [[ $? -eq 0 ]]; then
                os_VENDOR="openSUSE"
            fi
        elif [[ $os_VENDOR == "openSUSE project" ]]; then
            os_VENDOR="openSUSE"
        elif [[ $os_VENDOR =~ Red.*Hat ]]; then
            os_VENDOR="Red Hat"
        fi
        os_CODENAME=$(lsb_release -c -s)
    elif [[ -r /etc/redhat-release ]]; then
        # Red Hat Enterprise Linux Server release 5.5 (Tikanga)
        # Red Hat Enterprise Linux Server release 7.0 Beta (Maipo)
        # CentOS release 5.5 (Final)
        # CentOS Linux release 6.0 (Final)
        # Fedora release 16 (Verne)
        # XenServer release 6.2.0-70446c (xenenterprise)
        os_CODENAME=""
        for r in "Red Hat" CentOS Fedora XenServer; do
            os_VENDOR=$r
            if [[ -n "`grep \"$r\" /etc/redhat-release`" ]]; then
                ver=`sed -e 's/^.* \([0-9].*\) (\(.*\)).*$/\1\|\2/' /etc/redhat-release`
                os_CODENAME=${ver#*|}
                os_RELEASE=${ver%|*}
                os_UPDATE=${os_RELEASE##*.}
                os_RELEASE=${os_RELEASE%.*}
                break
            fi
            os_VENDOR=""
        done
        os_PACKAGE="rpm"
    elif [[ -r /etc/SuSE-release ]]; then
        for r in openSUSE "SUSE Linux"; do
            if [[ "$r" = "SUSE Linux" ]]; then
                os_VENDOR="SUSE LINUX"
            else
                os_VENDOR=$r
            fi

            if [[ -n "`grep \"$r\" /etc/SuSE-release`" ]]; then
                os_CODENAME=`grep "CODENAME = " /etc/SuSE-release | sed 's:.* = ::g'`
                os_RELEASE=`grep "VERSION = " /etc/SuSE-release | sed 's:.* = ::g'`
                os_UPDATE=`grep "PATCHLEVEL = " /etc/SuSE-release | sed 's:.* = ::g'`
                break
            fi
            os_VENDOR=""
        done
        os_PACKAGE="rpm"
    # If lsb_release is not installed, we should be able to detect Debian OS
    elif [[ -f /etc/debian_version ]] && [[ $(cat /proc/version) =~ "Debian" ]]; then
        os_VENDOR="Debian"
        os_PACKAGE="deb"
        os_CODENAME=$(awk '/VERSION=/' /etc/os-release | sed 's/VERSION=//' | sed -r 's/\"|\(|\)//g' | awk '{print $2}')
        os_RELEASE=$(awk '/VERSION_ID=/' /etc/os-release | sed 's/VERSION_ID=//' | sed 's/\"//g')
    fi
    export os_VENDOR os_RELEASE os_UPDATE os_PACKAGE os_CODENAME
}

#######################################################################
# Determine if current distribution is a Fedora-based distribution
# (Fedora, RHEL, CentOS, etc).
#######################################################################
function is_fedora {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "Fedora" ] || [ "$os_VENDOR" = "Red Hat" ] || \
        [ "$os_VENDOR" = "CentOS" ] || [ "$os_VENDOR" = "OracleServer" ]
}

#######################################################################
# Determine if current distribution is a Rhel/CentOS 7 distribution
#######################################################################
function is_rhel7 {
    if [[ -z "$os_RELEASE" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "Red Hat" ] || \
        [ "$os_VENDOR" = "CentOS" ] || [ "$os_VENDOR" = "OracleServer" ] && \
        [ "$os_RELEASE" = "7" ]
}

#######################################################################
# Determine if current distribution is a SUSE-based distribution
# (openSUSE, SLE).
#######################################################################
function is_suse {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "openSUSE" ] || [ "$os_VENDOR" = "SUSE LINUX" ]
}

#######################################################################
# Determine if current distribution is an Ubuntu-based distribution
# It will also detect non-Ubuntu but Debian-based distros
#######################################################################
function is_ubuntu {
    if [[ -z "$os_PACKAGE" ]]; then
        GetOSVersion
    fi
    [ "$os_PACKAGE" = "deb" ]
}

#######################################################################
# Connects to a iscsi target. It takes the target ip as an argument. 
#######################################################################
function iscsiConnect() {
# Start the iscsi service. This is distro-specific.
    if is_suse ; then
        /etc/init.d/open-iscsi start
        sts=$?
        if [ 0 -ne ${sts} ]; then
            LogMsg "ERROR: iSCSI start failed. Please check if iSCSI initiator is installed"
            UpdateTestState "TestAborted"
            UpdateSummary "iSCSI service: Failed"
            exit 1
        else
            LogMsg "iSCSI start: Success"
            UpdateSummary "iSCSI start: Success"
        fi
    elif is_ubuntu ; then
        service open-iscsi restart
        sts=$?
        if [ 0 -ne ${sts} ]; then
            LogMsg "ERROR: iSCSI start failed. Please check if iSCSI initiator is installed"
            UpdateTestState "TestAborted"
            UpdateSummary "iSCSI service: Failed"
            exit 1
        else
            LogMsg "iSCSI start: Success"
            UpdateSummary "iSCSI start: Success"
        fi

    elif is_fedora ; then
        service iscsi restart
        sts=$?
        if [ 0 -ne ${sts} ]; then
            LogMsg "ERROR: iSCSI start failed. Please check if iSCSI initiator is installed"
            UpdateTestState "TestAborted"
            UpdateSummary "iSCSI service: Failed"
            exit 1
        else
            LogMsg "iSCSI start: Success"
            UpdateSummary "iSCSI start: Success"
        fi
    else
        LogMsg "Distro not supported"
        UpdateTestState "TestAborted"
        UpdateSummary "Distro not supported, test aborted"
        exit 1
    fi

    # Discover the IQN
    iscsiadm -m discovery -t st -p ${TargetIP}
    if [ 0 -ne $? ]; then
        LogMsg "ERROR: iSCSI discovery failed. Please check the target IP address (${TargetIP})"
        UpdateTestState "TestAborted"
        UpdateSummary " iSCSI service: Failed"
        exit 1
    elif [ ! ${IQN} ]; then  # Check if IQN Variable is present in constants.sh, else select the first target. 
        # We take the first IQN target
        IQN=`iscsiadm -m discovery -t st -p ${TargetIP} | head -n 1 | cut -d ' ' -f 2` 
    fi
    
    # Now we have all data necesary to connect to the iscsi target
    iscsiadm -m node -T ${IQN} -p  ${TargetIP} -l
    sts=$?
    if [ 0 -ne ${sts} ]; then
        LogMsg "ERROR: iSCSI connection failed ${sts}"
        UpdateTestState "TestAborted"
        UpdateSummary "iSCSI connection: Failed"
        exit 1
    else
        LogMsg "iSCSI connection to ${TargetIP} >> ${IQN} : Success"
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
iscsiConnect
sts=$?
if [ 0 -ne ${sts} ]; then
    LogMsg "ERROR: iSCSI connect failed ${sts}"
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
        echo "ERROR:  Partitioning disk Failed ${sts}"
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
            LogMsg "ERROR:  creating filesystem  Failed ${sts}"
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
           LogMsg "ERROR:  mounting disk Failed ${sts}"
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
