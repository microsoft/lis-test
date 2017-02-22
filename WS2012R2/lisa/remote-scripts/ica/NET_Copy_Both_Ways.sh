#!/bin/bash

#####################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
#####################################################################

#############################################################################################################
#
# Description:
#   This script verifies that the network doesn't loose connection
#   by trigerring two scp processes that copy two files, at the same time,
#   between the two VMs.
#
#
#   Steps:
#   1. Verify configuration file constants.sh
#   2. Verify ssh private key file for remote VM was given
#   3. Ping the remote server through the Synthetic Adapter card
#   4. Verify there is enough local and remote disk space for 20GB
#   5. Create two 10GB files, one on the local VM and one on the remote VM, from /dev/urandom
#   6. Save md5sums and start copying the two files.
#   7. Compare md5sums for both cases
#
#   Parameters required:
#       STATIC_IP2
#       SSH_PRIVATE_KEY
#
#   Optional parameters:
#       TC_COVERED
#       NO_DELETE
#       REMOTE_USER
#       ZERO_FILE
#       FILE_SIZE_GB
#       STATIC_IP
#       NETMASK
#       GATEWAY
#
#   Parameter explanation:
#   STATIC_IP2 is the address of the second vm.
#   The script assumes that the SSH_PRIVATE_KEY is located in $HOME/.ssh/$SSH_PRIVATE_KEY
#   TC_COVERED is the test id from LIS testing
#   NO_DELETE stops the script from deleting the 10GB files locally and remotely
#   REMOTE_USER is the user used to ssh into the remote VM. Default is root
#   ZERO_FILE creates a file filled with 0. Is created much faster than the one from /dev/urandom
#   FILE_SIZE_GB override the 10GB size. File size specified in GB
#   STATIC_IP is the address that will be assigned to the VM's synthetic network adapter
#   NETMASK of this VM's subnet. Defaults to /24 if not set.
#   GATEWAY is the IP Address of the default gateway
#
#############################################################################################################

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Source constants file and initialize most common variables
UtilsInit

# In case of error
case $? in
    0)
        #do nothing
        ;;
    1)
        LogMsg "Unable to cd to $LIS_HOME. Aborting..."
        UpdateSummary "Unable to cd to $LIS_HOME. Aborting..."
        SetTestStateAborted
        exit 3
        ;;
    2)
        LogMsg "Unable to use test state file. Aborting..."
        UpdateSummary "Unable to use test state file. Aborting..."
        # need to wait for test timeout to kick in
            # hailmary try to update teststate
            sleep 60
            echo "TestAborted" > state.txt
        exit 4
        ;;
    3)
        LogMsg "Error: unable to source constants file. Aborting..."
        UpdateSummary "Error: unable to source constants file"
        SetTestStateAborted
        exit 5
        ;;
    *)
        # should not happen
        LogMsg "UtilsInit returned an unknown error. Aborting..."
        UpdateSummary "UtilsInit returned an unknown error. Aborting..."
        SetTestStateAborted
        exit 6
        ;;
esac

