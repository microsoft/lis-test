#!/bin/bash

PACKAGES="lsb-release sudo build-essential git wget curl gpg gcc gcc-c++ make patch autoconf automake bison libffi-devel libtool patch readline-devel sqlite-devel zlib-devel openssl-devel"
EXCLUDE_TESTS="reaim-hsx.yaml"
ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error while performing the test
WORK_DIR="/build_dir/lkp"

CONSTANTS_FILE="constants.sh"

function install_dependencies {
    packages="$1"
    
    yum update
    yum install -y $packages 
    
    gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
    curl -sSL https://get.rvm.io | bash -s stable
    source /etc/profile.d/rvm.sh
    rvm install 2.5.1
}

LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1}
}

UpdateSummary() {
    echo $1 >> ~/summary.log
}

UpdateTestState() {
    echo $1 > ~/state.txt
}

function copy_logs {
    results_path="$1"
    log_dir="$2"
    test_name="$3"
    
    mkdir "${log_dir}/${test_name}"
    cp ${results_path}* "${log_dir}/${test_name}"
}

function run_tests {
    log_dir="$1"

    git clone https://github.com/fengguang/lkp-tests.git .
    make install
    if [[ $? -ne 0 ]];then
        LogMsg "Error: lkp make failed"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
    yes | lkp install
    if [[ $? -ne 0 ]];then
        LogMsg "Error: lkp deps install failed"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
    
    for test in $(find ./jobs -name "*.yaml");do
        test_path="$test"
        test_file="${test##*/}"
        test_name="${test_file%%.*}"
        
        if [[ $(grep "$test_file" <<< $EXCLUDE_TESTS) ]];then
            UpdateSummary "Test $test_name is excluded"    
            continue
        fi
        
        lkp install $test_path
        lkp run $test_path
        results_path="$(lkp result $test_name)"
        if [[ -d "$results_path" ]];then
            copy_logs "$results_path" "$log_dir" "$test_name"
            UpdateSummary "Test ${test_name} finished successfully"
        else
            echo "${test}" >> "$log_dir/ABORT" 
            UpdateSummary "Test $test_name failed, cannot find any logs"
            continue
        fi
    done
}

function main {
    dos2unix utils.sh
    . utils.sh || {
        echo "ERROR: unable to source utils.sh!"
        echo "TestAborted" > state.txt
        exit 2
    }

    if [ -e ~/summary.log ]; then
        LogMsg "Cleaning up previous copies of summary.log"
        rm -rf ~/summary.log
    fi

    LogMsg "Updating test case state to running"
    UpdateTestState $ICA_TESTRUNNING

    # Source the constants file
    if [ -e ~/${CONSTANTS_FILE} ]; then
        source ~/${CONSTANTS_FILE}
    else
        msg="Error: no ${CONSTANTS_FILE} file"
        echo $msg
        echo $msg >> ~/summary.log
        UpdateTestState $ICA_TESTABORTED
       exit 1
    fi
    
    if [[ ! -e "$WORK_DIR" ]];then
        mkdir -p "$WORK_DIR"
    else
        rm -rf "$WORK_DIR"
    fi
    if [[ "$LOG_DIR" == "" ]];then
        UpdateSummary "Error: No LOG_DIR specified. Exiting"
        UpdateTestState $ICA_TESTABORTED
        exit 1
    fi
    mkdir -p "$LOG_DIR"
    
    if [[ "${PACKAGES}" != "" ]];then
        install_dependencies "$PACKAGES"
    fi
    
    pushd "$WORK_DIR"
    run_tests "$LOG_DIR"
    popd
    
    UpdateTestState $ICA_TESTCOMPLETED
}

main $@







