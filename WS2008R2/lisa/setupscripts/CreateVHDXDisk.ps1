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


<#
.Synopsis
    

.Description
    

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>
#######################################################################
#
# This is a script that works only on Windows 8 server.
#
#######################################################################kex
param (
        $Server = "localhost",
        $ParentVHDX,
        $VHDXPath
      )
$s = New-PSSession -ComputerName $Server
Invoke-Command -Session $s -scriptBlock {
    param($Remote_VHDXPath, $Remote_ParentVHD)
    Import-Module Hyper-V
    New-VHD -Path $Remote_VHDXPath -ParentPath $Remote_ParentVHD -VHDFormat VHDX -VHDType Differencing
} -Args $VHDXPath,$ParentVHDX