# Parameters to check in constants file
if [ "${STATIC_IP2:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter STATIC_IP2 is not defined in ${LIS_CONSTANTS_FILE}"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
    exit 30
fi

if [ "${STATIC_IP2_V6:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter STATIC_IP2_V6 is not defined in ${LIS_CONSTANTS_FILE}. No IPV6 related tests will be run."
    LogMsg "$msg"
    if [ "${TestIPV6}" = "yes" ]; then
        SetTestStateFailed
        exit 30
    fi
fi

if [ "${SSH_PRIVATE_KEY:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter SSH_PRIVATE_KEY is not defined in ${LIS_CONSTANTS_FILE}"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
    exit 30
fi

# Set remote user
if [ "${REMOTE_USER:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter REMOTE_USER is not defined in ${LIS_CONSTANTS_FILE} . Using root instead"
    LogMsg "$msg"
    REMOTE_USER=root
else
    msg="REMOTE_USER set to $REMOTE_USER"
    LogMsg "$msg"
fi

# Set clean-up policy
if [ "${NO_DELETE:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter NO_DELETE is not defined in ${__LIS_CONSTANTS_FILE} . Generated file will be deleted"
    LogMsg "$msg"
    NO_DELETE=0
else
    msg="NO_DELETE is set. Generated file will not be deleted"
    NO_DELETE=1
    LogMsg "$msg"
fi

IFS=',' read -a networkType <<< "$NIC"

# set gateway parameter
if [ "${GATEWAY:-UNDEFINED}" = "UNDEFINED" ]; then
    if [ "${networkType[2]}" = "External" ]; then
        msg="The test parameter GATEWAY is not defined in constants file . The default gateway will be set for all interfaces."
        LogMsg "$msg"
        GATEWAY=$(/sbin/ip route | awk '/default/ { print $3 }')
    else
        msg="The test parameter GATEWAY is not defined in constants file . No gateway will be set."
        LogMsg "$msg"
        GATEWAY=''
    fi
else
    CheckIP "$GATEWAY"

    if [ 0 -ne $? ]; then
        msg=""
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateAborted
        exit 10
    fi
fi

declare __iface_ignore

# Parameter provided in constants file
if [ "${ipv4:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter ipv4 is not defined in constants file! Make sure you are using the latest LIS code."
    LogMsg "$msg"
    UpdateSummary "$msg"
else

    CheckIP "$ipv4"

    if [ 0 -ne $? ]; then
        msg="Test parameter ipv4 = $ipv4 is not a valid IP Address"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 10
    fi

    # Get the interface associated with the given ipv4
    __iface_ignore=$(ip -o addr show| grep "$ipv4" | cut -d ' ' -f2)
fi

if [ "${DISABLE_NM:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter DISABLE_NM is not defined in constants file. If the NetworkManager is running it could interfere with the test."
    LogMsg "$msg"
else
    if [[ "$DISABLE_NM" =~ [Yy][Ee][Ss] ]]; then

        # work-around for suse where the network gets restarted in order to shutdown networkmanager.
        declare __orig_netmask
        GetDistro
        case "$DISTRO" in
            suse*)
                __orig_netmask=$(ip -o addr show | grep "$ipv4" | cut -d '/' -f2 | cut -d ' ' -f1)
                ;;
        esac
        DisableNetworkManager
        case "$DISTRO" in
            suse*)
                ip link set "$__iface_ignore" down
                ip addr flush dev "$__iface_ignore"
                ip addr add "$ipv4"/"$__orig_netmask" dev "$__iface_ignore"
                ip link set "$__iface_ignore" up
                ;;
        esac
    fi
fi

# Retrieve synthetic network interfaces
GetSynthNetInterfaces

if [ 0 -ne $? ]; then
    msg="No synthetic network interfaces found"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

# Remove interface if present
SYNTH_NET_INTERFACES=(${SYNTH_NET_INTERFACES[@]/$__iface_ignore/})

if [ ${#SYNTH_NET_INTERFACES[@]} -eq 0 ]; then
    msg="The only synthetic interface is the one which LIS uses to send files/commands to the VM."
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
    exit 10
fi


LogMsg "Found ${#SYNTH_NET_INTERFACES[@]} synthetic interface(s): ${SYNTH_NET_INTERFACES[*]} in VM"

# Test interfaces
declare -i __iterator
declare -ai __invalid_positions
for __iterator in "${!SYNTH_NET_INTERFACES[@]}"; do
    ip link show "${SYNTH_NET_INTERFACES[$__iterator]}" >/dev/null 2>&1
    if [ 0 -ne $? ]; then
        # mark invalid positions
        __invalid_positions=("${__invalid_positions[@]}" "$__iterator")
        LogMsg "Warning synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]} is unusable"
    fi
done

if [ ${#SYNTH_NET_INTERFACES[@]} -eq  ${#__invalid_positions[@]} ]; then
    msg="No usable synthetic interface remains"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

# reset iterator and remove invalid positions from array
__iterator=0
while [ $__iterator -lt ${#__invalid_positions[@]} ]; do
    # eliminate from SYNTH_NET_INTERFACES array the interface located on position ${__invalid_positions[$__iterator]}
    SYNTH_NET_INTERFACES=("${SYNTH_NET_INTERFACES[@]:0:${__invalid_positions[$__iterator]}}" "${SYNTH_NET_INTERFACES[@]:$((${__invalid_positions[$__iterator]}+1))}")
    : $((__iterator++))
done

# delete array
unset __invalid_positions

if [ 0 -eq ${#SYNTH_NET_INTERFACES[@]} ]; then
    msg="This should not have happened. Probable internal error"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 100
fi

declare -ai __invalid_positions
__iterator=0
# Try to get DHCP address for synthetic adaptor and ping if configured
while [ $__iterator -lt ${#SYNTH_NET_INTERFACES[@]} ]; do
    CreateIfupConfigFile "${SYNTH_NET_INTERFACES[$__iterator]}" "dhcp"
    if [ 0 -eq $? ]; then
        # add some interface output
        UpdateSummary "Successfully set ip from dhcp on interface ${SYNTH_NET_INTERFACES[$__iterator]}"
        LogMsg "$(ip -o addr show ${SYNTH_NET_INTERFACES[$__iterator]} | grep -vi inet6)"

        # set default gateway if specified
        if [ -n "$GATEWAY" ]; then
            LogMsg "Setting $GATEWAY as default gateway on dev ${SYNTH_NET_INTERFACES[$__iterator]}"
            CreateDefaultGateway "$GATEWAY" "${SYNTH_NET_INTERFACES[$__iterator]}"
            if [ 0 -ne $? ]; then
                LogMsg "Warning! Failed to set default gateway!"
            fi
        fi

        LogMsg "Trying to ping $STATIC_IP2"
        sleep 20

        # ping the remote host using an easily distinguishable pattern 0xcafed00d`null`copy`null`dhcp`null`
        ping -I "${SYNTH_NET_INTERFACES[$__iterator]}" -c 10 -p "cafed00d00636f7079006468637000" "$STATIC_IP2" >/dev/null 2>&1
        if [ 0 -eq $? ]; then
            # ping worked!
            LogMsg "Successfully pinged $STATIC_IP2 through synthetic ${SYNTH_NET_INTERFACES[$__iterator]} (dhcp)."
            UpdateSummary "Successfully pinged $STATIC_IP2 through synthetic ${SYNTH_NET_INTERFACES[$__iterator]} (dhcp)."
            break
        else
            LogMsg "Unable to ping $STATIC_IP2 through synthetic ${SYNTH_NET_INTERFACES[$__iterator]}"
        fi
    fi
    __invalid_positions=("${__invalid_positions[@]}" "$__iterator")
    LogMsg "Unable to get address from dhcp server on synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
    UpdateSummary "Unable to get address from dhcp server on synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
    : $((__iterator++))
done

# check if there is any interface capable of pinging remote_vm
if [ ${#SYNTH_NET_INTERFACES[@]} -eq  ${#__invalid_positions[@]} ]; then
    # delete array
    unset __invalid_positions
    # try using static IPs
    declare -ai __invalid_positions
    __iterator=0
    # set synthetic interface address to $STATIC_IP
    while [ $__iterator -lt ${#SYNTH_NET_INTERFACES[@]} ]; do
        SetIPstatic "$STATIC_IP" "${SYNTH_NET_INTERFACES[$__iterator]}" "$NETMASK"
        # if successfully assigned address
        if [ 0 -eq $? ]; then
            LogMsg "Successfully assigned $STATIC_IP ($NETMASK) to synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
            UpdateSummary "Successfully assigned $STATIC_IP ($NETMASK) to synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"

            # set default gateway if specified
            if [ -n "$GATEWAY" ]; then
                LogMsg "Setting $GATEWAY as default gateway on dev ${SYNTH_NET_INTERFACES[$__iterator]}"
                CreateDefaultGateway "$GATEWAY" "${SYNTH_NET_INTERFACES[$__iterator]}"
                if [ 0 -ne $? ]; then
                    LogMsg "Warning! Failed to set default gateway!"
                fi
            fi
            # ping the remote vm using an easily distinguishable pattern 0xcafed00d`null`cop`null`static`null`
            ping -I "${SYNTH_NET_INTERFACES[$__iterator]}" -c 10 -p "cafed00d00636f700073746174696300" "$STATIC_IP2" >/dev/null 2>&1

            if [ 0 -eq $? ]; then
                # ping worked!
                UpdateSummary "Successfully pinged $STATIC_IP2 on synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"
                break
            else
                LogMsg "Unable to ping $STATIC_IP2 through ${SYNTH_NET_INTERFACES[$__iterator]}"
            fi
        else
            LogMsg "Unable to set static IP to interface ${SYNTH_NET_INTERFACES[$__iterator]}"
        fi
        # shut interface down
        ip link set ${SYNTH_NET_INTERFACES[$__iterator]} down
        __invalid_positions=("${__invalid_positions[@]}" "$__iterator")
        : $((__iterator++))
    done

    # if no interface was capable of pinging the STATIC_IP2 by having its IP address statically assigned, give up
    if [ $__iterator -eq ${#SYNTH_NET_INTERFACES[@]} ]; then
        msg="Not even with static IPs was any interface capable of pinging $STATIC_IP2 . Failed..."
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 40
    fi
else
    # reset iterator and remove invalid positions from array
    __iterator=0
    while [ $__iterator -lt ${#__invalid_positions[@]} ]; do
        # eliminate from SYNTH_NET_INTERFACES array the interface located on position ${__invalid_positions[$__iterator]}
        SYNTH_NET_INTERFACES=("${SYNTH_NET_INTERFACES[@]:0:${__invalid_positions[$__iterator]}}" "${SYNTH_NET_INTERFACES[@]:$((${__invalid_positions[$__iterator]}+1))}")
        : $((__iterator++))
    done
fi

# delete array
unset __invalid_positions

if [ 0 -eq ${#SYNTH_NET_INTERFACES[@]} ]; then
    msg="This should not have happened. Probable internal error above line $LINENO"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 100
fi

LogMsg "Successfully pinged $STATIC_IP2 on synthetic interface(s) ${SYNTH_NET_INTERFACES[@]}"

# get file size in bytes
declare -i __file_size

if [ "${FILE_SIZE_GB:-UNDEFINED}" = "UNDEFINED" ]; then
    __file_size=$((10*1024*1024*1024))                      # 10 GB
else
    __file_size=$((FILE_SIZE_GB*1024*1024*1024))
fi

LogMsg "Checking for local disk space"
total_space=$((__file_size*2))
LogMsg "Total disk space needed - $total_space"
# Check disk size on local vm
IsFreeSpace "$HOME" "$total_space"
if [ 0 -ne $? ]; then
    msg="Not enough free space on current partition to create the test file"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

LogMsg "Enough free space locally to create the file"
LogMsg "Checking for disk space on $STATIC_IP2"
# Check disk size on remote vm. Cannot use IsFreeSpace function directly. Need to export utils.sh to the remote_vm, source it and then access the functions therein
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no utils.sh "$REMOTE_USER"@"$STATIC_IP2":/tmp
if [ 0 -ne $? ]; then
    msg="Cannot copy utils.sh to $STATIC_IP2:/tmp"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

remote_home=$(ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "
    . /tmp/utils.sh
    IsFreeSpace \"\$HOME\" $total_space
    if [ 0 -ne \$? ]; then
        exit 1
    fi
    echo \"\$HOME\"
    exit 0
    ")

# get ssh status
sts=$?

if [ 1 -eq $sts ]; then
    msg="Not enough free space on $STATIC_IP2 to create the test file"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

# if status is neither 1, nor 0 then ssh encountered an error
if [ 0 -ne $sts ]; then
    msg="Unable to connect through ssh to $STATIC_IP2"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

LogMsg "Enough free space remotely to create the file"

# get source to create the file
if [ "${ZERO_FILE:-UNDEFINED}" = "UNDEFINED" ]; then
    file_source=/dev/urandom
else
    file_source=/dev/zero
fi

# create file locally with PID appended
output_file_1=large_file_1_$$
output_file_2=large_file_2_$$

if [ -d "$HOME"/"$output_file_1" ]; then
    rm -rf "$HOME"/"$output_file_1"
fi

if [ -e "$HOME"/"$output_file_1" ]; then
    rm -f "$HOME"/"$output_file_1"
fi

#disabling firewall on both VMs
iptables -F
remote_home=$(ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "iptables -F")

dd if=$file_source of="$HOME"/"$output_file_1" bs=1M count=$((__file_size/1024/1024))

if [ 0 -ne $? ]; then
    msg="Unable to create file $output_file_1 in $HOME"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

LogMsg "Successfully created $output_file"
ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "dd if=${file_source} of=${remote_home}/${output_file_2} bs=1M count=$((__file_size/1024/1024))"
if [ 0 -ne $? ]; then
    msg="Unable to create file $output_file_2 in $HOME"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

#compute md5sum
local_md5sum_file_1=$(md5sum $output_file_1 | cut -f 1 -d ' ')
remote_md5sum_file_2=$(ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "md5sum ${remote_home}/${output_file_2} |  cut -f 1 -d ' '")

#send file to remote_vm
remote_exit_status_file_path = "${remote_home}/exit_status"
remote_cmd="
    scp -i ${HOME}/.ssh/${SSH_PRIVATE_KEY} -v -o StrictHostKeyChecking=no ${remote_home}/${output_file_2} ${REMOTE_USER}@${ipv4}:${HOME}/${output_file_2}
    echo $? > ${remote_exit_status_file_path}
    "
ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "setsid  ${remote_cmd} >/dev/null 2>&1 < /dev/null &"
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$output_file_1" "$REMOTE_USER"@"$STATIC_IP2":"$remote_home"/"$output_file_1"

if [ 0 -ne $? ]; then
    msg="Unable to copy file $output_file_1 to $STATIC_IP2:$remote_home/$output_file_1"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

LogMsg "Successfully sent $output_file_1 to $STATIC_IP2:${remote_home}/$output_file_1"
UpdateSummary "Successfully sent $output_file_1 to $STATIC_IP2:${remote_home}/$output_file_1"

remote_exit_status=$(ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "cat ${remote_exit_status_file_path}")
if [ remote_exit_status -ne $? ]; then
    msg="Unable to copy file $output_file_2 to $ipv4:${HOME}/${output_file_2}"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

# save md5sumes of copied files
remote_md5sum_file_1=$(ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "md5sum ${remote_home}/${output_file_1} | cut -f 1 -d ' '")
local_md5sum_file_2=$(md5sum ${HOME}/${output_file_2} | cut -f 1 -d ' ')

# delete files
rm -f "$HOME"/$output_file_1
rm -f "$HOME"/$output_file_2}
ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "rm -f ${remote_home}/${output_file_1}"
ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "rm -f ${remote_home}/${output_file_2}"

if [ "$local_md5sum_file_1" != "$remote_md5sum_file_1" ]; then
    msg="md5sums differ for ${output_file_1}. Files do not match: ${local_md5sum_file_1} - ${remote_md5sum_file_1}"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi


if [ "$local_md5sum_file_2" != "$remote_md5sum_file_2" ]; then
    msg="md5sums differ for ${output_file_2}. Files do not match: ${local_md5sum_file_2} - ${remote_md5sum_file_2}"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

UpdateSummary "Checksums of files match. Test successful"
LogMsg "Updating test case state to completed"
SetTestStateCompleted
exit 0
