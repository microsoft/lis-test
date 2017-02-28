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
#     of an Ubuntu test kernel. The following steps are performed:
#	1. Download the test kernel from the URL provided in XML file.
#	2. Install the test kernel
#	3. Matching LIS daemons packages are also installed.
#
#######################################################################

ICA_TESTRUNNING="TestRunning"         # The test is running
ICA_TESTCOMPLETED="TestCompleted"     # The test completed successfully
ICA_TESTABORTED="TestAborted"         # Error during setup of test
ICA_TESTFAILED="TestFailed"           # Error during execution of test

CONSTANTS_FILE="constants.sh"

LogMsg() {
    echo `date "+%a %b %d %T %Y"` ": ${1}"
}

UpdateTestState() {
    echo $1 > ~/state.txt
}

UpdateSummary() {
    echo $1 >> ~/summary.log
}

cd ~
UpdateTestState $ICA_TESTRUNNING

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

# Check if script is running on primary vm or secondary vm
# If constants.sh is present means we're on VM1 
# We'll check for VM2Name param; if it exists, script will be sent & will run on VM2 
# link.sh will be sent by VM1 to VM2 and will contain the test kernel URL 
if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
    cat constants.sh | grep VM2NAME
    willInstall=$?
elif [ -e ~/link.sh ]; then
	source ~/link.sh
else
    msg="Error: no ${CONSTANTS_FILE} or link.sh file"
    UpdateSummary $msg
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

if [ -e ~/summary.log ]; then
    echo "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 1
}

mkdir -p /tmp/test_kernel/
if [ $? -ne 0 ]; then
	UpdateSummary "Error: Unable to create the test directory!"
	UpdateTestState $ICA_TESTABORTED
fi

if [ "${URL:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the test kernel URL parameter is missing!"
    LogMsg "${msg}"
    UpdateSummary "${msg}"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

if is_ubuntu ; then
	LogMsg "Downloading files (silent mode)..."
	cd /tmp/test_kernel/
	for file in $(curl -s $URL/ |
				grep href |
				sed 's/.*href="//' |
				sed 's/".*//' |
				grep '^[a-zA-Z].*'); do
		curl -s -O $URL/$file
	done

	LogMsg "Installing packages..."
	dpkg -i linux-image*
	if [[ $? -ne 0 ]]; then
		UpdateSummary "Error: Unable to install the test kernel!"
		UpdateTestState $ICA_TESTABORTED
		exit 1
	fi
	UpdateSummary "Info: Kernel package has been successfully installed!"
	
	dpkg -i linux-tools*
	dpkg -i linux-cloud-tools*
	if [[ $? -ne 0 ]]; then
		UpdateSummary "Error: Unable to install the proposed LIS daemons packages!"
		UpdateTestState $ICA_TESTABORTED
		exit 1
	fi
	UpdateSummary "Info: linux-tools and linux-cloud-tools have been successfully installed!"

	dpkg -i linux-headers*
	if [[ $? -ne 0 ]]; then
		UpdateSummary "Error: Unable to install the new kernel headers!"
		UpdateTestState $ICA_TESTABORTED
		exit 1
	fi

	# Modify grub so it will boot with the test kernel
	version=$(ls -1 linux-image-extra* | sed -r 's/^.{18}//' | cut -f1 -d"_")
	LogMsg "New kernel version: $version"
	sed -i.bak 's/GRUB_DEFAULT=.*/GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux '$version'"/g' /etc/default/grub
	update-grub
	
	# Send the script on the secondary vm if it's the case
	if [ $willInstall -eq 0 ]; then
		scp -i ~/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no ~/ubuntu_test_kernel.sh "$SERVER_OS_USERNAME"@"$STATIC_IP2":~/ubuntu_test_kernel.sh
	    if [ 0 -ne $? ]; then
	        msg="ERROR: Unable to send the file from VM1 to VM2"
	        LogMsg "$msg"
	        UpdateSummary "$msg"
	        UpdateTestState $ICA_TESTFAILED
	        exit 1
	    fi

		scp -i ~/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no ~/utils.sh "$SERVER_OS_USERNAME"@"$STATIC_IP2":~/utils.sh
	    if [ 0 -ne $? ]; then
	        msg="ERROR: Unable to send utils.sh from VM1 to VM2"
	        LogMsg "$msg"
	        UpdateSummary "$msg"
	        UpdateTestState $ICA_TESTFAILED
	        exit 1
	    fi

	    ssh -i ~/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$SERVER_OS_USERNAME"@"$STATIC_IP2" "echo 'URL=${URL}' >> ~/link.sh"
	    if [ $? -ne 0 ]; then
	        msg="ERROR: Could not create link.sh on VM2!"
	        LogMsg "$msg"
	        UpdateSummary "$msg"
	        UpdateTestState $ICA_TESTFAILED
	        exit 1
	    fi

	    ssh -i ~/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$SERVER_OS_USERNAME"@"$STATIC_IP2" bash ~/ubuntu_test_kernel.sh
	    if [ $? -ne 0 ]; then
	        msg="ERROR: Script failed on secondary vm"
	        LogMsg "$msg"
	        UpdateSummary "$msg"
	        UpdateTestState $ICA_TESTFAILED
	        exit 1
	    fi

        ssh -i ~/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$SERVER_OS_USERNAME"@"$STATIC_IP2" init 0
	    LogMsg "Kernel install completed successfully on VM2"
	fi

	LogMsg "Test completed successfully"
	UpdateTestState $ICA_TESTCOMPLETED
	exit 0
fi
