#!/bin/bash

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
    constants=(ARCHIVE_URL REMOTE_DIR)
    for var in ${constants[@]};do
        if [[ ${!var} = "" ]];then
            msg="Error: ${var} parameter is null"
            UpdateSummary $msg
        fi
    done
}

function download_artifacts {
    share_url="$1"
    archive_name="kernel-archive.tgz"

    wget -O $archive_name "$share_url"
    tar -xvzf $archive_name
    
    for file in $(find ./tmp -name "kernel*.rpm");do
        cp "$file" .
    done
        
    if [[ $(find *.rpm) == "" ]];then
        msg="Error: Failed to download artifacts."
        UpdateSummary $msg
        UpdateTestState $ICA_TESTABORTED
    fi
}

function install_kernel_rhel {
    rpm -ivh --force --ignorearch *.rpm
    if [[ $? -ne 0 ]];then
        msg="Error: rpm install failed."
        UpdateSummary $msg
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi
    grub2-mkconfig -o /boot/grub2/grub.cfg
    
    kernelName=$(find /boot -name "bzImage-*")
    fileName=${kernelName##*/}
    fileVersion=${fileName#*-}
    linuzName="vmlinuz-${fileVersion}.x86_64"
    cp $kernelName "/boot/$linuzName"
    if [[ $? -ne 0 ]];then
        msg="Error: cp $kernelName $linuzName failed"
        UpdateSummary $msg
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi
    
    grub2-set-default 0
    grub2-mkconfig -o /boot/grub2/grub.cfg
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
    if [[ $DISTRO != "centos"* ]] && [[ $DISTRO != "rhel"* ]];then
        LogMsg "WARNING: Distro '${distro}' not supported."
        UpdateSummary "WARNING: Distro '${distro}' not supported."
    fi

    if [[ -e "./$CONSTANTS_FILE" ]];then
        source ${CONSTANTS_FILE}
        check_constants
    else
        msg="Error: no ${CONSTANTS_FILE} file"
        UpdateSummary $msg
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi
    
    yum install -y wget
    
    if [[ -d "./kernel_temp_dir" ]];then
        rm -rf ./kernel_temp_dir
    fi
    mkdir ./kernel_temp_dir

    pushd ./kernel_temp_dir
    if [[ ! "$REMOTE_DIR" ]];then
        download_artifacts "$ARCHIVE_URL"
    else
        cp ${REMOTE_DIR}/*.rpm .
    fi
    install_kernel_rhel
    popd
    rm -rf ./kernel_temp_dir
    LogMsg "Test completed successfully"
    UpdateTestState $ICA_TESTCOMPLETED
    exit 0
}

main $@