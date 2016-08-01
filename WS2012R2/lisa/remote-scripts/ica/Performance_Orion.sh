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
############################################################################

############################################################################
#
# Performance_Orion.sh
#
# Description:
#     For the test to run you have to place the orion_linux_x86-64.gz archive in the
#     Tools folder under lisa.
#      
#      For the test to run  you have attach a PassThrough disk on SSD.
#
# Parameters:
#     TOTAL_DISKS: Number of disks attached
#     TEST_DEVICE1 = /dev/sdb
#
############################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the time-stamp to the log file
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

LinuxRelease()
{
    DISTRO=`grep -ihs "buntu\|Suse\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux" /etc/{issue,*release,*version}`

    case $DISTRO in
        *buntu*)
            echo "UBUNTU";;
        Fedora*)
            echo "FEDORA";;
        CentOS*)
            echo "CENTOS";;
        *SUSE*)
            echo "SLES";;
        Red*Hat*)
            echo "RHEL";;
        Debian*)
            echo "DEBIAN";;
    esac
}

#
# Create the state.txt file so ICA knows we are running
#
LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

#
# Source the constants.sh file
#
if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    echo "Warn : no ${CONSTANTS_FILE} found"
fi

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

#
# Check if variable is defined in the constants file
#
if [ ! ${TOTAL_DISKS} ]; then
    LogMsg "The TOTAL_DISKS variable is not defined."
    echo "The TOTAL_DISKS variable is not defined." >> ~/summary.log
    LogMsg "aborting the test."
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

echo " Kernel version: $(uname -r)" >> ~/summary.log

sleep 2
NEW_DISK=$(fdisk -l | grep "Disk /dev/sd*" | wc -l)
NEW_DISK=$((NEW_DISK-1))
if [ "$NEW_DISK" = "$TOTAL_DISKS" ] ; then
    LogMsg "Result : New disk is present inside guest VM "
    LogMsg " fdisk -l is : "
    fdisk -l    
else
    LogMsg "Result : New disk is not present in Guest VM "
    UpdateTestState $ICA_TESTFAILED
    LogMsg "Result : Number of new disks inside guest VM is $NEW_DISK"
    echo "Result : Number of new disks inside guest VM is $NEW_DISK" >> ~/summary.log
    LogMsg " fdisk -l is : "
    fdisk -l
    exit 40
fi

case $(LinuxRelease) in
    "UBUNTU")
        LogMsg "Run test on Ubuntu. Install dependencies..."
        apt-get -y install make gcc libaio-dev sysstat
        sts=$?
        if [ 0 -ne ${sts} ]; then
            echo "Failed to install the dependency packages!" >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
            exit 41
        fi

        FS="ext4"
        
        # Disable multipath so that it doesn't lock the disks
         if [ -e /etc/multipath.conf ]; then
            rm /etc/multipath.conf
        fi
        echo -e "blacklist {\n\tdevnode \"^sd[a-z]\"\n}" >> /etc/multipath.conf
        service multipath-tools reload
        service multipath-tools restart 

    ;;
    "RHEL"|"CENTOS")
        LogMsg "Run test on RHEL. Install libaio-devel..."
        yum -y install libaio-devel sysstat
        sts=$?
        if [ 0 -ne ${sts} ]; then
            echo "Failed to install the dependency packages!" >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
            exit 41
        fi

        FS="ext4"
    ;;
    "SLES")
        LogMsg "Run test on SLES. Install libaio-devel..."
        zypper --non-interactive install libaio-devel
        sts=$?
        if [ 0 -ne ${sts} ]; then
            echo "Failed to install the dependency packages!" >> ~/summary.log
            UpdateTestState $ICA_TESTABORTED
            exit 41
        fi
        FS="ext4"
    ;;
     *)
        FS="ext4"
    ;; 
esac

i=1
while [ $i -le $TOTAL_DISKS ]
do
    j=TEST_DEVICE$i
    if [ ${!j:-UNDEFINED} = "UNDEFINED" ]; then
        LogMsg "Error: constants.sh did not define the variable $j"
        UpdateTestState $ICA_TESTABORTED
        exit 50
    fi

    LogMsg "TEST_DEVICE = ${!j}"
    echo "Target device = ${!j}" >> ~/summary.log
    DISK=`echo ${!j} | cut -c 6-8`

# Format and mount the disk
    (echo d;echo;echo w)|fdisk /dev/$DISK
    sleep 2
    (echo n;echo p;echo 1;echo;echo;echo w)|fdisk /dev/$DISK
    sleep 5
    mkfs.${FS} /dev/${DISK}1
    if [ "$?" = "0" ]; then
        LogMsg "mkfs.$FS /dev/${DISK}1 successful..."
        mount /dev/${DISK}1 /mnt
        if [ "$?" = "0" ]; then
            LogMsg "Drive mounted successfully..."    
        else
            LogMsg "Error in mounting drive..."
            echo "Drive mount : Failed" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 70
        fi
    else
            LogMsg "Error in creating file system.."
            echo "Creating Filesystem : Failed" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 80
    fi
    i=$[$i+1]
done

#
# Install ORION and check if the installation is successful
#
ORION=/root/${FILE_NAME}

if [ ! -e ${ORION} ];
then
    echo "Cannot find ORION test source file." >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 20
fi

