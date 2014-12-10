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

# Description:
#     This script was created to automate the testing of a Linux
#     kernel source tree.  It does this by performing the following
#     steps:
#	1. Make sure we were given a kernel source tarball
#	2. Configure and build the new kernel
#	3. Update the grub boot options
#	4. Validate the ICs are in the new initrd image
#	5. Reboot into the new kernel
#
#     To identify which files to operation on, we source a file
#     named constants.sh.  This file was given to us by the
#     control server.  It contains definitions like:
#         TARBALL=linux2.6.tar.gz
#         ROOTDIR=linux2.6

DEBUG_LEVEL=3
CONFIG_FILE=.config

START_DIR=$(pwd)
cd ~

#
# Source the constants.sh file so we know what files to operate on.
#

source ~/constants.sh

dbgprint()
{
    if [ $1 -le $DEBUG_LEVEL ]; then
        echo "$2"
    fi
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

UpdateSummary()
{
    echo $1 >> ~/summary.log
}

#
# Create the state.txt file so the ICA script knows
# we are running
#
UpdateTestState "TestRunning"

if [ -e ~/state.txt ]; then
    dbgprint 0 "State.txt file is created "
    dbgprint 0 "Content of state is : " ; echo `cat state.txt`
fi



#
# Write some useful info to the log file
#
dbgprint 1 "buildKernel.sh - Script to automate building of the kernel"
dbgprint 3 ""
dbgprint 3 "Global values"
dbgprint 3 "  DEBUG_LEVEL = ${DEBUG_LEVEL}"
dbgprint 3 "  TARBALL = ${TARBALL}"
dbgprint 3 "  ROOTDIR = ${ROOTDIR}"
dbgprint 3 "  CONFIG_FILE = ${CONFIG_FILE}"
dbgprint 3 "  NEW_CONFIG_FILE = ${NEW_CONFIG_FILE}"
dbgprint 3 "  REPOSITORY_SERVER = ${REPOSITORY_SERVER}"
dbgprint 3 "  REPOSITORY_PATH   = ${REPOSITORY_PATH}"
dbgprint 3 ""

#
# Delete old kernel source tree if it exists.
# This should not be needed, but check to make sure
# 
if [ ! ${ROOTDIR} ]; then
    #dbgprint 1 "The ROOTDIR variable is not defined."
    #dbgprint 1 "aborting the test."
    #UpdateTestState "TestAborted"

    # Try to extract the root directory from the tarball
    ROOTDIR=`tar -tvjf ${TARBALL} | head -n 1 | awk -F " " '{print $6}' | awk -F "/" '{print $1}'`
    if [ ! -n $ROOTDIR ]; then
        dbgprint 0 "Unable to determine value for ROOTDIR."
	UpdateTestState "TestAborted"
        exit 10
    fi
fi
# adding check for summary.log
if [ -e ~/summary.log ]; then
    dbgprint 1 "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

if [ -e ${ROOTDIR} ]; then
    dbgprint 1 "Cleaning up previous copies of source tree"
    dbgprint 3 "Removing the ${ROOTDIR} directory"
    rm -rf ${ROOTDIR}
fi

#
# Make sure we were given the $TARBALL file
#
if [ ! ${TARBALL} ]; then
    dbgprint 0 "The TARBALL variable is not defined."
    dbgprint 0 "Aborting the test."
    UpdateTestState "TestAborted"
    exit 20
fi

#
# Convert any .sh files to Unix format
#
dbgprint 1 "Converting the files in the ica director to unix EOL"
dos2unix -q bin/*

#
# set the execute bit on any downloade files we may run
#
dbgprint 1 "Setting execute bit on files in the ica and bin directories"

chmod 755 bin/*

#Get OS details
if [ -e /etc/SuSE-release ]; then
    OS=$(head -1 /etc/SuSE-release)
	UpdateSummary "OS Under Test : ${OS}"
fi

if [ -e /etc/redhat-release ]; then
    OS=$(head -1 /etc/redhat-release)
	UpdateSummary "OS Under Test : ${OS}"
fi

#Save old Kernel version
OldKernel=$(uname -r)
UpdateSummary "Old Kernel : ${OldKernel}"

#
# Copy the tarball from the repository server
#
#dbgprint 1 "scp -i .ssh/ica_repos_id_rsa root@${REPOSITORY_SERVER}:${REPOSITORY_PATH}/${TARBALL} ."
#scp -i .ssh/ica_repos_id_rsa root@${REPOSITORY_SERVER}:${REPOSITORY_PATH}/${TARBALL} .

dbgprint 1 "Mounting Repository NFS share and copying tarball"
ICATEMPDIR=./icaTempDir
if [ ! -e ${ICATEMPDIR} ]; then
    mkdir ${ICATEMPDIR}
fi

mount ${REPOSITORY_SERVER}:${REPOSITORY_PATH} ./${ICATEMPDIR}
cp ./${ICATEMPDIR}/${TARBALL} .

umount ${ICATEMPDIR}
rmdir ${ICATEMPDIR}

dbgprint 3 "Extracting Linux kernel sources from ${TARBALL}"
# The 'm' option was added to the tar extraction so that the modification
# of all the files in the tarball will be set to the time that the files
# were extracted on the Linux VM (instead of the modification time that is
# recorded in the tarball).
#
# This fixes a potential clock skew error loop when building the kernel.  When
# the ICA repository server is moved to a physical machine this workaround can
# be removed.  The whole problem is caused because of clock drift (fast clock)
# on the repository server because the repository server is a VM on Hyper-V
# (which has known clock drift problems with Linux VMs).
#
# Added the -j option since we are now using .bz2 compressed tar files.
tar -xmjf ${TARBALL}
sts=$?
if [ 0 -ne ${sts} ]; then
    dbgprint 0 "tar failed to extract the kernel from the tarball: ${sts}" 
    dbgprint 0 "Aborting test."
    UpdateTestState "TestAborted"
    exit 40
fi

if [ ! -e ${ROOTDIR} ]; then
    dbgprint 0 "The tar file did not create the directory: ${ROOTDIR}"
    dbgprint 0 "Aborting the test."
    UpdateTestState "TestAborted"
    exit 50
fi

cd ${ROOTDIR}

#
# Create the .config file
#
#dbgprint 1 "Creating the .config file."

# if [ ! -e ${CONFIG_FILE} ]; then
	# # Basing a new kernel config on a previous kernel config file will
	# # provide flexibility in providing know good config files with certain
	# # options enabled/disabled.  Functionality could also potentially be
	# # added here for choosing between multiple old config files depending
	# # on the distro that the kernel is being compiled on (i.g. if Fedora
	# # is detected copy ~/ica/kernel.config.base-fedora to .config before
	# # running 'make oldconfig')

	# dbgprint 3 "Creating new config using Kconfig"
	# yes "" | make oldconfig

	# # Base the new config on the old one and select the default config
	# # option for any new options in the newer kernel version
	# # yes "" | make oldconfig
# else
    yes "" | make oldconfig
	sts=$?
	if [ 0 -ne ${sts} ]; then
	    dbgprint 0 "make oldconfig failed."
	    UpdateTestState "TestFailed"
	    exit 60
	fi
# fi
	dbgprint 3 "Update .config file - Hyper-V Support"
	
	
	hvmodule=$( `cat .config | grep #CONFIG_HYPERV is not set` )
	if [ ${hvmodule} -ne "" ]; then
	    sed --in-place -e s:"#CONFIG_HYPERV is not set":"CONFIG_HYPERV=m": ${CONFIG_FILE}
	else
	    echo "CONFIG_HYPERV=m" >> ${CONFIG_FILE}
	fi
	hvmodule=$( `cat .config | grep #CONFIG_HYPERV_STORAGE is not set` )
	if [ ${hvmodule} -ne "" ]; then
	    sed --in-place -e s:"#CONFIG_HYPERV_STORAGE is not set":"CONFIG_HYPERV_STORAGE=m": ${CONFIG_FILE}
	else
	    echo "CONFIG_HYPERV_STORAGE=m" >> ${CONFIG_FILE}
	fi
	hvmodule=$( `cat .config | grep #CONFIG_HYPERV_NET is not set` )
	if [ ${hvmodule} -ne "" ]; then
	    sed --in-place -e s:"#CONFIG_HYPERV_NET is not set":"CONFIG_HYPERV_NET=m": ${CONFIG_FILE}
	else
	    echo "CONFIG_HYPERV_NET=m" >> ${CONFIG_FILE}
	fi
	hvmodule=$( `cat .config | grep #CONFIG_HID_HYPERV_MOUSE is not set` )
	if [ ${hvmodule} -ne "" ]; then
	    sed --in-place -e s:"#CONFIG_HID_HYPERV_MOUSE is not set":"CONFIG_HID_HYPERV_MOUSE=m": ${CONFIG_FILE}
	else
	    echo "CONFIG_HID_HYPERV_MOUSE=m" >> ${CONFIG_FILE}
	fi
	hvmodule=$( `cat .config | grep #CONFIG_HYPERV_UTILS is not set` )
	if [ ${hvmodule} -ne "" ]; then
	    sed --in-place -e s:"#CONFIG_HYPERV_UTILS is not set":"CONFIG_HYPERV_UTILS=m": ${CONFIG_FILE}
	else
	    echo "CONFIG_HYPERV_UTILS=m" >> ${CONFIG_FILE}
	fi
	hvmodule=$( `cat .config | grep #CONFIG_HYPERV_BALLOON is not set` )
	if [ ${hvmodule} -ne "" ]; then
	    sed --in-place -e s:"#CONFIG_HYPERV_BALLOON is not set":"CONFIG_HYPERV_BALLOON=m": ${CONFIG_FILE}
	else
	    echo "CONFIG_HYPERV_BALLOON=m" >> ${CONFIG_FILE}
	fi
	hvmodule=$( `cat .config | grep #CONFIG_FB_HYPERV is not set` )
	if [ ${hvmodule} -ne "" ]; then
	    sed --in-place -e s:"#CONFIG_FB_HYPERV is not set":"CONFIG_FB_HYPERV=m": ${CONFIG_FILE}
	else
	    echo "CONFIG_FB_HYPERV=m" >> ${CONFIG_FILE}
	fi
	
	
	# Disable kernel preempt support , because of this lot of stack trace is coming and some time kernel does not boot at all.
	#

	dbgprint 3 "Disabling KERNEL_PREEMPT_VOLUNTARY in ${CONFIG_FILE}"
	# On this first this is a workaround for known bug that makes kernel lockup once the bug is fixed we can remove this in PS bug ID is 124 and 125
	sed --in-place -e s:"CONFIG_PREEMPT_VOLUNTARY=y":"# CONFIG_PREEMPT_VOLUNTARY is not set": ${CONFIG_FILE}

	#
	# Enable Ext4, Reiser support (ext3 is enabled by default)
	#
	sed --in-place -e s:"# CONFIG_EXT4_FS is not set":"CONFIG_EXT4_FS=y\nCONFIG_EXT4_FS_XATTR=y\nCONFIG_EXT4_FS_POSIX_ACL=y\nCONFIG_EXT4_FS_SECURITY=y": ${CONFIG_FILE}
	sed --in-place -e s:"# CONFIG_REISERFS_FS is not set":"CONFIG_REISERFS_FS=y\nCONFIG_REISERFS_PROC_INFO=y\nCONFIG_REISERFS_FS_XATTR=y\nCONFIG_REISERFS_FS_POSIX_ACL=y\nCONFIG_REISERFS_FS_SECURITY=y": ${CONFIG_FILE}

	#
	# Enable Tulip network driver support.  This is needed for the "legacy"
	# network adapter provided by Hyper-V
	#
	sed --in-place -e s:"# CONFIG_TULIP is not set":"CONFIG_TULIP=m\nCONFIG_TULIP_MMIO=y": ${CONFIG_FILE}

	HyperVGuest=$( `cat .config | grep #CONFIG_HYPERVISOR_GUEST is not set` )
	if [ ${HyperVGuest} -ne "" ]; then
	    sed --in-place -e s:"#CONFIG_HYPERVISOR_GUEST is not set":"CONFIG_HYPERVISOR_GUEST=y": ${CONFIG_FILE}
	else
	    echo "CONFIG_HYPERVISOR_GUEST=y" >> ${CONFIG_FILE}
	fi
	
	yes "" | make oldconfig
	sts=$?
	if [ 0 -ne ${sts} ]; then
	    dbgprint 0 "make oldconfig failed."
	    UpdateTestState "TestFailed"
	    exit 60
	fi

	if [ ! -e ${CONFIG_FILE} ]; then
	    dbgprint 0 "make oldconfig did not create the '${CONFIG_FILE}'"
	    dbgprint 0 "Aborting the test."
	    UpdateTestState "TestFailed"
	    exit 70
	fi

	


#
# Build the kernel
#
dbgprint 1 "Building the kernel."
proc_count=$(cat /proc/cpuinfo | grep --count processor)
if [ $proc_count -eq 1 ]; then
	make
	sts=$?
else
	make -j $proc_count
	sts=$?
	
fi
if [ 0 -ne ${sts} ]; then
	    dbgprint 1 "Kernel make failed: ${sts}"
	    
	    UpdateTestState "TestFailed"
	    UpdateSummary "Make: Failed"
	    exit 110
else
		UpdateSummary "make: Success"
fi

#
# Build the kernel modules
#
dbgprint 1 "Building the kernel modules."
if [ $proc_count -eq 1 ]; then
	make modules_install
	sts=$?
	
else
	make modules_install -j $proc_count
	sts=$?
fi

if [ 0 -ne ${sts} ]; then
	    dbgprint 1 "Kernel make failed: ${sts}"
	    
	    UpdateTestState "TestFailed"
	    UpdateSummary "make modules_install: Failed"	
	    exit 110
else
		UpdateSummary "make modules_install: Success"
fi
#
# Install the kernel
#
dbgprint 1 "Installing the kernel."
# Adding support for parallel compilation on SMP systems.  This isn't
# needed now, but will benefit testing whenever Hyper-V SMP is default in
# new kernels or if someone decides to have the base system for building
# kernels SMP enabled (currently requires proper Hyper-V IC patch).
# proc_count=$(cat /proc/cpuinfo | grep --count processor)
if [ $proc_count -eq 1 ]; then
	make install
	sts=$?
else
	make install -j $proc_count
	sts=$?
fi
if [ 0 -ne ${sts} ]; then
    echo "kernel build failed: ${sts}"
    # todo - collect diagnostic information to be displayed
    UpdateTestState "TestFailed"
	UpdateSummary "make install: Failed"
    exit 130
else
		UpdateSummary "make install: Success"
fi

#
# Validate everything is setup correctly for a successful boot
# of the new kernel
#
dbgprint 1 "Validate everything is setup correctly to boot the new kernel."
if [ -e ~/newKernelVersion ]; then
	. ~/newKernelVersion
	UpdateSummary "Kernel Version under test is : $KERNEL_VERSION"
else
	echo "ERROR: cannot determine the version number of the kernel to validate"
	UpdateTestState "TestFailed"
	exit 140
fi

#Build KVP Daemon
if [ -e /usr/sbin/hv_kvp_daemon ]; then
    rm -f /usr/sbin/hv_kvp_daemon
fi

cd ./tools/hv
cp ~/${ROOTDIR}/include/linux/hyperv.h /usr/include/linux
sts=$?
if [ 0 -ne ${sts} ]; then
    echo "ERROR: Failed to copy hyperv.h: ${sts}"
    UpdateTestState "TestFailed"
	UpdateSummary "KVPDaemon compilation: Failed"
	exit 100
fi
cp ~/${ROOTDIR}/include/uapi/linux/connector.h /usr/include/linux
sts=$?
if [ 0 -ne ${sts} ]; then
    echo "ERROR: Failed to copy connector.h: ${sts}"
    UpdateTestState "TestFailed"
	UpdateSummary "KVPDaemon compilation: Failed"
	exit 100
fi
gcc -o hv_kvp_daemon hv_kvp_daemon.c
sts=$?
if [ 0 -ne ${sts} ]; then
    echo "ERROR: KVP daemon GCC compilation failed: ${sts}"
    UpdateTestState "TestFailed"
	UpdateSummary "KVPDaemon compilation: Failed"
	exit 100
fi

cp hv_kvp_daemon /usr/sbin/

echo "/usr/sbin/hv_kvp_daemon" >> /etc/init.d/boot.local

cd ~/bin
./verifyKernelInstall.sh $KERNEL_VERSION
sts=$?
if [ 0 -ne ${sts} ]; then
    echo "ERROR: kernel install validation failed: ${sts}"
    UpdateTestState "TestFailed"
	UpdateSummary "Verfication of new kernel Install: Failed"
    exit 150
#else
#	UpdateSummary "Verfication of new kernel Install: Success"
fi

 

cd ~

#
# Let the caller know everything worked
#
dbgprint 1 "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"


exit 0
