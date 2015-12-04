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
declare os_VENDOR os_RELEASE os_UPDATE os_PACKAGE os_CODENAME

########################################################################
# Determine what OS is running
########################################################################
# GetOSVersion
function GetOSVersion {
    # Figure out which vendor we are
    if [[ -x "`which sw_vers 2>/dev/null`" ]]; then
        # OS/X
        os_VENDOR=`sw_vers -productName`
        os_RELEASE=`sw_vers -productVersion`
        os_UPDATE=${os_RELEASE##*.}
        os_RELEASE=${os_RELEASE%.*}
        os_PACKAGE=""
        if [[ "$os_RELEASE" =~ "10.7" ]]; then
            os_CODENAME="lion"
        elif [[ "$os_RELEASE" =~ "10.6" ]]; then
            os_CODENAME="snow leopard"
        elif [[ "$os_RELEASE" =~ "10.5" ]]; then
            os_CODENAME="leopard"
        elif [[ "$os_RELEASE" =~ "10.4" ]]; then
            os_CODENAME="tiger"
        elif [[ "$os_RELEASE" =~ "10.3" ]]; then
            os_CODENAME="panther"
        else
            os_CODENAME=""
        fi
    elif [[ -x $(which lsb_release 2>/dev/null) ]]; then
        os_VENDOR=$(lsb_release -i -s)
        os_RELEASE=$(lsb_release -r -s)
        os_UPDATE=""
        os_PACKAGE="rpm"
        if [[ "Debian,Ubuntu,LinuxMint" =~ $os_VENDOR ]]; then
            os_PACKAGE="deb"
        elif [[ "SUSE LINUX" =~ $os_VENDOR ]]; then
            lsb_release -d -s | grep -q openSUSE
            if [[ $? -eq 0 ]]; then
                os_VENDOR="openSUSE"
            fi
        elif [[ $os_VENDOR == "openSUSE project" ]]; then
            os_VENDOR="openSUSE"
        elif [[ $os_VENDOR =~ Red.*Hat ]]; then
            os_VENDOR="Red Hat"
        fi
        os_CODENAME=$(lsb_release -c -s)
    elif [[ -r /etc/redhat-release ]]; then
        # Red Hat Enterprise Linux Server release 5.5 (Tikanga)
        # Red Hat Enterprise Linux Server release 7.0 Beta (Maipo)
        # CentOS release 5.5 (Final)
        # CentOS Linux release 6.0 (Final)
        # Fedora release 16 (Verne)
        # XenServer release 6.2.0-70446c (xenenterprise)
        os_CODENAME=""
        for r in "Red Hat" CentOS Fedora XenServer; do
            os_VENDOR=$r
            if [[ -n "`grep \"$r\" /etc/redhat-release`" ]]; then
                ver=`sed -e 's/^.* \([0-9].*\) (\(.*\)).*$/\1\|\2/' /etc/redhat-release`
                os_CODENAME=${ver#*|}
                os_RELEASE=${ver%|*}
                os_UPDATE=${os_RELEASE##*.}
                os_RELEASE=${os_RELEASE%.*}
                break
            fi
            os_VENDOR=""
        done
        os_PACKAGE="rpm"
    elif [[ -r /etc/SuSE-release ]]; then
        for r in openSUSE "SUSE Linux"; do
            if [[ "$r" = "SUSE Linux" ]]; then
                os_VENDOR="SUSE LINUX"
            else
                os_VENDOR=$r
            fi

            if [[ -n "`grep \"$r\" /etc/SuSE-release`" ]]; then
                os_CODENAME=`grep "CODENAME = " /etc/SuSE-release | sed 's:.* = ::g'`
                os_RELEASE=`grep "VERSION = " /etc/SuSE-release | sed 's:.* = ::g'`
                os_UPDATE=`grep "PATCHLEVEL = " /etc/SuSE-release | sed 's:.* = ::g'`
                break
            fi
            os_VENDOR=""
        done
        os_PACKAGE="rpm"
    # If lsb_release is not installed, we should be able to detect Debian OS
    elif [[ -f /etc/debian_version ]] && [[ $(cat /proc/version) =~ "Debian" ]]; then
        os_VENDOR="Debian"
        os_PACKAGE="deb"
        os_CODENAME=$(awk '/VERSION=/' /etc/os-release | sed 's/VERSION=//' | sed -r 's/\"|\(|\)//g' | awk '{print $2}')
        os_RELEASE=$(awk '/VERSION_ID=/' /etc/os-release | sed 's/VERSION_ID=//' | sed 's/\"//g')
    fi
    export os_VENDOR os_RELEASE os_UPDATE os_PACKAGE os_CODENAME
}

########################################################################
# Determine if current distribution is a Fedora-based distribution
########################################################################
function is_fedora {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "Fedora" ] || [ "$os_VENDOR" = "Red Hat" ] || \
        [ "$os_VENDOR" = "CentOS" ] || [ "$os_VENDOR" = "OracleServer" ]
}

########################################################################
# Determine if current distribution is a SUSE-based distribution
########################################################################
function is_suse {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "openSUSE" ] || [ "$os_VENDOR" = "SUSE LINUX" ]
}

########################################################################
# Determine if current distribution is an Ubuntu-based distribution
########################################################################
function is_ubuntu {
    if [[ -z "$os_PACKAGE" ]]; then
        GetOSVersion
    fi
    [ "$os_PACKAGE" = "deb" ]
}

#######################################################################
# Adds a timestamp to the log file
#######################################################################
function LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1}
}

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
# Create the state.txt file so the ICA script knows we are running
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