gunzip -f ${ORION}
sts=$?
if [ 0 -ne ${sts} ]; then
    echo "Failed to extract the ORION archive!" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi
 
#Make Orion executable
chmod 755 orion_linux_x86-64

LogMsg "ORION was installed successfully!"

#Create .lun file
echo "/dev/sdb" > /root/$ORION_SCENARIO_FILE.lun
mkdir -p /root/benchmark/orion
sts=$?
if [ ${sts} -ne 0 ]; then
    echo "WARNING: Unable to create Orion directory for iostat logs."  >> ~/summary.log
    LogMsg "WARNING: Unable to create Orion directory for iostat logs."
    UpdateTestState $ICA_TESTABORTED
fi

run_oltp()
{
    LogMsg "Orion start running in OLTP mode. Test will take approximately 22 minutes."
    DATE=`date +%Y%m%d_%H%M`
    iostat -x -d 1 4000 sdb  2>&1 > /root/benchmark/orion/oltp.iostat.diskio.log  &
    vmstat       1 4000      2>&1 > /root/benchmark/orion/oltp.vmstat.memory.cpu.log &

    ./orion_linux_x86-64 -run oltp -testname /root/$ORION_SCENARIO_FILE
    sts=$?
    if [ $sts -eq 0 ]; then
        cp /root/${ORION_SCENARIO_FILE}_${DATE}_iops.csv /root/oltp_iops.csv
        cp /root/${ORION_SCENARIO_FILE}_${DATE}_lat.csv /root/oltp_lat.csv
        echo "OTLP test completed. Sleep 60 seconds." >> ~/summary.log
        pkill -f iostat
    	pkill -f vmstat
        sleep 60
    else
        echo "OLTP test failed." >> ~/summary.log
        return 1
    fi    
}

run_dss()
{
    LogMsg "Orion start running in DSS mode. Test will take approximately 65 minutes."
    DATE=`date +%Y%m%d_%H%M`
    iostat -x -d 1 4000 sdb  2>&1 > /root/benchmark/orion/dss.iostat.diskio.log  &
    vmstat       1 4000      2>&1 > /root/benchmark/orion/dss.vmstat.memory.cpu.log &

    ./orion_linux_x86-64 -run dss -testname /root/$ORION_SCENARIO_FILE
    sts=$?
    if [ $sts -eq 0 ]; then
        DSS_STS="yes"
        cp /root/${ORION_SCENARIO_FILE}_${DATE}_mbps.csv /root/dss_mbps.csv
        cp /root/${ORION_SCENARIO_FILE}_${DATE}_lat.csv /root/dss_lat.csv
        echo "DSS test completed. Sleep 60 seconds." >> ~/summary.log
        pkill -f iostat
    	pkill -f vmstat
        sleep 60
    else
        echo "DSS test failed." >> ~/summary.log
        return 1
    fi
}

run_simple()
{
    LogMsg "Orion start running in SIMPLE mode. Test will take approximately 9 minutes."
    DATE=`date +%Y%m%d_%H%M`
    iostat -x -d 1 4000 sdb  2>&1 > /root/benchmark/orion/simple.iostat.diskio.log  &
    vmstat       1 4000      2>&1 > /root/benchmark/orion/simple.vmstat.memory.cpu.log &

    ./orion_linux_x86-64 -run simple -testname /root/$ORION_SCENARIO_FILE
    sts=$?
    if [ $sts -eq 0 ]; then
        SIMPLE_STS="yes"
        cp /root/${ORION_SCENARIO_FILE}_${DATE}_iops.csv /root/simple_iops.csv
        cp /root/${ORION_SCENARIO_FILE}_${DATE}_lat.csv /root/simple_lat.csv
        cp /root/${ORION_SCENARIO_FILE}_${DATE}_mbps.csv /root/simple_mbps.csv
        echo "Simple test completed. Sleep 60 seconds." >> ~/summary.log
        pkill -f iostat
    	pkill -f vmstat
        sleep 60
    else
        echo "Simple test failed." >> ~/summary.log
        return 1
    fi
}

run_normal()
{
    LogMsg "Orion start running in NORMAL mode. Test will take approximately 19 minutes."
    DATE=`date +%Y%m%d_%H%M`
    iostat -x -d 1 4000 sdb  2>&1 > /root/benchmark/orion/normal.iostat.diskio.log  &
    vmstat       1 4000      2>&1 > /root/benchmark/orion/normal.vmstat.memory.cpu.log &

    ./orion_linux_x86-64 -run normal -testname /root/$ORION_SCENARIO_FILE
    sts=$?
    if [ $sts -eq 0 ]; then
        NORMAL_STS="yes"
        cp /root/${ORION_SCENARIO_FILE}_${DATE}_iops.csv /root/normal_iops.csv
        cp /root/${ORION_SCENARIO_FILE}_${DATE}_lat.csv /root/normal_lat.csv
        echo "Normal test completed. Sleep 60 seconds." >> ~/summary.log
        pkill -f iostat
    	pkill -f vmstat
        sleep 60
    else
        echo "Normal test failed." >> ~/summary.log
        return 1
    fi    
}

if  run_oltp && run_dss && run_simple && run_normal -eq 0 ; then
    echo "Orion tests completed." >> ~/summary.log
    UpdateTestState $ICA_TESTCOMPLETED
fi
