#!/bin/bash
#
# buildKernel.sh
#
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
#

DEBUG_LEVEL=3
CONFIG_FILE=.config

START_DIR=$(pwd)
cd ~

#
# Source the constants.sh file so we know what files to operate on.
#

source ./constants.sh

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
dos2unix ica/*
dos2unix bin/*

#
# set the execute bit on any downloade files we may run
#
dbgprint 1 "Setting execute bit on files in the ica and bin directories"
chmod 755 ica/*
chmod 755 bin/*

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
n    UpdateTestState "TestAborted"
    exit 50
fi

cd ${ROOTDIR}

#
# Create the .config file
#
dbgprint 1 "Creating the .config file."
if [ -f ~/ica/kernel.config.base ]; then
	# Basing a new kernel config on a previous kernel config file will
	# provide flexibility in providing know good config files with certain
	# options enabled/disabled.  Functionality could also potentially be
	# added here for choosing between multiple old config files depending
	# on the distro that the kernel is being compiled on (i.g. if Fedora
	# is detected copy ~/ica/kernel.config.base-fedora to .config before
	# running 'make oldconfig')

	dbgprint 3 "Creating new config based on a previous .config file"
	cp ~/ica/kernel.config.base .config

	# Base the new config on the old one and select the default config
	# option for any new options in the newer kernel version
	yes "" | make oldconfig
else
	dbgprint 3 "Create a default .config file"
	yes "" | make oldconfig
	sts=$?
	if [ 0 -ne ${sts} ]; then
	    dbgprint 0 "make defconfig failed."
	    dbgprint 0 "Aborting the test."
	    UpdateTestState "TestAborted"
	    exit 60
	fi

	if [ ! -e ${CONFIG_FILE} ]; then
	    dbgprint 0 "make defconfig did not create the '${CONFIG_FILE}'"
	    dbgprint 0 "Aborting the test."
	    UpdateTestState "TestAborted"
	    exit 70
	fi

	#
	# Enable HyperV support
	#
	dbgprint 3 "Enabling HyperV support in the ${CONFIG_FILE}"
	# On this first 'sed' command use --in-place=.orig to make a backup
	# of the original .config file created with 'defconfig'
	sed --in-place=.orig -e s:"# CONFIG_HYPERVISOR_GUEST is not set":"CONFIG_HYPERVISOR_GUEST=y\nCONFIG_HYPERV=y\nCONFIG_HYPERV_UTILS=y\nCONFIG_HYPERV_BALLOON=y\nCONFIG_HYPERV_STORAGE=m\nCONFIG_HYPERV_NET=y\nCONFIG_HYPERV_KEYBOARD=y\nCONFIG_FB_HYPERV=y\nCONFIG_HID_HYPERV_MOUSE=m": ${CONFIG_FILE}

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

	#
	# Disable the ata_piix driver since this driver loads before the hyperv driver
	# and causes drives to be initialized as sda* (ata_piix driver) as well as
	# hda* (hyperv driver).  Removing the ata_piix driver prevents the hard drive
	# from being claimed by both drivers.
	#
	#sed --in-place -e s:"^CONFIG_ATA_PIIX=[m|y]":"# CONFIG_ATA_PIIX is not set": ${CONFIG_FILE}
	#sed --in-place -e s:"^CONFIG_PATA_OLDPIIX=[m|y]":"# CONFIG_PATA_OLDPIIX is not set": ${CONFIG_FILE}

	#
	# Enable vesa framebuffer support.  This was needed for SLES 11 as a
	# workaround for X not initializing properly on boot.  The 'vga=0x317'
	# line was also necessarily added to the grub configuration.
	#
	#sed --in-place -e s:"# CONFIG_FB_VESA is not set":"CONFIG_FB_VESA=y": ${CONFIG_FILE}

	#
	# ToDo, add support for IC SCSI support
	#

	# After manually adding lines to .config, run make oldconfig to make
	# sure config file is setup properly and all appropriate config
	# options are added. THIS STEP IS NECESSARY!!
	yes "" | make oldconfig

fi


#
# Build the kernel
#
dbgprint 1 "Building the kernel."
proc_count=$(cat /proc/cpuinfo | grep --count processor)
if [ $proc_count -eq 1 ]; then
	make
else
	make -j $((proc_count+1))
	
fi

sts=$?
if [ 0 -ne ${sts} ]; then
	    dbgprint 1 "Kernel make failed: ${sts}"
	    dbgprint 1 "Aborting test."
	    UpdateTestState "TestAborted"
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
	
else
	make modules_install -j $((proc_count+1)) 
fi

sts=$?
if [ 0 -ne ${sts} ]; then
	    dbgprint 1 "Kernel make failed: ${sts}"
	    dbgprint 1 "Aborting test."
	    UpdateTestState "TestAborted"
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
if [ $proc_count -eq 1 ]; then
	make install
else
	make -j $((proc_count+1)) install
fi

sts=$?
if [ 0 -ne ${sts} ]; then
    echo "kernel build failed: ${sts}"
    # todo - collect diagnostic information to be displayed
    UpdateTestState "TestAborted"
	UpdateSummary "make install: Failed"
    exit 130
else
		UpdateSummary "make install: Success"
fi

#
# Validate everything is setup correctly for a successful boot
# of the new kernel
#
#dbgprint 1 "Validate everything is setup correctly to boot the new kernel."
#if [ -e ~/newKernelVersion ]; then
#	. ~/newKernelVersion
#	UpdateSummary "Kernel Version under test is : ##$KERNEL_VERSION"
#else
#	echo "ERROR: cannot determine the version number of the #kernel to validate"
#	UpdateTestState "TestAborted"
#	exit 140
#fi

#cd ~/ica
#./verifyKernelInstall.sh $KERNEL_VERSION
#sts=$?
#if [ 0 -ne ${sts} ]; then
#    echo "ERROR: kernel install validation failed: ${sts}"
#    UpdateTestState "TestAborted"
#	UpdateSummary "Verfication of new kernel Install: Failed"
#    exit 150
#else
#	UpdateSummary "Verfication of new kernel Install: Success"
#fi

#
# Save the current Kernel version for comparision with the version
# of the new kernel after the reboot.
#
cd ~
dbgprint 3 "Saving version number of current kernel in oldKernelVersion.txt"
uname -r > ~/oldKernelVersion.txt


# Update Grub Ebtry to boot from new installed Kernel.


### Grub Modification ###
# Update grub.conf (we only support v1 right now, grub v2 will have to be added
# later)
if [ -e /boot/grub/grub.conf ]; then
        grubfile="/boot/grub/grub.conf"
elif [ -e /boot/grub/menu.lst ]; then
        grubfile="/boot/grub/menu.lst"
else
        echo "ERROR: grub v1 does not appear to be installed on this system."
        exit $E_GENERAL
fi
new_default_entry_num="0"
# added

sed --in-place=.bak -e "s/^default\([[:space:]]\+\|=\)[[:digit:]]\+/default\1$new_default_entry_num/" $grubfile

# Display grub configuration after our change
echo "Here are the new contents of the grub configuration file:"
cat $grubfile


#
# Let the caller know everything worked
#
dbgprint 1 "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"


exit 0
