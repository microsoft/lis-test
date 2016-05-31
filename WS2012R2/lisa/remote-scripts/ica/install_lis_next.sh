#!/bin/bash
#######################################################################
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
#######################################################################

#######################################################################
#
# install_lis_next.sh
#
# Clones the Lis-Next repository from github, then build and 
# install LIS from the source code.
# Currently works with RHEL/CentOS 6.x and 7.x
#
#######################################################################

ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"

build_date=$(date "+%d-%b")

LogMsg() {
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

UpdateTestState() {
    echo $1 > ~/state.txt
}

#
# Create the state.txt file so the LISA knows
# we are running
#
cd ~
UpdateTestState $ICA_TESTRUNNING

#
# Remove any old symmary.log files
#
LogMsg "Info : Cleaning up any old summary.log files"
if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

#
# Source any test parameters passed to us via the constants.sh file
#
if [ -e ~/constants.sh ]; then
    LogMsg "Info : Sourcing ~/constants.sh"
    . ~/constants.sh
else
    LogMsg "ERROR: Unable to source the constants file."
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

#
# Source the utils.sh script
#
if [ ! -e ~/utils.sh ]; then
    LogMsg "Error: The utils.sh script is not present on the VM"
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

dos2unix utils.sh
chmod +x utils.sh
. ~/utils.sh

#######################################################################
#
# Main script body
#
#######################################################################
#
# Removing existing folder if present.
#
if [ -e ./lis-next ]; then
    LogMsg "Info : Removing an old lis-next directory"
    rm -rf ./lis-next
fi

#
# Clone Lis-Next 
#
LogMsg "Info : Cloning lis-next"
git clone https://github.com/LIS/lis-next
if [ $? -ne 0 ]; then
    LogMsg "Error: unable to clone lis-next"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# Detect the version of CentOS/RHEL we are running
#
rhel_version=0
GetDistro
LogMsg "Info : Detected OS distro/version ${DISTRO}"

case $DISTRO in
redhat_7|centos_7)
    rhel_version=7
    ;;
redhat_6|centos_6)
    rhel_version=6
    ;;
redhat_5|centos_5)
    rhel_version=5
    ;;
*)
    LogMsg "Error: Unknown or unsupported version: ${DISTRO}"
    UpdateTestState $ICA_TESTFAILED
    exit 1
    ;;
esac

echo "Kernel: $(uname -r)" >> ~/summary.log

#
# If an existing LIS RPM installation is present,
# decide if we should clean-up the installed modules
#
if [[ ${lis_cleanup} -eq "yes" ]]; then
    LogMsg "Info: Existing LIS clean-up flag present, removing old modules..."
	echo "Info: Existing LIS clean-up flag present, removing old modules..." >> ~/summary.log
	
	# clean-up previous installed lis modules
	rm -rf /lib/modules/$(uname -r)/extra/microsoft-hyper-v
	rm -rf /lib/modules/$(uname -r)/weak-updates/microsoft-hyper-v
fi

LogMsg "Info : Building ${rhel_version}.x source tree"
cd lis-next/hv-rhel${rhel_version}.x/hv

# Defining a custom LIS version string in order to acknoledge the use of these drivers
sed --in-place -e s:"#define HV_DRV_VERSION.*":"#define HV_DRV_VERSION "'"4.1.0-'$build_date'"'"": include/linux/hv_compat.h

./rhel${rhel_version}-hv-driver-install
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to build the lis-next RHEL ${rhel_version} code"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

echo "Info: Successfully built lis-next from the hv-rhel-${rhel_version}.x code" > ~/summary.log

# Compiling LIS daemons
cd ~/lis-next/hv-rhel${rhel_version}.x/hv/tools

make
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to compile the LIS modules!"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

# Stopping selinux
# LIS daemons can conflict with selinux without proper rules
setenforce 0
sed -i -e 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

