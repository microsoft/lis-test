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
#     This script was created to automate the testing of a Linux
#     kernel source tree.  It does this by performing the following
#     steps:
#    1. Make sure we were given a kernel source. If a linux-next git address is provided, make sure that
#       the VM has a NIC (eth1) connect to Internet. This script will configure eth1 to DHCP to access internet.
#    2. Configure and build the new kernel
#
# The outputs are directed into files named:
#     Perf_BuildKernel_make.log, 
#     Perf_BuildKernel_makemodulesinstall.log, 
#     Perf_BuildKernel_makeinstall.log
#
# This test script requires the below test parameters:
#     <param>SOURCE_TYPE=ONLINE</param>
#     <param>LINUX_KERNEL_LOCATION=git://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git</param>
#     <param>KERNEL_VERSION=linux-next</param>
#
# A typical XML test definition for this test case would look
# similar to the following:
#          <test>
#             <testName>BuildKernel</testName>     
#             <testScript>Perf_BuildKernel.sh</testScript>
#             <files>remote-scripts/ica/Perf_BuildKernel.sh</files>
#             <files>Tools/linux-3.14.tar.xz</files>
#             <testParams>
#                 <param>SOURCE_TYPE=ONLINE</param>
#                 <param>LINUX_KERNEL_LOCATION=https://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git</param>
#                 <param>KERNEL_VERSION=linux-next</param>
#                 # params to build kernel from rpm - requires copyLatestItem.ps1 as preTest
#                 <param>SOURCE_TYPE=RPM</param>
#                 <param>ITEM=*.src.rpm</param>
#                 <param>itemLoc=\\redmond\wsscfs\OSTCNix\Build_Drops\unstable_drops\latest\rpm</param>
#                 <param>localDest=tools</param>
#                 # params to build upstream kernel tar from http link
#                 <param>SOURCE_TYPE=ONLINE_TAR</param>
#                 <param>KERNEL_VERSION=linux-4.14-rc7</param>
#                 # params to enable GCOV profiling on the kernel - required for code coverage
#                 <param>ACTIVATE_GCOV=yes</param>
#             </testParams>
#             <uploadFiles>
#                 <file>Perf_BuildKernel_make.log</file>
#                 <file>Perf_BuildKernel_makemodulesinstall.log</file> 
#                 <file>Perf_BuildKernel_makeinstall.log</file>
#             </uploadFiles>
#             <timeout>10800</timeout>
#             <OnError>Abort</OnError>
#          </test>
#
#######################################################################

DEBUG_LEVEL=3
CONFIG_FILE=.config
LINUX_VERSION=$(uname -r)
START_DIR=$(pwd)
proc_count=$(cat /proc/cpuinfo | grep --count processor)

#######################################################################
# Adds a timestamp to the log file
#######################################################################
function LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1}
}

UpdateTestState() {
    echo $1 > ~/state.txt
}

UpdateSummary() {
    echo $1 >> ~/summary.log
}

#
# Source the constants.sh file so we know what files to operate on.
#
cd ~
dos2unix ./utils.sh
source ./constants.sh
source ./utils.sh

dbgprint() {
    if [ $1 -le $DEBUG_LEVEL ]; then
        echo "$2"
    fi
}

function EnableGcov() {
    FILE=`readlink -e $1`
    NR_GCOV=`grep -n "GCOV-based" ${FILE} | grep -Eo '^[^:]+'`
    NR_GCOV=$(($NR_GCOV + 2))

    GCOV_LINES="CONFIG_GCOV_KERNEL=y\n\
CONFIG_ARCH_HAS_GCOV_PROFILE_ALL=y\n\
CONFIG_GCOV_PROFILE_ALL=y\n\
CONFIG_GCOV_FORMAT_AUTODETECT=y\n\
# CONFIG_GCOV_FORMAT_3_4 is not set\n\
# CONFIG_GCOV_FORMAT_4_7 is not set"

    sed -i '/.*_GCOV_.*/ d' $FILE
    sed -i "${NR_GCOV}i ${GCOV_LINES}" $FILE
}

