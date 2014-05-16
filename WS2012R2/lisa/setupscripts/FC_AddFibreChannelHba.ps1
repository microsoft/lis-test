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
    Add a given Fibre Channel Adapter to a VM.

.Description
    The script will add a FC Adapter to a given VM.

    The XML definition for this test case would look similar to:
    <test>
        <testName>FC_disks_detection</testName>
        <testScript>FC_disks.sh</testScript>
        <files>remote-scripts\ica\FC_disks.sh</files>
        <setupScript>setupscripts\FC_AddFibreChannelHba.ps1</setupScript>
        <cleanupScript>setupScripts\FC_RemoveFibreChannelHba.ps1</cleanupScript>
        <noReboot>False</noReboot>
        <timeout>600</timeout>
        <testParams>
            <param>TC_COVERED=FC-01,FC-02</param>
            <param>vSANName=fc</param>
        </testParams>
    </test>
    
.Parameter vmName
    Name of the VM to perform the test with.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.
    
.Example
    .\FC_AddFibreChannelHba.ps1 -vmName "MyVM" -hvServer "localhost" -testParams "TC_COVERED=FC-01;$vSANName=FC_NAME"
#>

param ([String] $vmName, [String] $hvServer, [String] $testParams)
$retVal = $False
$vSANName = $null

#
# Check input arguments
#
if (-not $vmName) {
    "Error: VM name is null!"
    return $retVal
}

if (-not $hvServer) {
    "Error: hvServer is null!"
    return $retVal
}

if (-not $testParams) {
    "Error: No testParams provided!"
    "This script requires the test case ID as the test parameter."
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
    "Error: No fibre channel adapter name was specified in the test parameters!"
    return $retVal
}

#############################################################
#
# Main script body
#
#############################################################

# Add the FC adapter, if the command is successful there is no output
Write-Output "Adding the Fibre Channel adapter..."
if ((Add-VMFibreChannelHba -VmName $vmName $vSANName) -ne $null) {
    write-output "Error: Unable to add Fibre Channel with name $vSANName"
    return $retVal
}

#
# Verify the FC adapter
#
if ((Get-VMFibreChannelHba -VmName $vmName) -eq $null) {
    write-Output "Error: Unable to retrieve the Fibre Channel adapter named: $vSANName"
    return $retVal
}
else {
    Write-Output "Successfully added the Fibre Channel adapter $vSANName"
    $retVal = $True
}

return $retVal
