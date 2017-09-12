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

#######################################################################
#
# Description:
#     This script was created to automate the installation and validation
#     of the latest SLES kernel. The following steps are performed:
#	1. Verify if the system is registered with Novell. Register if not.
#	2. Search for the latest kernel available online.
#	3. Matching LIS daemons package is also installed if available.
#
#######################################################################



#Verify if is registered and register if not
#
function checkActive {
    SUSEConnect --status-text | grep -i 'Active'
    if [[ $? -ne 0 ]]; then
        LogMsg "Not Registered. Will be activated... "
        SUSEConnect -r $password -e $username
		if [[ $? -ne 0 ]]; then
		    msg="Error: Could not register vm"
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateAborted
		else
		    LogMsg "VM registered"
		fi		
    fi
}


#refresh repositories
#check if exist updates for kernel and installing if exist
#Changing grub config to boot the proposed kernel
#
function verfKernel {
    LogMsg "Refreshing repositories....."
    zypper refresh 
	if [[ $? -ne 0 ]]; then
	    msg="Error: Could not refresh repositories"
		LogMsg "$msg"
		UpdateSummary "$msg"
		SetTestStateAborted
	fi	
    status=$(zypper info kernel-default | grep -i status | awk '{print $3}')
    if [[ $status == 'out-of-date' ]]; then
	    zypper -n update kernel-default
	    if [[ $? -ne 0 ]]; then
            msg="Error: Kernel could not be installed"
			LogMsg "$msg"
		    UpdateSummary "$msg"
			SetTestStateFailed
			exit 1
		else
		    LogMsg "Kernel updated!"
        fi				
	    version=$(zypper info kernel-default | grep -i version | awk '{print $3}')
		version=${version::-2}
		sles_version=$(awk -F' *= *' '$1=="VERSION"{gsub(/"/,"",$2); print $2 }' /etc/os-release)
	    LogMsg "Set to boot the proposed kernel..."
	    LogMsg "Advanced options for SLES $sles_version>SLES $sles_version, with Linux $version-default"
	    grub2-set-default "Advanced options for SLES $sles_version>SLES $sles_version, with Linux $version-default"
	    grub2-mkconfig -o /boot/grub2/grub.cfg
		if [[ $? -ne 0 ]]; then
		    msg="Error: Could not set to boot the new kernel"
			LogMsg "$msg"
			UpdateSummary "$msg"
			SetTestStateFailed
			exit 1
		else
		    UpdateSummary "Found a new kernel : ${version}"
			UpdateSummary "New kernel has been successfully installed and set to boot!"
		fi		
	else
	    msg="Kernel up-to-date! Nothing to do!"
	    LogMsg "$msg"
		UpdateSummary "$msg"
    fi
}


#check if exist updates LIS hyper-v modules and installing if exist
#
function verfHyper {
    LogMsg "Checking for the latest version of Hyper-V tools..."
	status=$(zypper info hyper-v | grep -i status | awk '{print $3}')
    if [[ $status == 'out-of-date' ]]; then
	    zypper -n update hyper-v
		if [[ $? -ne 0 ]]; then
             msg="Error: Hyper-V tools could not be installed"
			 LogMsg "$msg"
			 UpdateSummary "$msg"
			 SetTestStateFailed
			 exit 1
		else
		    LogMsg "Hyper-V tools updated!"
			UpdateSummary "Hyper-V tools updated!"
		fi
	else  
	    msg="Hyper-V tools up-to-date! Nothing to do!"
	    LogMsg "$msg"
		UpdateSummary "$msg"		
	fi
}


#Source utils.sh
#
dos2unix utils.sh
. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}
UtilsInit

checkActive
verfKernel
verfHyper


SetTestStateCompleted
exit 0
