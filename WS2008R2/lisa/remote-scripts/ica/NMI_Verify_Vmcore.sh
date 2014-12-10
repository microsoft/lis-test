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

#Description : This script will verify if the generated vmcore 
# is in appropriate format and can be readble using crash utility

cd /var/crash/
echo "Crash folder found, Processing..."
cd "` ls -ltc | awk '/^d/{print $NF; exit}' `"
if [ $? -ne 0 ]; then
	echo "Error: Crash folder not found"
	exit 1
fi
crash vmlinux-$(uname -r).gz vmcore -i /root/crashcommand > crash.log
if [ $? -ne 0 ]; then
	echo "Error: vmcore file not generated or failed to read. Please also check if the appropriate kernel-debug packages are installed"
else
	cat crash.log
	echo "vmcore file generated and read successfully"
fi
