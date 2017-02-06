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

# Description:
#   Basic networking test that checks if VM can send and receive multicast packets
#
# Steps:
#   Use Omping (yum install omping -y)
#   On the 2nd VM: omping $STATIC_IP $STATIC_IP -m 239.255.254.24 -c 11 > out.client &
#   On the TEST VM: omping $STATIC_IP $STATIC_IP -m 239.255.254.24 -c 11 > out.client
#   Check results:
#   On the TEST VM: cat out.client | grep multicast | grep /0%
#   On the 2nd VM: cat out.client | grep multicast | grep /0%
#   If both have 0% packet loss, test passed
################################################################################

InstallDependencies()
{
    # Enable broadcast listening
    echo 0 >/proc/sys/net/ipv4/icmp_echo_ignore_broadcasts

    GetDistro
    case "$DISTRO" in
        suse*)
            # Disable firewall
            rcSuSEfirewall2 stop

            # Check omping
            omping -V > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                zypper addrepo http://download.opensuse.org/repositories/home:emendonca/SLE_12_SP2/home:emendonca.repo
                zypper --gpg-auto-import-keys refresh
                zypper --non-interactive in omping
                if [ $? -ne 0 ]; then
                    msg="ERROR: Failed to install omping"
                    LogMsg "$msg"
                    UpdateSummary "$msg"
                    SetTestStateFailed
                    return 1
                fi
            fi
            ;;

        ubuntu*)
            # Disable firewall
            ufw disable

            # Check omping
            omping -V > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                wget https://fedorahosted.org/releases/o/m/omping/omping-0.0.4.tar.gz
                tar -xzf omping-0.0.4.tar.gz
                cd omping-0.0.4/
                make
                make install
                if [ $? -ne 0 ]; then
                    msg="ERROR: Failed to install omping"
                    LogMsg "$msg"
                    UpdateSummary "$msg"
                    SetTestStateFailed
                    return 1
                fi
                cd ~
            fi
            ;;

        redhat*|centos*)
            # Disable firewall
            service firewalld stop

            # Check omping
            omping -V > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                yum install omping -y
                if [ $? -ne 0 ]; then
                    msg="ERROR: Failed to install omping"
                    LogMsg "$msg"
                    UpdateSummary "$msg"
                    SetTestStateFailed
                    return 1
                fi  
            fi

        ;;
        *)
            msg="ERROR: OS Version not supported"
            LogMsg "$msg"
            UpdateSummary "$msg"
            SetTestStateFailed
            return 1
        ;;
    esac

    return 0
}

InstallDependenciesRemote(){
    scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no ~/utils.sh "$REMOTE_USER"@"$STATIC_IP2":
    ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "
chmod +x ./utils.sh ;. ./utils.sh

GetDistro

echo 0 >/proc/sys/net/ipv4/icmp_echo_ignore_broadcasts

GetDistro
case \"\$DISTRO\" in
    suse*)
        # Disable firewall
        rcSuSEfirewall2 stop

        # Check omping
        omping -V > /dev/null 2>&1
        if [ \$? -ne 0 ]; then
            zypper addrepo http://download.opensuse.org/repositories/home:emendonca/SLE_12_SP2/home:emendonca.repo
            zypper --gpg-auto-import-keys refresh
            zypper --non-interactive in omping
            if [ \$? -ne 0 ]; then
                UpdateSummary \"ERROR: Failed to install omping\"
                exit 1
            fi
        fi
        ;;

    ubuntu*)
        # Disable firewall
        ufw disable

        # Check omping
        omping -V > /dev/null 2>&1
        if [ \$? -ne 0 ]; then
            wget https://fedorahosted.org/releases/o/m/omping/omping-0.0.4.tar.gz
            tar -xzf omping-0.0.4.tar.gz
            cd omping-0.0.4/
            make
            make install
            if [ \$? -ne 0 ]; then
                UpdateSummary \"ERROR: Failed to install omping\"
                exit 1
            fi
            cd ~
        fi
        ;;

    redhat*|centos*)
        # Disable firewall
        service firewalld stop

        # Check omping
        omping -V > /dev/null 2>&1
        if [ \$? -ne 0 ]; then
            yum install omping -y
            if [ \$? -ne 0 ]; then
                UpdateSummary \"ERROR: Failed to install omping\"
                exit 1
            fi  
        fi

    ;;
    *)
        UpdateSummary \"ERROR: OS Version not supported\"
        exit 1
    ;;
esac

exit 0
"
    return $?
}


################################################################################3





# Convert eol
dos2unix utils.sh

# Source SR-IOV_Utils.sh. This is the script that contains all the 
# SR-IOV basic functions (checking drivers, making de bonds, assigning IPs)
. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

UtilsInit

dos2unix NET_set_static_ip.sh
chmod +x NET_set_static_ip.sh
./NET_set_static_ip.sh
if [ $? -ne 0 ];then
    msg="ERROR: Could not set static ip on VM1!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
fi

# Install dependencies needed for testing
InstallDependencies
if [ $? -ne 0 ]; then
    msg="ERROR: Could not install dependencies on VM1!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
fi

InstallDependenciesRemote
if [ $? -ne 0 ]; then
    msg="ERROR: Could not install dependencies on VM2!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
fi 
LogMsg "INFO: All configuration completed successfully. Will proceed with the testing"

# Multicast testing
ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "omping $STATIC_IP $STATIC_IP2 -m 239.255.254.24 -c 11 > out.client &"
if [ $? -ne 0 ]; then
    msg="ERROR: Could not start omping on VM2 (STATIC_IP: ${STATIC_IP2})"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

omping $STATIC_IP $STATIC_IP2 -m 239.255.254.24 -c 11 > out.client
if [ $? -ne 0 ]; then
    msg="ERROR: Could not start omping on VM1 (STATIC_IP: ${STATIC_IP})"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

LogMsg "INFO: Omping was started on both VMs. Results will be checked in a few seconds"
sleep 5
 
# Check results - Summary must show a 0% loss of packets
multicastSummary=$(cat out.client | grep multicast | grep /0%)
if [ $? -ne 0 ]; then
    msg="ERROR: VM1 shows that packets were lost!"
    LogMsg "$msg"
    LogMsg "${multicastSummary}"
    UpdateSummary "$msg"
    UpdateSummary "${multicastSummary}"
    SetTestStateFailed
fi
LogMsg "Multicast summary"
LogMsg "${multicastSummary}"

ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "cat out.client | grep multicast | grep /0%"
if [ $? -ne 0 ]; then
    msg="ERROR: VM2 shows that packets were lost!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
fi

msg="Multicast packets were successfully sent, 0% loss"
LogMsg $msg
UpdateSummary "$msg"
SetTestStateCompleted