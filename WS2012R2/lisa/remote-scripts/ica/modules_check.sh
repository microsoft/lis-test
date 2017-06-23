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
#
# Functions definitions
#
LogMsg()
{
    # To add the time-stamp to the log file
    echo `date "+%a %b %d %T %Y"` ": ${1}"
}

CopyImage()
{
    if [ -d /root/initr ]; then
        LogMsg "Deleting old temporary rescue directory."
        rm -rf /root/initr/
    fi

    LogMsg "Creating temporary directory."
    mkdir /root/initr
    cp $1 /root/initr/boot.img
    cd /root/initr/

    img_type=`file boot.img`
    LogMsg "The image type is: $img_type"
}

SearchModules()
{
    LogMsg "Searching for modules..."
    [[ -d "/root/initr/usr/lib/modules" ]] && abs_path="/root/initr/usr/lib/modules/" || abs_path="/root/initr/lib/modules/"
    for module in "${hv_modules[@]}"; do
        grep -i $module $abs_path*/modules.dep
        if [ $? -eq 0 ]; then
            LogMsg "Info: Module $module was found in initrd."
            echo "Info: Module $module was found in initrd." >> /root/summary.log
        else
            LogMsg "ERROR: Module $module was NOT found."
            echo "ERROR: Module $module was NOT found." >> /root/summary.log
			grep -i $module $abs_path*/modules.dep >> /root/summary.log
            SetTestStateFailed
            exit 1
        fi
    done
}

######################################################################
#
# Main script
#
######################################################################

dos2unix utils.sh
# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 1
}

# Source constants file and initialize most common variables
UtilsInit

if [ -d /sys/firmware/efi ]; then
    msg = "Test not available for gen 2 VMs"
    LogMsg "$msg"
    echo $msg >> ~/summary.log
    SetTestStateSkipped
fi

if [ "${hv_modules:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter fileSystems is not defined in constants file."
    LogMsg "$msg"
    echo $msg >> ~/summary.log
    SetTestStateAborted
    exit 30
fi

if [[ $DISTRO == "redhat_6" ]]; then
    yum install -y dracut-network
    dracut -f
    if [ "$?" = "0" ]; then
        LogMsg "Info: dracut -f executes successfully"
    else
        LogMsg "Error: dracut -f fails to execute"
        echo "Error: dracut -f fails to execute" >> summary.log
        SetTestStateAborted
        exit 1
    fi
fi

if [ -f /boot/initramfs-0-rescue* ]; then
    img=/boot/initramfs-0-rescue*
else
    [[ -f "/boot/initrd-`uname -r`" ]] && img="/boot/initrd-`uname -r`" || [[ -f "/boot/initramfs-`uname -r`.img" ]] && img="/boot/initramfs-`uname -r`.img" || img="/boot/initrd.img-`uname -r`"
fi

echo "The initrd test image is: $img" >> summary.log

CopyImage $img

LogMsg "Info: Unpacking the image..."

case $img_type in
    *ASCII*cpio*)
        /usr/lib/dracut/skipcpio boot.img |zcat| cpio -id --no-absolute-filenames
        if [ $? -eq 0 ]; then
            LogMsg "Info: Successfully unpacked the image."
        else
            LogMsg "Error: Failed to unpack the initramfs image."
            echo "Error: Failed to unpack the initramfs image." >> /root/summary.log
            SetTestStateFailed
            exit 1
        fi
    ;;
    *gzip*)
        gunzip -c boot.img | cpio -i -d -H newc --no-absolute-filenames
        if [ $? -eq 0 ]; then
            LogMsg "Info: Successfully unpacked the image."
        else
            LogMsg "Error: Failed to unpack the initramfs image with gunzip."
            echo "Error: Failed to unpack the initramfs image." >> /root/summary.log
            SetTestStateFailed
            exit 1
        fi
    ;;
    *XZ*)
        xzcat boot.img | cpio -i -d -H newc --no-absolute-filenames
        if [ $? -eq 0 ]; then
            LogMsg "Info: Successfully unpacked the image."
        else
            LogMsg "Error: Failed to unpack the initramfs image with gunzip."
            echo "Error: Failed to unpack the initramfs image." >> /root/summary.log
            SetTestStateFailed
            exit 1
        fi
    ;;
esac

SearchModules

SetTestStateCompleted
exit 0