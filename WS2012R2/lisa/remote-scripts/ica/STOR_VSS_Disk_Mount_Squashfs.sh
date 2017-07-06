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

########################################################################
#
# STOR_VSS_BackupRestore_Mount_Squashfs.sh
#
# Description:
#	This script creates squashfs file, which is readonly.
#
################################################################
dos2unix utils.sh
# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 1
}

# Source constants file and initialize most common variables
UtilsInit

# Get distro
GetDistro

case $DISTRO in
    redhat* | fedora*)
        yum -y install squashfs-tools
    ;;
    ubuntu*)
        apt-get -y install squashfs-tools
    ;;
    suse*)
        zypper -y install squashfs-tools
     ;;
     *)
        LogMsg "WARNING:Distro not supported"
        UpdateSummary "WARNING: Distros not supported, test skipped"
        SetTestStateSkipped
        exit 1
    ;;
esac

testDir="/dir"
testDirSqsh="dir.sqsh"
if [ ! -e ${testDir} ]; then
    mkdir $testDir
fi

mksquashfs ${testDir} ${testDirSqsh}
sts=$?
if [ 0 -ne ${sts} ]; then
    LogMsg "Error: mksquashfs Failed ${sts}"
    SetTestStateFailed
    UpdateSummary " mksquashfs ${testDir} ${testDirSqsh}: Failed"
    exit 1
else
    LogMsg "mksquashfs ${testDir} ${testDirSqsh}"
    UpdateSummary "mksquashfs ${testDir} ${testDirSqsh} : Success"
fi

mount ${testDirSqsh} /mnt -t squashfs -o loop
sts=$?
if [ 0 -ne ${sts} ]; then
    LogMsg "Error: mount squashfs Failed ${sts}"
    SetTestStateFailed
    UpdateSummary "mount $testDirSqsh Failed"
    exit 1
else
    LogMsg "mount $testDirSqsh"
    UpdateSummary "mount $testDirSqsh : Success"
    SetTestStateCompleted
fi
