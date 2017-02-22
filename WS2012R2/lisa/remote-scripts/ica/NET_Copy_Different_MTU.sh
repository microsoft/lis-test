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

# Description:
#   This script verifies that the network doesn't
#   lose connection by copying a large file(~1GB)file
#   between two VM's when MTU is set to 9000 on the network 
#   adapters.
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
#   Parameters explanation:
#   STATIC_IP2 is the address of the second VM.
#   The script assumes that the SSH_PRIVATE_KEY is located in $HOME/.ssh/$SSH_PRIVATE_KEY
#   TC_COVERED is the test id from LIS testing
#   NO_DELETE stops the script from deleting the test files locally and remotely
#   REMOTE_USER is the user used to ssh into the remote VM. Default is root
#   ZERO_FILE creates a file filled with 0. Is created much faster than the one from /dev/urandom
#   FILE_SIZE_GB test file size. File size is specified in GB.
#   STATIC_IP is the address that will be assigned to the VM's synthetic network adapter
#   NETMASK of this VM's subnet. Defaults to /24 if not set.
#   GATEWAY is the IP Address of the default gateway
#
#############################################################################################################

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

# Source constants file and initialize most common variables
UtilsInit

# In case of error
case $? in
    0)
        # Do nothing
        ;;
    1)
        LogMsg "ERROR: Unable to cd to $LIS_HOME. Aborting..."
        UpdateSummary "ERROR: Unable to cd to $LIS_HOME. Aborting..."
        SetTestStateAborted
        exit 3
        ;;
    2)
        LogMsg "ERROR: Unable to use test state file. Aborting..."
        UpdateSummary "ERROR: Unable to use test state file. Aborting..."
        # Need to wait for test timeout to kick in
        sleep 60
        echo "TestAborted" > state.txt
        exit 4
        ;;
    3)
        LogMsg "ERROR: unable to source constants file. Aborting..."
        UpdateSummary "ERROR: unable to source constants file"
        SetTestStateAborted
        exit 5
        ;;
    *)
        # Should not happen
        LogMsg "ERROR: UtilsInit returned an unknown error. Aborting..."
        UpdateSummary "ERROR: UtilsInit returned an unknown error. Aborting..."
        SetTestStateAborted
        exit 6
        ;;
esac

# Parameters to check in constants file
if [ "${STATIC_IP2:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="ERROR: The test parameter STATIC_IP2 is not defined in ${LIS_CONSTANTS_FILE}"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateAborted
    exit 30
fi

if [ "${SSH_PRIVATE_KEY:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="ERROR: The test parameter SSH_PRIVATE_KEY is not defined in ${LIS_CONSTANTS_FILE}"
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

# Check for expect. If it's not on the system, install it
expect -v
if [ $? -ne 0 ]; then
    msg="Expect not found. Trying to install it"
    LogMsg "$msg"

    GetDistro
    case "$DISTRO" in
        suse*)
            zypper --non-interactive in expect
            if [ $? -ne 0 ]; then
                msg="ERROR: Failed to install expect"
                LogMsg "$msg"
                UpdateSummary "$msg"
                SetTestStateFailed
                exit 10
            fi
            ;;
        ubuntu*|debian*)
            apt-get install expect -y
            if [ $? -ne 0 ]; then
                msg="ERROR: Failed to install expect"
                LogMsg "$msg"
                UpdateSummary "$msg"
                SetTestStateFailed
                exit 10
            fi
            ;;
        redhat*|centos*)
            yum install expect -y
            if [ $? -ne 0 ]; then
                msg="ERROR: Failed to install expect"
                LogMsg "$msg"
                UpdateSummary "$msg"
                SetTestStateFailed
                exit 10
            fi
            ;;
            *)
                msg="ERROR: OS Version not supported"
                LogMsg "$msg"
                UpdateSummary "$msg"
                SetTestStateFailed
                exit 10
            ;;
    esac
fi

IFS=',' read -a networkType <<< "$NIC"

# Set gateway parameter
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
        msg="ERROR: Gateway format not good"
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
        msg="ERROR: Test parameter ipv4 = $ipv4 is not a valid IP Address"
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

        # Work-around for suse where the network gets restarted in order to shutdown networkmanager.
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
    msg="ERROR: No synthetic network interfaces found"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

