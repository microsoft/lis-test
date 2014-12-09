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
############################################################################
#
# AddNic.ps1
#
# Description:
#
#
#   The ICA scripts will always pass the vmName, hvServer, and a
#   string of testParams from the test definition separated by
#   semicolons. The testParams for this script identify disk
#   controllers, hard drives, and .vhd types.  The testParams
#   have the format of:
#
#      NIC=NIC type, Network Type, Network Name
#
#   NIC Type can be one of the following:
#      NetworkAdapter
#      LegacyNetworkAdapter
#
#   Network Type can be one of the following:
#      External
#      Internal
#      Private
#
#   Network Name is the name of a existing netowrk.
#
#   This script will not create the network.  It will make sure the network
#   exists.
#
#   The following is an example of a testParam for adding a NIC
#
#     <testParams>
#         <param>NIC=NetworkAdapter,External,Corp Ethernet LAN</param>
#         <param>NIC=LegacyNetworkAdapter,Internal,InternalNet</param>
#     <testParams>
#
#   The above will be parsed into the following string by the ICA scripts and passed
#   to the setup script:
#
#       "NIC=NetworkAdapter,External,Corp Ehternet LAN";NIC=LegacyNetworkAdapter,Internal,InternalNet"
#
#   The setup (and cleanup) scripts need to parse the testParam
#   string to find any parameters it needs.
#
#   Notes:
#     This is a setup script that will run before the VM is booted.
#     This script will add a NIC to the VM.
#
#     Setup scripts (and cleanup scripts) are run in a separate
#     PowerShell environment, so they do not have access to the
#     environment running the ICA scripts.  Since this script uses
#     The PowerShell Hyper-V library, these modules must be loaded
#     by this startup script.
#
#     The .xml entry for this script could look like either of the
#     following:
#         <setupScript>SetupScripts\AddNic.ps1</setupScript>
#
#   All setup and cleanup scripts must return a boolean ($true or $false)
#   to indicate if the script completed successfully or not.
#
############################################################################

#param([string] $vmName, [string] $hvServer, [string] $testParams)
$vmName = "PPG_ICA"
$hvServer = "localhost"

$retVal = $False

 $Error.Clear()

 $snic = Get-VMNIC -VM $vmName -VMBus
 Write-Host $snic 
 Set-VMNICSwitch $snic -Virtualswitch Internal
 if ($Error.Count -gt 0)
  {
    "Error: Unable to Switch Network Adaptor Type"
    $Error[0].Exception
    return $False
  }
$retVal = $true

return $retVal