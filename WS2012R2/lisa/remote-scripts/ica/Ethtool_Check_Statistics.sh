#!/bin/bash
############################################################################
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
#############################################################################
#############################################################################
#
# Ethtool_Check_Statistics.sh
# Description:
#       1. Add new Private NIC and set static IP for test interface.
#       2. Check for ethtool and netperf.
#       3. Start first test on 'tx_send_full' param with netperf TCP_SENDFILE.
#       4. Start the second test on 'wake_queue' param with changing mtu for 10 times.
#       5. Check if results are as expected.
#############################################################################
ICA_TESTRUNNING="TestRunning"
ICA_TESTSKIPPED="TestSkipped"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTFAILED="TestFailed"
ICA_TESTABORTED="TestAborted"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}
}

UpdateSummary()
{
    echo -e $1 >> ~/summary.log
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

SendFile(){
	#Download netperf 2.7.0
	wget https://github.com/HewlettPackard/netperf/archive/netperf-2.7.0.tar.gz > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		msg="Error: Unable to download netperf."
		LogMsg "$msg"
		UpdateSummary "$msg"
		return 1
	fi
	tar -xvf netperf-2.7.0.tar.gz > /dev/null 2>&1

	#Get the root directory of the tarball
	rootDir="netperf-netperf-2.7.0"
	LogMsg "rootDir = ${rootDir}"
	cd ${rootDir}

	#Distro specific setup
	GetDistro

	case "$DISTRO" in
	debian*|ubuntu*)
		service ufw status
		if [ $? -ne 3 ]; then
			LogMsg "Disabling firewall on Ubuntu.."
			iptables -t filter -F
			if [ $? -ne 0 ]; then
				msg=""Error: Failed to stop ufw.""
				LogMsg "${msg}"
				UpdateSummary "${msg}"
				return 1
			fi
			iptables -t nat -F
			if [ $? -ne 0 ]; then
				msg="Error: Failed to stop ufw."
				LogMsg "${msg}"
				UpdateSummary "${msg}"
				return 1
			fi
		fi;;
	redhat_5|redhat_6)
		LogMsg "Check iptables status on RHEL."
		service iptables status
		if [ $? -ne 3 ]; then
			LogMsg "Disabling firewall on Redhat.."
			iptables -t filter -F
			if [ $? -ne 0 ]; then
				msg="Error: Failed to flush iptables rules."
				LogMsg "${msg}"
				UpdateSummary "${msg}"
				return 1
			fi
			iptables -t nat -F
			if [ $? -ne 0 ]; then
				msg="Error: Failed to flush iptables nat rules."
				LogMsg "${msg}"
				UpdateSummary "${msg}"
				return 1
			fi
			ip6tables -t filter -F
			if [ $? -ne 0 ]; then
				msg="Error: Failed to flush ip6tables rules."
				LogMsg "${msg}"
				UpdateSummary "${msg}"
				return 1
			fi
			ip6tables -t nat -F
			if [ $? -ne 0 ]; then
				msg="Error: Failed to flush ip6tables nat rules."
				LogMsg "${msg}"
				UpdateSummary "${msg}"
				return 1
			fi
		fi;;
	redhat_7)
		LogMsg "Check iptables status on RHEL."
		systemctl status firewalld
		if [ $? -ne 3 ]; then
			LogMsg "Disabling firewall on Redhat 7.."
			systemctl disable firewalld
			if [ $? -ne 0 ]; then
				msg="Error: Failed to stop firewalld."
				LogMsg "${msg}"
				UpdateSummary "${msg}"
				return 1
			fi
			systemctl stop firewalld
			if [ $? -ne 0 ]; then
				msg="Error: Failed to turn off firewalld."
				LogMsg "${msg}"
				UpdateSummary "${msg}"
				return 1
			fi
		fi
		LogMsg "Check iptables status on RHEL 7."
		service iptables status
		if [ $? -ne 3 ]; then
			iptables -t filter -F
			if [ $? -ne 0 ]; then
				msg="Error: Failed to flush iptables rules."
				LogMsg "${msg}"
				UpdateSummary "${msg}"
				return 1
			fi
			iptables -t nat -F
			if [ $? -ne 0 ]; then
				msg="Error: Failed to flush iptables nat rules."
				LogMsg "${msg}"
				UpdateSummary "${msg}"
				return 1
			fi
			ip6tables -t filter -F
			if [ $? -ne 0 ]; then
				msg="Error: Failed to flush ip6tables rules."
				LogMsg "${msg}"
				UpdateSummary "${msg}"
				return 1
			fi
			ip6tables -t nat -F
			if [ $? -ne 0 ]; then
				msg="Error: Failed to flush ip6tables nat rules."
				LogMsg "${msg}"
				UpdateSummary "${msg}"
				return 1
			fi
		fi;;
	suse_12)
		LogMsg "Check iptables status on SLES."
		service SuSEfirewall2 status
		if [ $? -ne 3 ]; then
			iptables -F;
			if [ $? -ne 0 ]; then
				msg="Error: Failed to flush iptables rules."
				LogMsg "${msg}"
				UpdateSummary "${msg}"
				return 1
			fi
			service SuSEfirewall2 stop
			if [ $? -ne 0 ]; then
				msg="Error: Failed to stop iptables."
				LogMsg "${msg}"
				UpdateSummary "${msg}"
				return 1
			fi
			chkconfig SuSEfirewall2 off
			if [ $? -ne 0 ]; then
				msg="Error: Failed to turn off iptables."
				LogMsg "${msg}"
				UpdateSummary "${msg}"
				return 1
			fi
			iptables -t filter -F
			iptables -t nat -F
		fi;;
	esac

	./configure > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		msg="Error: Unable to configure make file for netperf."
		LogMsg "${msg}"
		UpdateSummary "${msg}"
		return 1
	fi

	make > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		msg="Error: Unable to build netperf."
		LogMsg "${msg}"
		UpdateSummary "${msg}"
		return 1
	fi

	make install > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		msg="Error: Unable to install netperf."
		LogMsg "${msg}"
		UpdateSummary "${msg}"
		return 1
	fi

	LogMsg "Copy files to dependency vm: ${STATIC_IP2}"
	scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ~/netperf_server.sh ${REMOTE_USER}@[${STATIC_IP2}]: > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		msg="Error: Unable to copy test scripts to dependency VM: ${STATIC_IP2}. scp command failed."
		LogMsg "${msg}"
		UpdateSummary "${msg}"
		return 1
	fi
	scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ~/constants.sh ${REMOTE_USER}@[${STATIC_IP2}]: > /dev/null 2>&1
	scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ~/utils.sh ${REMOTE_USER}@[${STATIC_IP2}]: > /dev/null 2>&1

	#Start netperf in server mode on the dependency vm
	LogMsg "Starting netperf in server mode on ${STATIC_IP2}"
	ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ${REMOTE_USER}@${STATIC_IP2} "echo '~/netperf_server.sh > netperf_ServerScript.log' | at now" > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		msg="Error: Unable to start netperf server script on the dependency vm."
		LogMsg "${msg}"
		UpdateSummary "${msg}"
		return 1
	fi

	#Wait for server to be ready
	wait_for_server=600
	server_state_file=serverstate.txt
	while [ $wait_for_server -gt 0 ]; do
		#Try to copy and understand server state
		scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ${REMOTE_USER}@[${STATIC_IP2}]:~/state.txt ~/${server_state_file} > /dev/null 2>&1

		if [ -f ~/${server_state_file} ]; then
			server_state=$(head -n 1 ~/${server_state_file})
			if [ "$server_state" == "netperfRunning" ]; then
				break
			elif [[ "$server_state" == "TestFailed" || "$server_state" == "TestAborted" ]]; then
				msg="Running netperf_server.sh was aborted or failed on dependency vm:$server_state"
				LogMsg "$msg"
				UpdateSummary "$msg"
				return 1
			elif [ "$server_state" == "TestRunning" ]; then
				continue
			fi
		fi
		sleep 5
		wait_for_server=$(($wait_for_server - 5))
	done

	if [ $wait_for_server -eq 0 ]; then
		msg="Error: netperf server script has been triggered but is not in running state within ${wait_for_server} seconds."
		LogMsg "${msg}"
		UpdateSummary "${msg}"
		return 1
	else
		LogMsg "SUCCESS: Netperf server is ready."
	fi

	#create 4GB file test for TCP_SENDFILE test
	dd if=/dev/zero of=test1 bs=1M count=4096

	LogMsg "Starting netperf .."
	netperf -H ${STATIC_IP2} -F test1 -t TCP_SENDFILE -l 300 -- -m 1 & > netperf.log 2>&1
	if [ $? -ne 0 ]; then
		msg="Error: Unable to run netperf on VM."
		LogMsg "$msg"
		UpdateSummary "$msg"
		return 1
	fi
	sleep 310

	#Get the modified value of 'tx_send_full' param after netpef test 
	new_send_value=$(ethtool -S ${SYNTH_NET_INTERFACES[$__iterator]} | grep "tx_send_full" | cut -d ":" -f 2)

	#LogMsg values
	UpdateSummary "Kernel: $(uname -r)."
	LogMsg "Tx_send_full before netperf test: $send_value."
	LogMsg "Tx_send_full after netperf test: $new_send_value."
	UpdateSummary "Tx_send_full after netperf test: $new_send_value."
	#Check results
	if [ $new_send_value -gt 10 ]; then
		msg="Successfully test on tx_send_full param."
		LogMsg "$msg"
		UpdateSummary "$msg"
		return 0
	else
		msg="Error: test on tx_send_full param failed."
		LogMsg "$msg"
		UpdateSummary "$msg"
		return 1
	fi
}