ApplyPatchesAndCompile() {
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
        dbgprint 3 "Create a .config file from existing one"
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
        sed --in-place=.orig -e s:"# CONFIG_HYPERVISOR_GUEST is not set":"CONFIG_HYPERVISOR_GUEST=y\nCONFIG_HYPERV=m\nCONFIG_HYPERV_UTILS=m\nCONFIG_HYPERV_BALLOON=m\nCONFIG_HYPERV_STORAGE=m\nCONFIG_HYPERV_NET=m\nCONFIG_HYPERV_KEYBOARD=m\nCONFIG_FB_HYPERV=m\nCONFIG_HID_HYPERV_MOUSE=m": ${CONFIG_FILE}
        sed --in-place -e s:"# CONFIG_HYPERVISOR_GUEST is not set":"CONFIG_HYPERVISOR_GUEST=y\nCONFIG_HYPERV=m\nCONFIG_HYPERV_UTILS=m\nCONFIG_HYPERV_BALLOON=m\nCONFIG_HYPERV_STORAGE=m\nCONFIG_HYPERV_NET=m\nCONFIG_HYPERV_KEYBOARD=m\nCONFIG_FB_HYPERV=m\nCONFIG_HID_HYPERV_MOUSE=m": ${CONFIG_FILE}

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
        # Enable Tulip network driver support. This is needed for the "legacy"
        # network adapter provided by Hyper-V
        #
        sed --in-place -e s:"# CONFIG_TULIP is not set":"CONFIG_TULIP=y\nCONFIG_TULIP_MMIO=y": ${CONFIG_FILE}

        #
        # Enable Hyper-V PCI passthrough. This is needed for the SR-IOV and
        # other PCI passthrough features.
        #
        sed --in-place -e s:"# CONFIG_PCI_HYPERV is not set":"CONFIG_PCI_HYPERV=m": ${CONFIG_FILE}

        # Disable staging
        sed --in-place -e s:"CONFIG_STAGING=y":"# CONFIG_STAGING is not set": ${CONFIG_FILE}

        # Disable module signing verification. This requires libSSL support if enabled.
        sed --in-place -e s:"CONFIG_KEXEC_BZIMAGE_VERIFY_SIG=y":"# CONFIG_KEXEC_BZIMAGE_VERIFY_SIG is not set": ${CONFIG_FILE}
        sed --in-place -e s:"CONFIG_MODULE_SIG=y":"# CONFIG_MODULE_SIG is not set": ${CONFIG_FILE}
        sed --in-place -e s:"CONFIG_MODULE_SIG_SHA256=y":"# CONFIG_MODULE_SIG_SHA256 is not set": ${CONFIG_FILE}
        sed --in-place -e s:"CONFIG_MODULE_SIG_HASH=.*":"": ${CONFIG_FILE}
        sed --in-place -e s:"CONFIG_MODULE_SIG_KEY=.*":"": ${CONFIG_FILE}
        sed --in-place -e s:"CONFIG_SYSTEM_TRUSTED_KEYRING=y":"# CONFIG_SYSTEM_TRUSTED_KEYRING is not set": ${CONFIG_FILE}
        sed --in-place -e s:"CONFIG_SYSTEM_TRUSTED_KEYS=.*":"": ${CONFIG_FILE}

        if [[ ! -z ${ACTIVATE_GCOV+x} && "${ACTIVATE_GCOV}" == "yes" ]]; then
            dbgprint 3 "Enabling GCOV profile"
            EnableGcov "${CONFIG_FILE}"
            #compile daemons with gcov flags and point systemd to the right ones
            dbgprint 3 "Adding daemons GCOV flags"
            pushd ${KERNEL_VERSION}/tools/hv
            if [ -f Makefile ]; then
                sed -i '/CFLAGS +=/a CFLAGS += -O0 -fprofile-arcs -ftest-coverage' Makefile
                make
            else
                dbgprint 0 "Hyper-V daemons Makefile not found."
                dbgprint 0 "Aborting the test."
                UpdateTestState "TestAborted"
                exit 120
            fi
            # update daemons location for fedora
            dbgprint 3 "Updated daemons service location to GCOV enabled"
            DAEMON_BASE_PATH=$(pwd)/hv_
            for i in fcopy kvp vss;
            do
                SERV_FILE=/usr/lib/systemd/system/hyperv"$i"d.service
                if [ -f ${SERV_FILE} ]; then
                    DAEMON_PATH="$DAEMON_BASE_PATH$i"_daemon
                    if [ -f ${DAEMON_PATH} ]; then
                        sed -i "/^ExecStart=/c\ExecStart=$DAEMON_PATH -n" ${SERV_FILE}
                    else
                        dbgprint 0 "Hyper-v daemon file ${DAEMON_PATH} not found."
                        dbgprint 0 "Aborting the test."
                        UpdateTestState "TestAborted"
                        exit 120
                    fi
                else
                    dbgprint 0 "Hyper-V daemon service file ${SERV_FILE} not found."
                    dbgprint 0 "Aborting the test."
                    UpdateTestState "TestAborted"
                    exit 120
                fi
            done
            popd
        fi

        yes "" | make oldconfig

        # Workaround: Enable HyperV Sock functionality. Otherwise, yes "" | make oldconfig won't set this
        sed --in-place -e s:"CONFIG_HYPERV_SOCK=.*":"": ${CONFIG_FILE}
        echo "CONFIG_HYPERV_SOCK=m" >> ${CONFIG_FILE}
    fi
    UpdateSummary "make oldconfig: Success"

    # Try apply patches under /root/
    dbgprint 1 "*************************"
    for patchfile in `ls ~/*.patch`; do
        patch -f -p1 < $patchfile

        if [ $? != 0 ]; then
            dbgprint 0 "Error: Failed to apply a patch file!"
            UpdateTestState "TestAborted"
            exit 20
        fi
    done

    dbgprint 1 "*************************"
    dbgprint 1 "Info: Building the kernel..."

    if [ $proc_count -eq 1 ]; then
        (time make) >/root/Perf_BuildKernel_make.log 2>&1
    else
        (time make -j $proc_count) >/root/Perf_BuildKernel_make.log 2>&1
    fi
}

