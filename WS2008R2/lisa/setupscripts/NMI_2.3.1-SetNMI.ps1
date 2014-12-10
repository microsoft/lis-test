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
# SetNMI.ps1
#
# Description:
# This powershell automates the process of sending NMI (Non-Maskable
# interrupt) to the Linux VM (TC-2.3.1).
# NMI is sent to Linux VM using Debug-VM powershell cmdlet and can be 
# sent to only VMs in 'running' state. Linux VMs can not receive NMI for
# any other VM state. Also users with administrator privileges can send 
# the NMI, unprivileged user can not send the NMI to VM.
# 
# Linux VM after receiving NMI, updates the counter in /proc/interrupt 
# file.
#  
# This script must be used along with NMI_2.3.1-VerifyNMI.sh testscript
# to verify if the NMI is received by the linux VM. Following is the 
# typical XML parameters for this testscript.
#
# <test>
#	    <testName>SetNMI</testName>
#       <testScript>SetupScripts\NMI_2.3.1-SetNMI.ps1</testScript>
#	    <timeout>600</timeout>
#	    <noReboot>True</noReboot>
# </test>
#		
# <test>
#	    <testName>VerifyNMI</testName>
#       <testScript>NMI_2.3.1-VerifyNMI.sh</testScript>
#       <files>remote-scripts\ica\NMI_2.3.1-VerifyNMI.sh</files>
#		<testparams>
#		     <param>TC_ID=2.3.1</param>
#		</testparams>
#	    <timeout>600</timeout>
#	    <noReboot>False</noReboot>
# </test>
#######################################################################

param([string] $vmName , [string] $hvServer)

#######################################################################
#
# Main script body
#
#######################################################################
$retVal = $false

#
# Check input arguments
#
if (-not $vmName)
{
    "Error: VM name is null. "
    return $retVal
}

if (-not $hvServer)
{
    "Error: hvServer is null"
    return $retVal
}

#
# Sending NMI to VM
#
Debug-VM -Name $vmName -InjectNonMaskableInterrupt -ComputerName $hvServer
if($?)
{
    $retVal = $true
}
else
{
    "NMI Could not be sent to $vmName"
    $retVal = $false
}

return $retval