case "$DISTRO" in
redhat_7|centos_7)
	if [[ $(systemctl list-units --type=service | grep hyperv) ]]; then
			LogMsg "Running daemons are being stopped."
				systemctl stop hypervkvpd.service 
				if [ $? -ne 0 ]; then
						echo "Error: Unabele to stop hypervkvpd." >> ~/summary.log
						UpdateTestState $ICA_TESTFAILED                    
				fi
				systemctl stop hypervvssd.service 
				if [ $? -ne 0 ]; then
						 echo "Error: Unable to stop hypervvssd." >> ~/summary.log
						 UpdateTestState $ICA_TESTFAILED
				fi
				systemctl stop hypervfcopyd.service
				 if [ $? -ne 0 ]; then
						echo "Error: Unable to stop hypervfcopyd." >> ~/summary.log
						UpdateTestState $ICA_TESTFAILED
				fi
			LogMsg "Running daemons have been stopped."
	fi
		
	LogMsg "Info: Backing up default daemons."

	\cp /usr/sbin/hypervkvpd /usr/sbin/hypervkvpd.old
		if [ $? -ne 0 ]; then
			echo "Error: Unable to copy hv-kvp-daemon." >> ~/summary.log
			UpdateTestState $ICA_TESTFAILED
		fi
	\cp /usr/sbin/hypervvssd /usr/sbin/hypervvssd.old
		if [ $? -ne 0 ]; then
			 echo "Error: Unable to copy hv-vss-daemon." >> ~/summary.log
			UpdateTestState $ICA_TESTFAILED
		fi
	\cp /usr/sbin/hypervfcopyd /usr/sbin/hypervfcopyd.old
		if [ $? -ne 0 ]; then
			echo "Error: Unable to copy hv-fcopy-daemon." >> ~/summary.log
			UpdateTestState $ICA_TESTFAILED
		fi
		
	LogMsg "Info: Copying compiled daemons."
	mv -f hv_kvp_daemon /usr/sbin/hypervkvpd
	if [ $? -ne 0 ]; then
		echo "Error: Unable to copy hv-kvp-daemon compiled." >> ~/summary.log
		UpdateTestState $ICA_TESTFAILED
	fi

	mv -f hv_vss_daemon /usr/sbin/hypervvssd
	if [ $? -ne 0 ]; then
		echo "Error: Unable to copy hv-vss-daemon compiled." >> ~/summary.log
		UpdateTestState $ICA_TESTFAILED
	fi

	mv -f hv_fcopy_daemon /usr/sbin/hypervfcopyd
	if [ $? -ne 0 ]; then
		echo "Error: Unable to copy hv-kvp-daemon compiled." >> ~/summary.log
		UpdateTestState $ICA_TESTFAILED
	fi

	LogMsg "Compiled daemons copied."

	sed -i 's,ExecStart=/usr/sbin/hypervkvpd,ExecStart=/usr/sbin/hypervkvpd -n,' /usr/lib/systemd/system/hypervkvpd.service
		if [ $? -ne 0 ]; then
			echo "Error: Unable to modify hv-kvp-daemon." >> ~/summary.log
			UpdateTestState $ICA_TESTFAILED
		fi
	sed -i 's,ExecStart=/usr/sbin/hypervvssd,ExecStart=/usr/sbin/hypervvssd -n,' /usr/lib/systemd/system/hypervvssd.service
		if [ $? -ne 0 ]; then
			echo "Error: Unable to modify hv-vss-daemon." >> ~/summary.log
			UpdateTestState $ICA_TESTFAILED
		fi
	sed -i 's,ExecStart=/usr/sbin/hypervfcopyd,ExecStart=/usr/sbin/hypervfcopyd -n,' /usr/lib/systemd/system/hypervfcopyd.service
		if [ $? -ne 0 ]; then
			echo "Error: Unable to modify hv-fcopy-daemon." >> ~/summary.log
			UpdateTestState $ICA_TESTFAILED
		fi

	systemctl daemon-reload
		if [ $? -ne 0 ]; then
			echo "Error: Unable to reload daemon." >> ~/summary.log
			UpdateTestState $ICA_TESTFAILED
		fi
		
	systemctl start hypervkvpd.service
		if [ $? -ne 0 ]; then
			echo "Info: The below warnings can be ignored if no existing LIS daemons are installed." >> ~/summary.log
			echo "Error: Unable to start hv-kvp-daemon." >> ~/summary.log
			UpdateTestState $ICA_TESTFAILED
		fi
	systemctl start hypervvssd.service
		if [ $? -ne 0 ]; then
			echo "Error: Unable to start hv-vss-daemon." >> ~/summary.log
			UpdateTestState $ICA_TESTFAILED
		fi
	systemctl start hypervfcopyd.service
		if [ $? -ne 0 ]; then
			echo "Error: Unable to start hv-fcopy-daemon." >> ~/summary.log
			UpdateTestState $ICA_TESTFAILED
		fi
	# fcopy daemon can be disabled by default in some configurations
	systemctl enable hypervfcopyd.service