ChangeMTU(){
	declare -i _iterator2=10
	declare -i __current_mtu=0
	declare -i __const_max_mtu=61440
	declare -i __const_increment_size=4096
	while [ $_iterator2 -gt 0 ]; do
		if [ "$__current_mtu" -lt "$__const_max_mtu" ]; then
			sleep 2
			__current_mtu=$((__current_mtu+__const_increment_size))

			ip link set dev "${SYNTH_NET_INTERFACES[$__iterator]}" mtu "$__current_mtu"
			if [ 0 -ne $? ]; then
				#we reached the maximum mtu for this interface. break loop
				__current_mtu=$((__current_mtu-__const_increment_size))
				break
			fi

			#make sure mtu was set. Otherwise, set test to failed.
			__actual_mtu=$(ip -o link show "${SYNTH_NET_INTERFACES[$__iterator]}" | cut -d ' ' -f5)
			if [ x"$__actual_mtu" != x"$__current_mtu" ]; then
				msg="Set mtu on interface ${SYNTH_NET_INTERFACES[$__iterator]} to $__current_mtu but ip reports mtu to be $__actual_mtu."
				LogMsg "$msg"
				UpdateSummary "$msg"
				return 1
			fi
			_iterator2=$(($_iterator2-1))
			LogMsg "Successfully set mtu to $__current_mtu on interface ${SYNTH_NET_INTERFACES[$__iterator]}"
		fi
	done

	#Get the value of 'wake_queue' after changing MTU
	new_wake_value=$(ethtool -S ${SYNTH_NET_INTERFACES[$__iterator]} | grep "wake_queue" | cut -d ":" -f 2)

	#Log the values
	LogMsg "Wake_queue start value: $wake_value"
	LogMsg "Wake_queue value after changing MTU: $new_wake_value"
	UpdateSummary "Wake_queue value after changing MTU: $new_wake_value"

	if [ $new_wake_value -eq 10 ]; then
		msg="Successfully test on wake_queue param."
		LogMsg "$msg"
		UpdateSummary "$msg"
		return 0
	else
		msg="Error: test on wake_queue param failed."
		LogMsg "$msg"
		UpdateSummary "$msg"
		return 1
	fi
}

