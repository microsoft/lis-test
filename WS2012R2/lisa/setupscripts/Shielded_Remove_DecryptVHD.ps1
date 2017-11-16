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
    Setup script that will remove the Decryption VHD to VM.

.Description
    This is a cleanup script that will run after the encrypted VM 
    is shut down.
    The script will remove the passthrough disk attached to the VM

    A typical XML definition for this test case would look similar
    to the following:
    <test>
        <testName>Install_lsvm</testName>
        <setupScript>setupScripts\Shielded_Add_DecryptVHD.ps1</setupScript>
        <testScript>setupscripts\Shielded_install_lsvm.ps1</testScript>
        <files>remote-scripts/ica/utils.sh</files>
        <testParams>
            <param>TC_COVERED=LSVM-INSTALL</param>
        </testParams>
        <cleanupScript>setupScripts\Shielded_Remove_DecryptVHD.ps1</cleanupScript>
        <timeout>600</timeout>
        <onError>Abort</onError>
        <noReboot>True</noReboot>
    </test>
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

############################################################################
#
# Main script
#
############################################################################

# Check input arguments
if ($vmName -eq $null -or $vmName.Length -eq 0) {
    "Error: VM name is null"
    return $false
}

if ($hvServer -eq $null -or $hvServer.Length -eq 0) {
    "Error: hvServer is null"
    return $false
}

if ($testParams -eq $null -or $testParams.Length -lt 3) {
    "Error: No testParams provided"
    "Shielded_Add_decryptVHD.ps1 requires test params"
    return $false
}


Remove-VMHardDiskDrive -ComputerName $hvServer -VMName $vmName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1

return $true