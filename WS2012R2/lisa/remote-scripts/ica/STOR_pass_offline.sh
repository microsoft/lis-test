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
        *SUSE*)
            echo "SLES";;
        *Red*Hat*)
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
iscsiSTOP()
{
    ssh -i /root/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no root@"$1" "service iscsitarget stop"
    return $?
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

            # Discover the IQN
            iscsiadm -m discovery -t st -p ${1}
            if [ 0 -ne $? ]; then
                LogMsg "Error: iSCSI discovery failed. Please check the target IP address (${1})"
                UpdateTestState "TestAborted"
                UpdateSummary " iSCSI service: Failed"
                exit 1
            else
                if [ ! ${IQN} ]; then
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

#
# Compute the number of sd* drives on the system.
#
initialSdCount=0
for drive in /dev/sd*[^0-9]
do
    initialSdCount=$((initialSdCount+1))
done
((initialSdCount--))
LogMsg "After connecting to iscsi target the number of disks is: $initialSdCount"


iscsiSTOP $TargetIP
if [ 0 -ne $? ]; then
        msg="Unable to stop iscsitarget"
        LogMsg "$msg"
        UpdateTestState "ICA_TESTABORTED"
        UpdateSummary "$msg"
        exit 10
    fi
#
# Compute the number of sd* drives on the system.
#
sleep 10
finalSdCount=0
finalSdCount=$(fdisk -l 2>/dev/null | grep sd.*: | wc -l)
((finalSdCount--))
LogMsg "After disconnecting from the iscsi target the number of disks is: $finalSdCount"

if [ $finalSdCount -lt $initialSdCount ]; then
    UpdateTestState "ICA_TESTCOMPLETED"
    UpdateSummary "Test successfully completed."
else
    LogMsg "Test Failed. Initial sd count $initialSdCount, final sd count $finalSdCount"
    UpdateTestState "ICA_TESTABORTED"
    UpdateSummary "Test failed. Initial sd count $initialSdCount, final sd count $finalSdCount"
    exit 1
fi
UpdateTestState $ICA_TESTCOMPLETED
exit 0