#######################################################################
#
# Main script body
#
#######################################################################

#Create the state.txt file so ICA knows we are running
UpdateTestState $ICA_TESTRUNNING

#Convert eol
dos2unix utils.sh

#Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    UpdateTestState $ICA_TESTABORTED
    exit 20
}

#Source constants file and initialize most common variables
UtilsInit

#In case of error
case $? in
    0)
        #do nothing, init succeeded
        ;;
    1)
        LogMsg "Unable to cd to $LIS_HOME. Aborting..."
        UpdateSummary "Unable to cd to $LIS_HOME. Aborting..."
        UpdateTestState $ICA_TESTABORTED
        exit 20
        ;;
    2)
        LogMsg "Unable to use test state file."
        UpdateSummary "Unable to use test state file."
        # need to wait for test timeout to kick in
        # hailmary try to update teststate
        sleep 60
        echo "TestAborted" > state.txt
        exit 20
        ;;
    3)
        LogMsg "Error: unable to source constants file. Aborting..."
        UpdateSummary "Error: unable to source constants file. Aborting..."
        UpdateTestState $ICA_TESTABORTED
        exit 20
        ;;
    *)
        # should not happen
        LogMsg "UtilsInit returned an unknown error. Aborting..."
        UpdateSummary "UtilsInit returned an unknown error. Aborting..."
        UpdateTestState $ICA_TESTABORTED
        exit 20
        ;;
