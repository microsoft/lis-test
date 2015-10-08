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

$server_VM_Name = "sixiao-Ubuntu1410-Server"
$client_VM_Name = "sixiao-Ubuntu1410-Client"

$server_Host_ip = "LIS-TEST01"
$client_Host_ip = "LIS-TEST02"

$server_VM_ip = "192.168.1.100"
$client_VM_ip = "192.168.1.10"
$sshKey = "id_rsa.ppk"

$distro_build_script = "build-ubuntu.sh"
$icabase_checkpoint = "Lisabase"
$linux_next_base_checkpoint = "linux-next-base"

$test_folder = "D:\Test"

$linuxnext="git://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git"
$linuxnextfolder="linux-next"
$lastKnownGoodcommit = "5ec1d441a4227b2dfdc47fdc13aa7c6c50496194"
$lastKnownBadcommit  = ""
$topCommitQuality = "BAD"
$badResult = 15
$goodResult = 25