# Create the state.txt file so the ICA script knows we are running
UpdateTestState "TestRunning"

# Write some useful info to the log file
dbgprint 1 "buildKernel.sh - Script to automate building of the kernel"
dbgprint 3 ""
dbgprint 3 "Global values"
dbgprint 3 "  DEBUG_LEVEL = ${DEBUG_LEVEL}"
dbgprint 3 "  SOURCE_TYPE = ${SOURCE_TYPE}"
dbgprint 3 "  LINUX_KERNEL_LOCATION = ${LINUX_KERNEL_LOCATION}"
dbgprint 3 "  TARBALL = ${TARBALL}"
dbgprint 3 "  KERNEL_VERSION = ${KERNEL_VERSION}"
dbgprint 3 "  CONFIG_FILE = ${CONFIG_FILE}"
dbgprint 3 ""

# Delete old kernel source tree if it exists.
# This should not be needed, but check to make sure
if [ -e ~/summary.log ]; then
    dbgprint 1 "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

if [ "${SOURCE_TYPE}" == "TARBALL" ]; then
    dbgprint 1 "Building linux kernel from tarball..."
    # Make sure we were given the $TARBALL file
    if [ ! ${TARBALL} ]; then
        dbgprint 0 "The TARBALL variable is not defined."
        dbgprint 0 "Aborting the test."
        UpdateTestState "TestAborted"
        exit 20
    fi
    dbgprint 3 "Extracting Linux kernel sources from ${TARBALL}"
    tar -jxvf ${TARBALL}
    sts=$?
    if [ 0 -ne ${sts} ]; then
        dbgprint 0 "tar failed to extract the kernel from the tarball: ${sts}" 
        dbgprint 0 "Aborting test."
        UpdateTestState "TestAborted"
        exit 40
    fi
    # The Linux Kernel is extracted to the folder which is named by the version by default
    if [ ! -e ${KERNEL_VERSION} ]; then
        dbgprint 0 "The tar file did not create the directory: ${KERNEL_VERSION}"
        dbgprint 0 "Aborting the test."
        UpdateTestState "TestAborted"
        exit 50
    fi
    cd ${KERNEL_VERSION}
