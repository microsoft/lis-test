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
    Removes a given Fibre Channel Adapter from a VM.

.Description
    The script will remove a FC Adapter from a given VM.
    
.Parameter vmName
    Name of the VM to perform the test with.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.
	
.Example
	.\FC_RemoveFibreChannelHba.ps1 -vmName "MyVM" -hvServer "localhost" -testParams "TC_COVERED=FC-ID;$vSANName=FC_NAME"
#>

param ([String] $vmName, [String] $hvServer, [String] $testParams)
$retVal = $false
$vSANName = $null

#
# Check input arguments
#
if (-not $vmName) {
    write-output "Error: VM name is null!"
    return $retVal
}

if (-not $hvServer) {
    write-output  "Error: hvServer is null!"
    return $retVal
}

if (-not $testParams) {
  write-output  "Error: No testParams provided!"
  write-output  "This script requires the test case ID as the test parameter."
    return $retVal
}

#
# Checking the mandatory testParams. New parameters must be validated here.
#
$params = $testParams.Split(';')
foreach ($p in $params)
{
    if ($p.Trim().Length -eq 0) {
        continue
    }

    $tokens = $p.Trim().Split('=')

    if ($tokens.Length -ne 2) {
        # Just ignore it
         continue
    }

    $lValue = $tokens[0].Trim()
    $rValue = $tokens[1].Trim()

    #
    # fcName test param
    #
    if ($lValue -eq "vSANName") {
        $vSANName = $rValue
        continue
    }
}

#
# Make sure we have all the required data to do our job
#
if (-not $vSANName) {
    write-output "Error: No fibre channel adapter name was specified in the test parameters!"
    return $retVal
}

#############################################################
#
# Main script body
#
#############################################################
$retVal = $true

# Remove the FC adapter
$fc = Get-VMFibreChannelHba -VmName $vmName

if ((Remove-VMFibreCHannelHba $fc) -ne $null) {
    write-output "Error: Unable to remove the Fibre Channel named: $vSANName "
    $retVal = $false
}
else {
    write-output "Successfully removed Fibre Channel named:$vSANName "
    $retVal = $true
}

return $retVal
