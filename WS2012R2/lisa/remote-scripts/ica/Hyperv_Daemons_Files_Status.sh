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
ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"
ICA_TESTSKIPPED="TestSkipped"
#######################################################################
# Adds a timestamp to the log file
#######################################################################
LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}
}

#######################################################################
# Updates the summary.log file
#######################################################################
UpdateSummary()
{
    echo $1 >> ~/summary.log
}

#######################################################################
# Keeps track of the state of the test
#######################################################################
UpdateTestState()
{
    echo $1 > ~/state.txt
}

#######################################################################
# Checks what Linux distro we are running
#######################################################################

#######################################################################
#
# LinuxRelease()
#
#######################################################################
LinuxRelease()
{
    DISTRO=`grep -ihs "buntu\|Suse\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux\|Oracle" /etc/{issue,*release,*version}`
    case $DISTRO in
        *buntu*)
            echo "UBUNTU";;
        Fedora*)
            echo "FEDORA";;
        *CentOS*6.*)
            echo "CENTOS6";;
        *CentOS*7*)
            echo "CENTOS7";;
        *SUSE*)
            echo "SLES";;
        *Red*6.*)
            echo "RHEL6";;
        *Red*7*)
            echo "RHEL7";;
        Debian*)
            echo "DEBIAN";;
		Oracle*)
		    echo "ORACLE";;
    esac
}

#######################################################################
# Check hyper-daemons default files and service status.
# If BuildNumber < 9600, hypervvssd and hypervfcopyd service are inactive,
# only check hypervkvpd
#######################################################################
CheckHypervDaemons()
{
    if [ $BuildNumber -lt 9600 ];then
        hv=('hypervkvpd')
        hv_alias=('[h]v_kvp_daemon')
        hv_service=("hypervkvpd.service")
    else
        hv=('hypervvssd' 'hypervkvpd' 'hypervfcopyd')
        hv_alias=('[h]v_vss_daemon' '[h]v_kvp_daemon' '[h]v_fcopy_daemon')
        hv_service=("hypervkvpd.service" "hypervvssd.service" "hypervfcopyd.service")
    fi
    len_hv=${#hv_service[@]}
    # Start the hyperv daemons check. This is distro-specific.
    case $(LinuxRelease) in
    "RHEL6" | "CENTOS6")

        for (( i=0; i<$len_hv; i++))
        do
            CheckDaemonsFilesRHEL6 ${hv[$i]}
            CheckDaemonsStatus ${hv[$i]} ${hv_alias[$i]}
        done
        ;;
    "RHEL7" | "CENTOS7")
        for (( i=0; i<$len_hv; i++))
        do
          CheckDaemonsFilesRHEL7 ${hv_service[$i]}
          CheckDaemonsStatusRHEL7 ${hv_service[$i]}
        done
        ;;
    "FEDORA")
            for (( i=0; i<$len_hv; i++))
            do
              CheckDaemonsStatusRHEL7 ${hv_service[$i]}
            done
            ;;
    *)
        LogMsg "Distro not supported"
        UpdateTestState $ICA_TESTSKIPPED
        UpdateSummary "Distros not supported, test skipped"
        exit 1
    ;;
    esac
}
#######################################################################
# Check kernel version is newer than the specified version
# if return 0, the current kernel version is newer than specified version
# else, the current kernel version is older than specified version
#######################################################################
CheckVMFeatureSupportStatus()
{
  specifiedKernel=$1
  if [ $specifiedKernel == "" ];then
    return 1
  fi
  # for example 3.10.0-514.el7.x86_64
  # get kernel version array is (3 10 0 514)
  local kernel_array=(`uname -r | awk -F '[.-]' '{print $1,$2,$3,$4}'`)
  local specifiedKernel_array=(`echo $specifiedKernel | awk -F '[.-]' '{print $1,$2,$3,$4}'`)
  local index=${!kernel_array[@]}
  local n=0
  for n in $index
  do
      if [ ${kernel_array[$n]} -gt ${specifiedKernel_array[$n]} ];then
          return 0
      fi
  done

  return 1
}

#######################################################################
# Check hyper-v daemons service status under 90-default.preset and
# systemd multi-user.target.wants for rhel7
#######################################################################
CheckDaemonsFilesRHEL7()
{
  dameonFile=`ls /usr/lib/systemd/system | grep -i $1`
  if [[ "$dameonFile" != $1 ]] ; then
    LogMsg "ERROR: $1 is not in /usr/lib/systemd/system, test failed"
    UpdateSummary "ERROR: $1 is not in /usr/lib/systemd/system, test failed"
    UpdateTestState $ICA_TESTFAILED
    exit 1
  fi

  # for rhel7.3+(kernel-3.10.0-514), no need to check 90-default.preset
  local kernel=$(uname -r)
  CheckVMFeatureSupportStatus "3.10.0-513"

  if [ $? -ne 0 ]; then
    LogMsg "INFO: Check 90-default.preset for $kernel"
    UpdateSummary "INFO: Check 90-default.preset for $kernel"
    dameonPreset=`cat /lib/systemd/system-preset/90-default.preset | grep -i $1`
    if [ "$dameonPreset" != "enable $1" ]; then
      LogMsg "ERROR: $1 is not in 90-default.preset, test failed"
      UpdateSummary "ERROR: $1 is not in 90-default.preset, test failed"
      UpdateTestState $ICA_TESTFAILED
      exit 1
    fi
  else
    LogMsg "INFO: No need to check 90-default.preset for $kernel"
    UpdateSummary "INFO: No need to check 90-default.preset for $kernel"
  fi
}


#######################################################################
# Check hyper-v daemons related file under default folder for rhel 6
#######################################################################
CheckDaemonsFilesRHEL6()
{
  dameonFile=`ls /etc/rc.d/init.d | grep -i $1`

  if [[ "$dameonFile" != $1 ]] ; then
    LogMsg "ERROR: $1 is not in /etc/rc.d/init.d , test failed"
    UpdateSummary "ERROR: $1 is not in /etc/rc.d/init.d , test failed"
    UpdateTestState $ICA_TESTFAILED
    exit 1
  fi
}

#######################################################################
# Check hyper-v daemons service status is active for rhel7
#######################################################################
CheckDaemonsStatusRHEL7()
{
  dameonStatus=`systemctl is-active $1`
  if [ $dameonStatus != "active" ]; then
    LogMsg "ERROR: $1 is not in running state, test aborted"
    UpdateSummary "ERROR: $1 is not in running state, test aborted"
    UpdateTestState $ICA_TESTABORTED
    exit 1

  fi
}

#######################################################################
# Check hyper-v daemons service status is active
#######################################################################
CheckDaemonsStatus()
{
  if [[ $(ps -ef | grep $1 | grep -v grep)  ]] || \
       [[ $(ps -ef | grep $2 | grep -v grep) ]]; then
      LogMsg "$1 Daemon is running"

  else
      LogMsg "ERROR: $1 Daemon not running, test aborted"
      UpdateSummary "ERROR: $1 Daemon not running, test aborted"
      UpdateTestState $ICA_TESTABORTED
      exit 1
  fi
}

#######################################################################
# Main script body
#######################################################################

# Create the state.txt file so ICA knows we are running
UpdateTestState $ICA_TESTRUNNING

# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

# Source the constants file
if [ -e constants.sh ]; then
    . constants.sh
else
    LogMsg "WARN: Unable to source the constants file."
fi

CheckHypervDaemons

UpdateTestState $ICA_TESTCOMPLETED
exit 0