if [ ! ${ROOTDIR} ]; then
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

# set the execute bit on any downloade files we may run
dbgprint 1 "Setting execute bit on files in the ica and bin directories"
chmod 755 ica/*
chmod 755 bin/*

#
if is_fedora ; then
    yum install openssl-devel -y
    if [ $? -ne 0 ]; then
        LogMsg "Error: Unable to install openssl."
         UpdateTestState $TestAborted
    fi
elif is_ubuntu ; then
    apt-get -y install nfs-common libssl-dev
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Unable to install libssl-devel. Aborting..."
        UpdateTestState $TestAborted
    fi
elif is_suse ; then
    #If distro is SLES we need to install soime packages first
    echo "Nothing to do."
fi

#
# Copy the tarball from the repository server
#
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
	sed --in-place=.orig -e s:"# CONFIG_HYPERVISOR_GUEST is not set":"CONFIG_HYPERVISOR_GUEST=y\nCONFIG_HYPERV=m\nCONFIG_HYPERV_UTILS=m\nCONFIG_HYPERV_BALLOON=m\nCONFIG_HYPERV_STORAGE=m\nCONFIG_HYPERV_NET=m\nCONFIG_HYPERV_KEYBOARD=y\nCONFIG_FB_HYPERV=m\nCONFIG_HID_HYPERV_MOUSE=m": ${CONFIG_FILE}

	# Disable kernel preempt support , because of this lot of stack trace is coming and some time kernel does not boot at all.
	dbgprint 3 "Disabling KERNEL_PREEMPT_VOLUNTARY in ${CONFIG_FILE}"
	# On this first this is a workaround for known bug that makes kernel lockup once the bug is fixed we can remove this in PS bug ID is 124 and 125
	sed --in-place -e s:"CONFIG_PREEMPT_VOLUNTARY=y":"# CONFIG_PREEMPT_VOLUNTARY is not set": ${CONFIG_FILE}
    	
    	# Disabling staging drivers, can cause the linux-next tree to fail to compile due to the new features added
	# Staging drivers are not required for LIS testing in this case.
    	sed --in-place -e s:"CONFIG_STAGING=y":"# CONFIG_STAGING is not set": ${CONFIG_FILE}

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

	# After manually adding lines to .config, run make oldconfig to make sure config file is setup
	# properly and all appropriate config options are added. THIS STEP IS NECESSARY!!
    # Disable module signing verification. This requires libSSL support if enabled.
    sed --in-place -e s:"CONFIG_MODULE_SIG=y":"# CONFIG_MODULE_SIG is not set": ${CONFIG_FILE}
    sed --in-place -e s:"CONFIG_MODULE_SIG_SHA256=y":"# CONFIG_MODULE_SIG_SHA256 is not set": ${CONFIG_FILE}
    sed --in-place -e s:"CONFIG_MODULE_SIG_HASH=.*":"": ${CONFIG_FILE}
    sed --in-place -e s:"CONFIG_MODULE_SIG_KEY=.*":"": ${CONFIG_FILE}
    sed --in-place -e s:"CONFIG_SYSTEM_TRUSTED_KEYRING=y":"# CONFIG_SYSTEM_TRUSTED_KEYRING is not set": ${CONFIG_FILE}
    sed --in-place -e s:"CONFIG_SYSTEM_TRUSTED_KEYS=.*":"": ${CONFIG_FILE}
    sed --in-place -e s:"CONFIG_BTRFS_FS=y":"# CONFIG_BTRFS_FS is not set": ${CONFIG_FILE}
    sed --in-place -e s:"CONFIG_XFS_FS=y":"# CONFIG_XFS_FS is not set": ${CONFIG_FILE}

	yes "" | make oldconfig
fi

#
# Build the kernel
#
dbgprint 1 "Building the kernel..."
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
dbgprint 1 "Installing the new kernel..."

# Adding support for parallel compilation on SMP systems.
if [ $proc_count -eq 1 ]; then
	make install
else
	make -j $((proc_count+1)) install
fi

sts=$?
if [ 0 -ne ${sts} ]; then
	echo "kernel build failed: ${sts}"
	UpdateTestState "TestAborted"
	UpdateSummary "make install: Failed"
	exit 130
else
	UpdateSummary "make install: Success"
fi

cd ~
dbgprint 3 "Saving version number of current kernel in oldKernelVersion.txt"
uname -r > ~/oldKernelVersion.txt

# Grub changes for the new kernel
grubversion=1
if [ -e /boot/grub/grub.conf ]; then
        grubfile="/boot/grub/grub.conf"
elif [ -e /boot/grub/menu.lst ]; then
        grubfile="/boot/grub/menu.lst"
elif [ -e /boot/grub2/grub.cfg ]; then
        grubversion=2
        grub2-mkconfig -o /boot/grub2/grub.cfg
	grub2-set-default 0
else
	echo "grub v1 files does not appear to be installed on this system. it should use grub v2."
	# the new kernel is the default one to boot next time
	grubversion=2
fi

if [ 1 -eq ${grubversion} ]; then
    echo "Update grub v1 files."
    new_default_entry_num="0"
    # added
    sed --in-place=.bak -e "s/^default\([[:space:]]\+\|=\)[[:digit:]]\+/default\1$new_default_entry_num/" $grubfile
fi

# Display grub configuration after our change
echo "This is the new grub configuration file:"
cat $grubfile

#
# Let the caller know everything worked
#
dbgprint 1 "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"

exit 0
