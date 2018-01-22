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

function check_constants {
    constants=(SHARE_URL AZURE_TOKEN KERNEL_FOLDER)
    
    for var in ${constants[@]};do
        if [[ ${!var} = "" ]];then
            msg="Error: ${var} parameter is null"
            UpdateSummary $msg
            UpdateTestState $ICA_TESTABORTED
            exit 1
        fi
    done
}

function download_artifacts {
    share_url="$1"
    azure_token="$2"
    kernel_folder="$3"
    package="$4"

    folder_xml=$(curl "$share_url/$kernel_folder/$package?restype=directory&comp=list&$azure_token")
    artifacts=${folder_xml//<Name>/ }

    for art in $artifacts;do
        line=$(echo $art | grep "</Name>")
        line=${line%</Name>*}
        if [[ "$line" != "" && "$line" != *"dbg"* ]];then
            wget -O $line "$share_url/$kernel_folder/$package/$line?$azure_token"
        fi
    done
    if [[ $(find *.$package) == "" ]];then
        msg="Error: Failed to download artifacts."
        UpdateSummary $msg
        UpdateTestState $ICA_TESTABORTED
    fi
}

function prepare_debian {
    apt install -y curl
}

function prepare_rhel {
    yum install -y curl
}

function install_kernel_debian {
    apt remove -y linux-cloud-tools-common
    dpkg --force-all -i *.deb
    if [[ $? -ne 0 ]];then
        msg="Error: deb install failed."
        UpdateSummary $msg
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi
}

function install_kernel_rhel {
    rpm -i *.rpm
    if [[ $? -ne 0 ]];then
        msg="Error: rpm install failed."
        UpdateSummary $msg
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi
}


function main {
    UpdateTestState $ICA_TESTRUNNING
    
    if [[ -e "./utils.sh" ]];then
        dos2unix utils.sh
        source utils.sh
    else
        msg="Error: no utils.sh file"
        UpdateSummary $msg
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi        
    GetDistro
    case $DISTRO in
    centos* | redhat* | fedora*)
        os_FAMILY="rhel"
        os_PACKAGE="rpm"
    ;;
    ubuntu*)
        os_FAMILY="debian"
        os_PACKAGE="deb"
    ;;
     *)
        LogMsg "WARNING: Distro '${distro}' not supported."
        UpdateSummary "WARNING: Distro '${distro}' not supported."
    ;;
    esac
    
    if [[ -e "./$CONSTANTS_FILE" ]];then
        source ${CONSTANTS_FILE}
        check_constants
    else
        msg="Error: no ${CONSTANTS_FILE} file"
        UpdateSummary $msg
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi
    if [[ -d "./kernel_temp_dir" ]];then
        rm -rf ./kernel_temp_dir
    fi
    mkdir ./kernel_temp_dir
    
    pushd ./kernel_temp_dir
    prepare_${os_FAMILY}
    download_artifacts "$SHARE_URL" "$AZURE_TOKEN" "$KERNEL_FOLDER" "$os_PACKAGE"
    install_kernel_${os_FAMILY}
    popd
    rm -rf ./kernel_temp_dir
    LogMsg "Test completed successfully"
    UpdateTestState $ICA_TESTCOMPLETED
    exit 0
}

main $@
