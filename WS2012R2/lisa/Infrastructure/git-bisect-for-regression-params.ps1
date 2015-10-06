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

$server_VM_ip = "192.168.1.100"
$client_VM_ip = "192.168.1.10"
$sshKey = "id_rsa.ppk"

$server_Host_ip = "LIS-TEST01"
$client_Host_ip = "LIS-TEST02"

$distro_build_script = "build-ubuntu.sh"
$server_VM_Name = "Ubuntu1410-Server"
$client_VM_Name = "Ubuntu1410-Client"
$linux_next_base_checkpoint = "linux-next-base"
$icabase_checkpoint = "Lisabase"


$portable_git_location = "\\Server\tools\PortableGit"
$local_git_location = "D:\PortableGit"
$test_folder = "D:\Test"
$test_folder_bash = "D:Test/"

$linuxnext="git://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git"
$linuxnextfolder="linux-next"
$lastKnownGoodcommit = "5ec1d441a4227b2dfdc47fdc13aa7c6c50496194"
$lastKnownBadcommit  = ""
$topCommitQuality = "BAD"
$badResult = 15
$goodResult = 25