elif [ "${SOURCE_TYPE}" == "ONLINE_TAR" ]; then
    wget ${LINUX_KERNEL_LOCATION}
    sts=$?
    if [ 0 -ne ${sts} ]; then
        dbgprint 0 "${sts} failed to download kernel from the link: ${LINUX_KERNEL_LOCATION}"
        dbgprint 0 "Aborting test."
        UpdateTestState "TestAborted"
        exit 40
    fi
    HTTP_TAR="${KERNEL_VERSION}.tar.xz"
    if [ -e "${HTTP_TAR}" ];then
        tar -xf ${HTTP_TAR}
        sts=$?
        if [ 0 -ne ${sts} ]; then
            dbgprint 0 "${sts} failed to extract the kernel from the tarball"
            dbgprint 0 "Aborting test."
            UpdateTestState "TestAborted"
            exit 40
        fi
    else
        dbgprint 0 "the script cannot find the tarball"
        UpdateTestState "TestAborted"
        exit 40
    fi
    if [ ! -e ${KERNEL_VERSION} ]; then
        dbgprint 0 "The tar file did not create the directory: ${KERNEL_VERSION}"
        dbgprint 0 "Aborting the test."
        UpdateTestState "TestAborted"
        exit 50
    fi
    cd ${KERNEL_VERSION}
elif [ "${SOURCE_TYPE}" == "RPM" ]; then
    dbgprint 1 "Building linux kernel from src rpm..."
    # Make sure we were given the src RPM item
    if [ ! ${ITEM} ]; then
        dbgprint 0 "The ITEM variable is not defined."
        dbgprint 0 "Aborting the test."
        UpdateTestState "TestAborted"
        exit 20
    fi
    dbgprint 3 "Extracting Linux kernel sources from ${ITEM}"
    rpm2cpio ${ITEM} | cpio -idmv
    sts=$?
    if [ 0 -ne ${sts} ]; then
        dbgprint 0 "${sts} failed to extract the kernel from rpm: ${ITEM}"
        dbgprint 0 "Aborting test."
        UpdateTestState "TestAborted"
        exit 40
    fi
    TAR=$(ls -t ${HOME}/ | grep tar.gz)
    tar -xzf ${TAR}
    sts=$?
    if [ 0 -ne ${sts} ]; then
        dbgprint 0 "${sts} failed to extract kernel from tar.gz"
        dbgprint 0 "Aborting test."
        UpdateTestState "TestAborted"
        exit 40
    fi
    # Getting the folder where the Linux Kernel was extracted
    KERNEL_VERSION=${HOME}/$(tar -tf ${TAR} | head -1 | cut -f1 -d"/")
    if [ ! -e ${KERNEL_VERSION} ]; then
        dbgprint 0 "The extracted kernel folder location does not exist: ${KERNEL_VERSION}"
        dbgprint 0 "Aborting the test."
        UpdateTestState "TestAborted"
        exit 50
    fi
    dbgprint 0 "The extracted kernel folder location is: ${KERNEL_VERSION}"
    cd ${KERNEL_VERSION}
else
    dbgprint 1 "Building linux-next kernel from git repository..."
    # Make sure we were given the linux-next git location
    if [ ! ${LINUX_KERNEL_LOCATION} ]; then
        dbgprint 0 "Error: The LINUX_KERNEL_LOCATION variable is not defined."
        UpdateTestState "TestAborted"
        exit 20
    fi
    if [ -e ${KERNEL_VERSION} ]; then
        cd ${KERNEL_VERSION}
        if [ "false" != "${FETCH_LATEST}" ]; then
            dbgprint 1 "Fetching latest sources."
            git fetch origin
            git reset --hard origin/master
        fi
    else
        git clone --depth=7 ${LINUX_KERNEL_LOCATION}
        cd ${KERNEL_VERSION}
    fi
