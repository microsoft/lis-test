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
LogMsg() {
    # To add the time-stamp to the log file
    echo `date "+%a %b %d %T %Y"` ": ${1}"
}

CopyImage() {
    if [ -d /root/initr ]; then
        LogMsg "Deleting old temporary rescue directory."
        rm -rf /root/initr/
    fi

    mkdir /root/initr
    cp $1 /root/initr/boot.img
    cd /root/initr/

    img_type=$(file boot.img)
    LogMsg "The image type is: $img_type"
}

SearchModules() {
    LogMsg "Searching for modules..."
    [[ -d "/root/initr/usr/lib/modules" ]] && abs_path="/root/initr/usr/lib/modules/" || abs_path="/root/initr/lib/modules/"
    for module in "${hv_modules[@]}"; do
        grep -i "$module" $abs_path*/modules.dep
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

UtilsInit

hv_modules=()
if [ ! -d /sys/firmware/efi ]; then
    index=${!gen1_hv_modules[@]}
    n=0
    for n in $index
    do
        hv_modules[$n]=${gen1_hv_modules[$n]}
    done

else
    index=${!gen2_hv_modules[@]}
    n=0
    for n in $index
    do
        hv_modules[$n]=${gen2_hv_modules[$n]}
    done
fi

# Rebuild array to exclude built-in modules
skip_modules=()

vmbusIncluded=$(grep CONFIG_HYPERV=y /boot/config-"$(uname -r)")
if [ "$vmbusIncluded" ]; then
    skip_modules+=("hv_vmbus.ko")
    LogMsg "Info: hv_vmbus module is built-in. Skipping module. "
fi
storvscIncluded=$(grep CONFIG_HYPERV_STORAGE=y /boot/config-"$(uname -r)")
if [ "$storvscIncluded" ]; then
    skip_modules+=("hv_storvsc.ko")
    LogMsg "Info: hv_storvsc module is built-in. Skipping module. "
fi
netvscIncluded=$(grep CONFIG_HYPERV_NET=y /boot/config-"$(uname -r)")
if [ "$netvscIncluded" ]; then
    skip_modules+=("hv_netvsc.ko")
    LogMsg "Info: hv_netvsc module is built-in. Skipping module. "
fi

# declare temporary array
tempList=()

# remove each module in skip_modules from hv_modules
for module in "${hv_modules[@]}"; do
    skip=""
    for modSkip in "${skip_modules[@]}"; do
        [[ $module == $modSkip ]] && { skip=1; break; }
    done
    [[ -n $skip ]] || tempList+=("$module")
done
hv_modules=("${tempList[@]}")

if [ "${hv_modules:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="The test parameter hv_modules is not defined in constants file."
    LogMsg "$msg"
    echo "$msg" >> ~/summary.log
    SetTestStateAborted
    exit 30
fi

GetDistro

case $DISTRO in
    centos_6 | redhat_6)
        yum install -y dracut-network
        dracut -f
        if [ "$?" = "0" ]; then
            LogMsg "Info: dracut -f ran successfully"
        else
            LogMsg "Error: dracut -f fails to execute"
            echo "Error: dracut -f fails to execute" >> summary.log
            SetTestStateAborted
            exit 1
        fi
    ;;
    ubuntu* | debian*)
        apt update -qq
        # provides skipcpio binary
        apt install -y dracut-core
    ;;
esac

if [ "${img:-UNDEFINED}" = "UNDEFINED" ]; then
    if [ -f /boot/initramfs-0-rescue* ]; then
        img=/boot/initramfs-0-rescue*
    else
    if [ -f "/boot/initrd-`uname -r`" ]; then
        img="/boot/initrd-`uname -r`"
    fi

    if [ -f "/boot/initramfs-`uname -r`.img" ]; then
        img="/boot/initramfs-`uname -r`.img"
    fi

    if [ -f "/boot/initrd.img-`uname -r`" ]; then
        img="/boot/initrd.img-`uname -r`"
    fi
    fi
else
    if [ $img == "kdump.img" ] && [ -f /boot/initramfs-`uname -r`kdump.img ]; then
        img=/boot/initramfs-`uname -r`kdump.img
    else 
        LogMsg "Error: Failed to find $img."
        echo "Error: Failed to find $img." >> /root/summary.log
        SetTestStateFailed
        exit 1
    fi
fi
echo "The initrd test image is: $img" >> summary.log

CopyImage "$img"

LogMsg "Info: Unpacking the image..."
case $img_type in
    *ASCII*cpio*)
        cpio -id -F boot.img &> out.file
        skip_block_size=$(cat out.file | awk '{print $1}')
        dd if=boot.img of=finalInitrd.img bs=512 skip=$skip_block_size
        /usr/lib/dracut/skipcpio finalInitrd.img |zcat| cpio -id --no-absolute-filenames
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
            LogMsg "Error: Failed to unpack the initramfs image with xzcat."
            echo "Error: Failed to unpack the initramfs image." >> /root/summary.log
            SetTestStateFailed
            exit 1
        fi
    ;;
esac

SearchModules

SetTestStateCompleted
exit 0