esac


#Make sure the required test parameters are defined

if [ "${STATIC_IP:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: The STATIC_IP test parameter is missing."
    LogMsg "${msg}"
    UpdateSummary "${msg}"
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

if [ "${STATIC_IP2:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: The STATIC_IP2 test parameter is missing."
    LogMsg "${msg}"
    UpdateSummary "${msg}"
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

if [ "${NETMASK:="UNDEFINED"}" = "UNDEFINED" ]; then
    NETMASK="255.255.255.0"
    msg="Warn: The NETMASK test parameter is missing, default value will be used: $NETMASK."
    LogMsg "${msg}"
    UpdateSummary "${msg}"
fi

#Get test synthetic interface
declare __iface_ignore

# Parameter provided in constants file
#   ipv4 is the IP Address of the interface used to communicate with the VM, which needs to remain unchanged
#   it is not touched during this test (no dhcp or static ip assigned to it)

if [ "${ipv4:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter ipv4 is not defined in constants file!"
    LogMsg "$msg"
    UpdateSummary "$msg"
    UpdateTestState $ICA_TESTABORTED
    exit 20
else
    CheckIP "$ipv4"
    if [ 0 -ne $? ]; then
        msg="Test parameter ipv4 = $ipv4 is not a valid IP Address."
        LogMsg "$msg"
        UpdateSummary "$msg"
        UpdateTestState $ICA_TESTABORTED
        exit 20
    fi

    #Get the interface associated with the given ipv4
    __iface_ignore=$(ip -o addr show | grep "$ipv4" | cut -d ' ' -f2)
fi

#Retrieve synthetic network interfaces
GetSynthNetInterfaces
if [ 0 -ne $? ]; then
    msg="No synthetic network interfaces found."
    LogMsg "$msg"
    UpdateSummary "$msg"
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

#Remove interface if present
SYNTH_NET_INTERFACES=(${SYNTH_NET_INTERFACES[@]/$__iface_ignore/})

if [ ${#SYNTH_NET_INTERFACES[@]} -eq 0 ]; then
    msg="The only synthetic interface is the one which LIS uses to send files/commands to the VM."
    LogMsg "$msg"
    UpdateSummary "$msg"
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

declare -i _iterator=0
if [ ${#SYNTH_NET_INTERFACES[@]} -eq 1 ]; then
    LogMsg "Found ${#SYNTH_NET_INTERFACES[@]} synthetic interface(s): ${SYNTH_NET_INTERFACES[*]} in VM."
    #test interface
    ip link show "${SYNTH_NET_INTERFACES[$__iterator]}" >/dev/null 2>&1
    if [ 0 -ne $? ]; then
        msg="Invalid synthetic interface ${SYNTH_NET_INTERFACES[$__iterator]}."
        LogMsg "$msg"
        UpdateSummary "$msg"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
    #set static IP for test interface
    LogMsg "Trying to set an IP Address via static on interface ${SYNTH_NET_INTERFACES[$__iterator]}."
    CreateIfupConfigFile "${SYNTH_NET_INTERFACES[$__iterator]}" "static" $STATIC_IP $NETMASK
    if [ 0 -ne $? ]; then
        msg="Unable to set address for ${SYNTH_NET_INTERFACES[$__iterator]} through static."
        LogMsg "$msg"
        UpdateSummary "$msg"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
else
    msg="Error: Multiple synthetic interfaces were found on vm. Found ${#SYNTH_NET_INTERFACES[@]} synthetic interface(s): ${SYNTH_NET_INTERFACES[*]} in VM."
    LogMsg "$msg"
    UpdateSummary "$msg"
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

#Check if ethtool exist and install it if not
VerifyIsEthtool

#Check if Statistics from ethtool are available
sts=$(ethtool -S ${SYNTH_NET_INTERFACES[$__iterator]} 2>&1)
if [[ $sts = *"no stats available"* ]]; then
    LogMsg "$sts"
    LogMsg "Operation not supported. Test Skipped."
    UpdateSummary "Operation not supported. Test Skipped."
    UpdateTestState $ICA_TESTSKIPPED
    exit 2
fi 

#Make all bash scripts executable
cd ~
dos2unix ~/*.sh
chmod 755 ~/*.sh

#Start the first test on tx_send_full param with TCP_SENDFILE netperf
#Get the started value of 'tx_send_full' param from statistics if exist and if not skip the test.
send_value=$(ethtool -S ${SYNTH_NET_INTERFACES[$__iterator]} | grep "tx_send_full" | cut -d ":" -f 2)
if [ -n "$send_value" ]; then
    SendFile
    sts_sendfile=$?
else
    msg="SendFile test is Skipped!'Tx_send_full' param not found."
    LogMsg "$msg"
    UpdateSummary "$msg"
    sts_sendfile=2
fi

#Start the second test - on wake_queue param 
#Get the started value of 'wake_queue' param from statistics if exist and if not skip the test.
wake_value=$(ethtool -S ${SYNTH_NET_INTERFACES[$__iterator]} | grep "wake_queue" | cut -d ":" -f 2)
if [ -n "$wake_value" ];then
    ChangeMTU
    sts_changemtu=$?
else
    msg="ChangeMTU test is Skipped!'Wake_queue' param not found."
    LogMsg "$msg"
    UpdateSummary "$msg"
    sts_changemtu=2
fi

#Get logs from dependency vm
scp -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no -r ${REMOTE_USER}@[${STATIC_IP2}]:~/netperf_ServerScript.log ~/netperf_ServerScript.log > /dev/null 2>&1

#Shutdown dependency VM
ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -v -o StrictHostKeyChecking=no ${REMOTE_USER}@${STATIC_IP2} "init 0" > /dev/null 2>&1

if [[ $sts_sendfile -eq 1 || $sts_changemtu -eq 1 ]];then
    UpdateTestState $ICA_TESTFAILED
    exit 1
elif [[ $sts_sendfile -eq 2 && $sts_changemtu -eq 2 ]];then
    UpdateTestState $ICA_TESTSKIPPED
    exit 2
fi

#If we made it here, everything worked
LogMsg "Test completed successfully"
UpdateTestState $ICA_TESTCOMPLETED