fi

#
if is_fedora ; then
    yum install openssl-devel bc nfs-utils elfutils-devel elfutils-libelf-devel -y
    if [ $? -ne 0 ]; then
        LogMsg "Error: Unable to install required packages. Re-trying."
        yum install openssl-devel bc nfs-utils elfutils-devel elfutils-libelf-devel -y
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to install required packages. Kernel compilation might fail."
            #UpdateTestState $TestAborted
        fi
    fi
elif is_ubuntu ; then
    apt update
    apt-get -y install nfs-common libssl-dev bc elfutils libelf-dev
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Unable to install libssl-devel. Aborting..."
        UpdateTestState $TestAborted
    fi
elif is_suse ; then
    #If distro is SLES we need to install some packages first
    echo "Nothing to do."
fi

#
# Start the testing
#
UpdateSummary "KernelRelease=${LINUX_VERSION}"
UpdateSummary "$(uname -a)"

cp /boot/config-${LINUX_VERSION} .config

#
# Apply patches and build the new kernel
#
ApplyPatchesAndCompile
sts=$?
if [ 0 -ne ${sts} ]; then
    dbgprint 1 "Kernel make failed: ${sts}"
    retrycommit=~/${KERNEL_VERSION}_good.commit
    if [ -f $retrycommit ]; then
        dbgprint 1 "Trying again with last good build at commit $(cat $retrycommit)"
        git reset --hard $(cat $retrycommit)
        ApplyPatchesAndCompile
        sts=$?
    fi
    if [ 0 -ne ${sts} ]; then
        dbgprint 1 "Aborting test."
        UpdateTestState "TestAborted"
        UpdateSummary "make: Failed"
        exit 110
    fi
fi
UpdateSummary "make: Success"

# Install the kernel modules
dbgprint 1 "Building the kernel modules."
if [ $proc_count -eq 1 ]; then
    (time make modules_install) >/root/Perf_BuildKernel_makemodulesinstall.log 2>&1
else
    (time make modules_install -j $proc_count) >/root/Perf_BuildKernel_makemodulesinstall.log 2>&1
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

# Install the kernel
dbgprint 1 "Installing the kernel."
if [ $proc_count -eq 1 ]; then
    (time make install) >/root/Perf_BuildKernel_makeinstall.log 2>&1
else
    (time make install -j $proc_count) >/root/Perf_BuildKernel_makeinstall.log 2>&1
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

# Save the current Kernel version for comparision with the version
# of the new kernel after the reboot.
cd ~
dbgprint 3 "Saving version number of current kernel in oldKernelVersion.txt"
uname -r > ~/oldKernelVersion.txt

# Grub modification
grubversion=1
if [ -e /boot/grub/grub.conf ]; then
        grubfile="/boot/grub/grub.conf"
elif [ -e /boot/grub/menu.lst ]; then
        grubfile="/boot/grub/menu.lst"
elif [ -e /boot/grub2/grub.cfg ] || [ -e /boot/efi/EFI/redhat/grub.cfg ] ; then
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
    # Display grub configuration after our change
    echo "Here are the new contents of the grub configuration file:"
    cat $grubfile
fi

# Remove the patch files
rm -f ~/*.patch

if [ "true" = "${OVERWRITE_DEFAULT_KERNEL}" ]; then
    # Remove current kernel
    dbgprint 3 "Removing default kernel ${LINUX_VERSION}"
    rm /boot/*${LINUX_VERSION}*
    rm -rf /lib/modules/${LINUX_VERSION}
fi

# Let the caller know everything worked
dbgprint 1 "Exiting with state: TestCompleted."
UpdateTestState "TestCompleted"
exit 0