# Remove interface if present
SYNTH_NET_INTERFACES=(${SYNTH_NET_INTERFACES[@]/$__iface_ignore/})

if [ ${#SYNTH_NET_INTERFACES[@]} -eq 0 ]; then
    msg="ERROR: The only synthetic interface is the one which LIS uses to send files/commands to the VM."
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
        # Mark invalid positions
        __invalid_positions=("${__invalid_positions[@]}" "$__iterator")
        LogMsg "Warning synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]} is unusable"
    fi
done

if [ ${#SYNTH_NET_INTERFACES[@]} -eq  ${#__invalid_positions[@]} ]; then
    msg="ERROR: No usable synthetic interface remains"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

# Reset iterator and remove invalid positions from array
__iterator=0
while [ $__iterator -lt ${#__invalid_positions[@]} ]; do
    # Eliminate from SYNTH_NET_INTERFACES array the interface located on position ${__invalid_positions[$__iterator]}
    SYNTH_NET_INTERFACES=("${SYNTH_NET_INTERFACES[@]:0:${__invalid_positions[$__iterator]}}" "${SYNTH_NET_INTERFACES[@]:$((${__invalid_positions[$__iterator]}+1))}")
    : $((__iterator++))
done

# Delete array
unset __invalid_positions

if [ 0 -eq ${#SYNTH_NET_INTERFACES[@]} ]; then
    msg="ERROR: This should not have happened. Probable internal error"
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
        # Add some interface output
        LogMsg "$(ip -o addr show ${SYNTH_NET_INTERFACES[$__iterator]} | grep -vi inet6)"

        # Set default gateway if specified
        if [ -n "$GATEWAY" ]; then
            LogMsg "Setting $GATEWAY as default gateway on dev ${SYNTH_NET_INTERFACES[$__iterator]}"
            CreateDefaultGateway "$GATEWAY" "${SYNTH_NET_INTERFACES[$__iterator]}"
            if [ 0 -ne $? ]; then
                LogMsg "Warning! Failed to set default gateway!"
            fi
        fi

        LogMsg "Trying to ping $REMOTE_SERVER"
        sleep 20

        # Ping the remote host using an easily distinguishable pattern 0xcafed00d`null`copy`null`dhcp`null`
        ping -I "${SYNTH_NET_INTERFACES[$__iterator]}" -c 10 -p "cafed00d00636f7079006468637000" "$STATIC_IP2" >/dev/null 2>&1
        if [ 0 -eq $? ]; then
            LogMsg "Successfully pinged $STATIC_IP2 through synthetic ${SYNTH_NET_INTERFACES[$__iterator]} (dhcp)."
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

# Check if there is any interface capable of pinging remote_vm
if [ ${#SYNTH_NET_INTERFACES[@]} -eq  ${#__invalid_positions[@]} ]; then
    # Delete array
    unset __invalid_positions
    # Try using static IPs
    declare -ai __invalid_positions
    __iterator=0
    # Set synthetic interface address to $STATIC_IP
    while [ $__iterator -lt ${#SYNTH_NET_INTERFACES[@]} ]; do
        SetIPstatic "$STATIC_IP" "${SYNTH_NET_INTERFACES[$__iterator]}" "$NETMASK"

        if [ 0 -eq $? ]; then
            LogMsg "Successfully assigned $STATIC_IP ($NETMASK) to synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}"

            # Set default gateway if specified
            if [ -n "$GATEWAY" ]; then
                LogMsg "Setting $GATEWAY as default gateway on dev ${SYNTH_NET_INTERFACES[$__iterator]}"
                CreateDefaultGateway "$GATEWAY" "${SYNTH_NET_INTERFACES[$__iterator]}"
                if [ 0 -ne $? ]; then
                    LogMsg "Warning! Failed to set default gateway!"
                fi
            fi
            # Ping the remote vm using an easily distinguishable pattern 0xcafed00d`null`cop`null`static`null`
            ping -I "${SYNTH_NET_INTERFACES[$__iterator]}" -c 10 -p "cafed00d00636f700073746174696300" "$STATIC_IP2" >/dev/null 2>&1

            if [ 0 -eq $? ]; then
                break
            else
                LogMsg "Unable to ping $STATIC_IP2 through ${SYNTH_NET_INTERFACES[$__iterator]}"
            fi
        else
            LogMsg "Unable to set static IP to interface ${SYNTH_NET_INTERFACES[$__iterator]}"
        fi
        # Shut interface down
        ip link set ${SYNTH_NET_INTERFACES[$__iterator]} down
        __invalid_positions=("${__invalid_positions[@]}" "$__iterator")
        : $((__iterator++))
    done

    # If no interface was capable of pinging the STATIC_IP2 by having its IP address statically assigned, give up
    if [ $__iterator -eq ${#SYNTH_NET_INTERFACES[@]} ]; then
        msg="ERROR: Not even with static IPs was any interface capable of pinging $STATIC_IP2 . Failed..."
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 40
    fi
else
    # Reset iterator and remove invalid positions from array
    __iterator=0
    while [ $__iterator -lt ${#__invalid_positions[@]} ]; do
        # Eliminate from SYNTH_NET_INTERFACES array the interface located on position ${__invalid_positions[$__iterator]}
        SYNTH_NET_INTERFACES=("${SYNTH_NET_INTERFACES[@]:0:${__invalid_positions[$__iterator]}}" "${SYNTH_NET_INTERFACES[@]:$((${__invalid_positions[$__iterator]}+1))}")
        : $((__iterator++))
    done
fi

# Delete array
unset __invalid_positions

if [ 0 -eq ${#SYNTH_NET_INTERFACES[@]} ]; then
    msg="ERROR: This should not have happened. Probable internal error above line $LINENO"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 100
fi

LogMsg "Successfully pinged $STATIC_IP2 on synthetic interface(s) ${SYNTH_NET_INTERFACES[@]}"

# Get file size in bytes
declare -i __file_size

if [ "${FILE_SIZE_GB:-UNDEFINED}" = "UNDEFINED" ]; then
    # Default size 1 GB
    __file_size=$((1024*1024*1024))                      
else
    __file_size=$((FILE_SIZE_GB*1024*1024*1024))
fi

LogMsg "Checking for local disk space"

# Check disk size on local vm
IsFreeSpace "$HOME" "$__file_size"

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
    msg="ERROR: Cannot copy utils.sh to $STATIC_IP2:/tmp"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

remote_home=$(ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "
    . /tmp/utils.sh
    IsFreeSpace \"\$HOME\" $__file_size
    if [ 0 -ne \$? ]; then
        exit 1
    fi
    echo \"\$HOME\"
    exit 0
    ")

# Get ssh status
sts=$?

if [ 1 -eq $sts ]; then
    msg="ERROR: Not enough free space on $STATIC_IP2 to create the test file"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

# If status is neither 1, nor 0 then ssh encountered an error
if [ 0 -ne $sts ]; then
    msg="ERROR: Unable to connect through ssh to $STATIC_IP2"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

LogMsg "Enough free space remotely to create the file"

# Get source to create the file

if [ "${ZERO_FILE:-UNDEFINED}" = "UNDEFINED" ]; then
    file_source=/dev/urandom
else
    file_source=/dev/zero
fi

# Create file locally with PID appended
output_file=large_file_$$
if [ -d "$HOME"/"$output_file" ]; then
    rm -rf "$HOME"/"$output_file"
fi

if [ -e "$HOME"/"$output_file" ]; then
    rm -f "$HOME"/"$output_file"
fi

dd if=$file_source of="$HOME"/"$output_file" bs=1M count=$((__file_size/1024/1024))

if [ 0 -ne $? ]; then
    msg="ERROR: Unable to create file $output_file in $HOME"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

LogMsg "Successfully created $output_file"

# Compute md5sum
local_md5sum=$(md5sum $output_file | cut -f 1 -d ' ')

# Try to set mtu to 9000 on both VMs
# All synthetic interfaces will have the same mtu
declare -i __max_mtu=0
declare -i __current_mtu=0
declare -i __const_max_mtu=9000
declare -i __const_increment_size=1500
declare -i __max_set=0
__iterator=0

for __iterator in ${!SYNTH_NET_INTERFACES[@]}; do

    while [ "$__current_mtu" -lt "$__const_max_mtu" ]; do
        sleep 2
        __current_mtu=$((__current_mtu+__const_increment_size))

        ip link set dev "${SYNTH_NET_INTERFACES[$__iterator]}" mtu "$__current_mtu"

        if [ 0 -ne $? ]; then
            # We reached the maximum mtu for this interface. break loop
            __current_mtu=$((__current_mtu-__const_increment_size))
            break
        fi

        # Make sure mtu was set. otherwise, set test to failed
        __actual_mtu=$(ip -o link show "${SYNTH_NET_INTERFACES[$__iterator]}" | cut -d ' ' -f5)

        if [ x"$__actual_mtu" != x"$__current_mtu" ]; then
            msg="ERROR: Set mtu on interface ${SYNTH_NET_INTERFACES[$__iterator]} to $__current_mtu but ip reports mtu to be $__actual_mtu"
            LogMsg "$msg"
            UpdateSummary "$msg"
            SetTestStateFailed
            exit 10
        fi

    done

    LogMsg "Successfully set mtu to $__current_mtu on interface ${SYNTH_NET_INTERFACES[$__iterator]}"

    # Update max mtu to the maximum of the first interface
    if [ "$__max_set" -eq 0 ]; then
        __max_mtu="$__current_mtu"
        # All subsequent __current_mtu must be equal to the max of the first one
        __max_set=1
    fi

    if [ "$__max_mtu" -ne "$__current_mtu" ]; then
        msg="ERROR: Maximum mtu for interface ${SYNTH_NET_INTERFACES[$__iterator]} is $__current_mtu but maximum mtu for previous interfaces is $__max_mtu"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 10
    fi

    # Reset __current_mtu for next interface
    __current_mtu=0

done

# Reset iterator
__iterator=0

# If SSH_PRIVATE_KEY was specified, ssh into the STATIC_IP2 and set the MTU of all interfaces to $__max_mtu
# If not, assume that it was already set.
if [ "${SSH_PRIVATE_KEY:-UNDEFINED}" != "UNDEFINED" ]; then
    LogMsg "Setting all interfaces on $STATIC_IP2 mtu to $__max_mtu"
    ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" "
		__remote_interface=\$(ip -o addr show | grep \"$STATIC_IP2\" | cut -d ' ' -f2)
		if [ x\"\$__remote_interface\" = x ]; then
			exit 1
		fi

		# make sure no legacy interfaces are present
		__legacy_interface_no=\$(find /sys/devices -name net -a ! -path '*vmbus*' -a ! -path '*virtual*' -a ! -path '*lo*' | wc -l)

		if [ 0 -ne \"\$__legacy_interface_no\" ]; then
			exit 2
		fi

		ip link set dev \$__remote_interface mtu \"$__max_mtu\"
		if [ 0 -ne \$? ]; then
			exit 2
		fi

		__remote_actual_mtu=\$(ip -o link show \"\$__remote_interface\" | cut -d ' ' -f5)

		if [ x\"\$__remote_actual_mtu\" !=  x\"$__max_mtu\" ]; then
			exit 3
		fi

		exit 0
		"

    if [ 0 -ne $? ]; then
        msg="ERROR: Unable to set $STATIC_IP2 mtu to $__max_mtu"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 10
    fi

fi

# Send file to remote_vm
expect -c "
    spawn scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" "$output_file" "$REMOTE_USER"@"$STATIC_IP2":"$remote_home"/"$output_file"
    expect -timeout -1 \"stalled\" {close}
    interact
" > expect.log

 if grep -q stalled "expect.log"; then
    msg="ERROR: File copy stalled!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
 fi

LogMsg "Successfully sent $output_file to $STATIC_IP2:$remote_home/$output_file"

# Compute md5sum of remote file
remote_md5sum=$(ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no "$REMOTE_USER"@"$STATIC_IP2" md5sum $output_file | cut -f 1 -d ' ')

# Check md5sums
if [ "$local_md5sum" != "$remote_md5sum" ]; then
    [ $NO_DELETE -eq 0 ] && rm -f "$HOME"/$output_file
    msg="ERROR: md5sums differ. Files do not match"
    LogMsg "$msg"
    UpdateSummary "$msg"
    SetTestStateFailed
    exit 10
fi

# Erase file locally, if set
[ $NO_DELETE -eq 0 ] && rm -f $output_file

UpdateSummary "Checksums of file match. Test successful"
LogMsg "Updating test case state to completed"
SetTestStateCompleted
exit 0