;;

redhat_6|centos_6)
	kill `ps -ef | grep daemon | grep -v grep | awk '{print $2}'`
        if [ $? -ne 0 ]; then
            echo "Error: Unable to kill daemons." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
		
    if [[ $(service --status -all | grep _daemon) ]]; then
        LogMsg "Running daemons are being stopped."
            service hypervkvpd stop
            if [ $? -ne 0 ]; then
                    echo "Error: Unable to stop hypervkvpd." >> ~/summary.log
                    UpdateTestState $ICA_TESTFAILED
            fi
            service hypervvssd stop
            if [ $? -ne 0 ]; then
                     echo "Error: Unable to stop hypervvssd." >> ~/summary.log
                     UpdateTestState $ICA_TESTFAILED
            fi
            service hypervfcopyd stop
             if [ $? -ne 0 ]; then
                    echo "Error: Unable to stop hypervfcopyd." >> ~/summary.log
                    UpdateTestState $ICA_TESTFAILED
            fi
        LogMsg "Running daemons stopped."
    fi
	
    LogMsg "Info: Backing up default daemons."

    \cp /usr/sbin/hv_kvp_daemon /usr/sbin/hv_kvp_daemon.old
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hv-kvp-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    \cp /usr/sbin/hv_vss_daemon /usr/sbin/hv_vss_daemon.old
        if [ $? -ne 0 ]; then
             echo "Error: Unable to copy hv-vss-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    \cp /usr/sbin/hv_fcopy_daemon /usr/sbin/hv_fcopy_daemon.old
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hv-fcopy-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
		
    LogMsg "Default daemons back up."
    LogMsg "Copying compiled daemons."
    mv -f hv_kvp_daemon /usr/sbin/
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hv-kvp-daemon compiled." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    mv -f hv_vss_daemon /usr/sbin/
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hv-vss-daemon compiled." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    mv -f hv_fcopy_daemon /usr/sbin/
        if [ $? -ne 0 ]; then
            echo "Error: Unable to copy hv-kvp-daemon compiled." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi

    LogMsg "Compiled daemons copied."

    service hypervkvpd start
        if [ $? -ne 0 ]; then
			echo "Info: The below warnings can be ignored if no existing LIS daemons are installed." >> ~/summary.log
            echo "Error: Unable to start hv-kvp-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    service hypervvssd start 
        if [ $? -ne 0 ]; then
            echo "Error: Unable to start hv-vss-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
    service hypervfcopyd start 
        if [ $? -ne 0 ]; then
            echo "Error: Unable to start hv-fcopy-daemon." >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
        fi
		
    LogMsg "Info: LIS daemons started."
;;
esac

echo "Info: Successfully compiled and started the lis-next tree LIS daemons." >> ~/summary.log

# work-around to satisfy requirements
numactl -s
if [ $? -ne 0 ]; then
	yum -y install numactl
fi

#
# If we got here, everything worked as expected.
#
LogMsg "Exiting with state: TestCompleted."
UpdateTestState $ICA_TESTCOMPLETED

exit 0
