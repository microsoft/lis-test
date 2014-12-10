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

EXPECTED_ARGS=1
INITRD_TMP_DIR="/tmp/initrd-extract"
ICA_BASE_DIR="~/bin"

# Check arguments
if [ $# -ne $EXPECTED_ARGS ]; then
	echo "Usage: $(basename $0) kernel-version"
	exit $E_BADARGS
fi
KERNEL_VERSION=$1

# # Source the ICA config file
# if [ -e $HOME/ica/config ]; then
	# . $HOME/ica/config
# else
	# echo "ERROR: Unable to source the Automation Framework config file."
	# exit 1
# fi

# Source distro detection script
if [ -e $ICA_BASE_DIR/distro-detection.sh ]; then
	. $ICA_BASE_DIR/distro-detection.sh
else
	echo "ERROR: File '$ICA_BASE_DIR/distro-detection.sh' does not exist"
	exit $E_NONEXISTENT_FILE
fi

echo "*** Checking installation of Kernel: $KERNEL_VERSION ***"

# Check installation location of hyperv drivers
echo -e "\nINFO: Checking installation of Hyper-V drivers..."

# Check to make sure the kernel modules were actually compiled and installed
# into /lib/modules...
if [ ! -e /lib/modules/$KERNEL_VERSION ]; then
	echo "ERROR: Bad kernel version '$KERNEL_VERSION'.  Unable to check installation of Hyper-V drivers. Exiting install check script."
	exit $E_BAD_KERNEL_VERSION
fi

#
# We have started the process of migrating our drivers from
# $KERNEL/drivers/staging/hv to $KERNEL/drivers/hv. In the following a
# couple of months, our drivers may exist under both directly (vmbus and
# utils have been moved so far).
#
#
echo "Checking to make sure the hyperv kernel modules were compiled and installed in /lib/modules/$KERNEL_VERSION)"

for ic_driver in ${HYPERV_MODULES[@]}; do
	DRIVER_INSTALLED=0
	for EACH_DIR in ${HYPERV_MODULES_DIRS[@]}; do
		basepath="/lib/modules/$KERNEL_VERSION/$EACH_DIR"
		if [ -e $basepath/$ic_driver.ko ]; then
			echo -e "\tIC driver '$ic_driver' installed correctly"
			DRIVER_INSTALLED=1
		fi
	done
	if [ "$DRIVER_INSTALLED" = "0" ]; then
		echo -e "\tERROR: IC driver '$ic_driver' does not exist in $basepath"
		exit $E_HYPERVIC_INSTALL_INCOMPLETE
	fi
done

# Check initrd image. Involves extracting the initrd to a temp directory,
# making sure the initrd /lib directory contains the hyperv kernel modules, and
# also check to make sure the proper modprobe/insmod commands are in the initrd
# 'init' script.
echo -e "\nINFO: Checking initrd image: $KERNEL_VERSION"

# Clean up tmp directory from previous run if something didn't exit cleanly
rm -rf $INITRD_TMP_DIR 

# Extract initrd image
mkdir -p $INITRD_TMP_DIR
START_DIR="~/bin"

# Check to make sure each Hyper-V driver is installed in the /lib directory of
# the initrd image
if [ -e $INITRD_TMP_DIR ]; then
	cd $INITRD_TMP_DIR
	echo "Extracting the initrd image..."
	gunzip -dc /boot/initrd-$KERNEL_VERSION | cpio -ivd

	echo -e "\nChecking initrd 'init' script for modprobe/insmod statements and existence of hyperv kernel modules..."
	for ic_driver in ${HYPERV_MODULES[@]}; do
		# This section needs distro specific processing since they each
		# layout their initrd differently.  Distro specific scripts are
		# sourced because this area could have gotten pretty ugly once
		# we start supporting more distros and different versions of
		# distros (e.g. RHEL6 may # use a different layout for the
		# initrd image)

		# See distro-detection.sh for list of valid DISTRIB_ID values
		# and distro id variables
		case "$DISTRIB_ID" in
			# Fedora isn't supported yet in this script, this is
			# just an example of grouping distros
			"$ID_REDHAT" )
				# If we need to filter even further on based on
				# the distro version number stored in
				# $DISTRIB_RELEASE (e.g. 5.4, etc), we can do so
				# Works for RHEL 5
				. $START_DIR/initrd_check_redhat ;;
		        "$ID_FEDORA" | "$ID_REDHAT6" )
				# Works for fedora 12 and RHEL 6
				. $START_DIR/initrd_check_fedora ;;
		        "$ID_SUSE" )
				# works for open suse 11
				. $START_DIR/initrd_check_suse ;;
			* )
				echo "ERROR: initrd checks are not yet supported for this distro ($DISTRIB_ID)"
		esac
	done
else
	echo "ERROR: Initrd extraction directory was not created due to an unkown error."
	exit $E_GENERAL
fi

# Check /etc/fstab and see if it needs to be modified (change sda,sdb,etc
# references to hda,hdb,et) If a system is using LVM (Logical Volume
# Mangement), we won't need to modify anything since LVM just searches drives
# for metadata and automatically brings them up (i.e. a drive changing from sda
# to hda won't matter).  Likewise, if drives are referred to by labels (e.g.
# LABEL=/) instead of device names (e.g. /dev/sda) we won't need to modify
# anything either.  We only need to modify /etc/fstab if drives are refered to
# by their device names (e.g. /dev/sda1).  In these cases we only modify the
# /dev/sd? devices that are mounted on /, /boot, /home, or swap.  The reason
# for this is that we could have a VM SCSI drive that actually is supposed to
# be a /dev/sd? device and we don't want to change it to /dev/hd?

# The fstab variable makes it useful for testing non-standard (something other
# than /etc/fstab) fstab files
fstab="/etc/fstab"
echo -e "\nINFO: Checking the contents of $fstab"
if [ "$(cat $fstab | grep -i /dev/sd)" = "" ]; then
	echo "$fstab does not need to be modified"
else
	echo "$fstab needs to be modified"
	echo -e "\nCurrent contents of $fstab:"
	cat $fstab

	# TODO: Add a function that takes the $search_pattern string and
	# properly escapes it.

	# The following is an easier to read (i.e. non-escaped) version of the
	# sed regular expression below.
	#search_pattern="^(/dev/)sd([:alpha:][:digit:]+[:space:]+(/|swap|home|boot))"

	sed --in-place=.bak -e 's/^\(\/dev\/\)sd\([[:alpha:]][[:digit:]]\+[[:space:]]\+\(\/\|swap\|\/home\|\/boot\)\)/\1hd\2/g' $fstab
	echo -e "\nNew contents of $fstab:"
	cat $fstab
fi

# Go back to the original directory
cd $START_DIR

# Cleanup temp initrd extraction
rm -rf $INITRD_TMP_DIR

# Exit Successfully
exit 0
