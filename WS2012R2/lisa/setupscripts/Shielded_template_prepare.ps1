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
    Setup script that will prepare VM for making a template

.Description
    This is a cleanup script that will run after the encrypted VM 
    is shut down.
    The script will delete the checkpoint and also will check the boot 
    order and change it to the vhdx file if it's the case

    A typical XML definition for this test case would look similar
    to the following:
    <test>
        <testName>Verify_lsvmprep</testName>
        <testScript>shielded_verify_lsvmprep.sh</testScript>
        <files>remote-scripts/ica/shielded_verify_lsvmprep.sh,remote-scripts/ica/utils.sh</files> 
        <setupScript>
            <file>setupscripts\RevertSnapshot.ps1</file>
            <file>setupScripts\Shielded_Add_DecryptVHD.ps1</file>
        </setupScript> 
        <testParams>
            <param>TC_COVERED=LSVM-PRE-03</param>
        </testParams>
        <cleanupScript>
            <file>setupScripts\Shielded_Remove_DecryptVHD.ps1</file>
            <file>setupScripts\Shielded_template_prepare.ps1</file>
        </cleanupScript>
        <timeout>600</timeout>
        <onError>Abort</onError>
        <noReboot>False</noReboot>
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

# Remove snapshot
Remove-VMSnapshot -vmName $vmName -ComputerName $hvServer -Name 'ICABase'
if (-not $?) {
    "Error: Failed to delete the snapshot ICABase"
    return $false
}
Start-Sleep -s 20

# Get boot vhdx
$bootDrive = Get-VMHardDiskDrive -vmName $vmName -ComputerName $hvServer -ControllerLocation 0 -ControllerNumber 0 -ControllerType 'SCSI'

# Check boot order
$bootOrder = $(Get-VMFirmware -vmName $vmName -ComputerName $hvServer).BootOrder
if ($bootOrder[0].BootType -eq 'File') {
    "Changing first boot option to vhdx"
    
    # Set first boot device to above vhdx
    Set-VMFirmware -vmName $vmName -ComputerName $hvServer -FirstBootDevice $bootDrive
}

# Make a copy of the vhdx
$pre_tdc_vhdx_location = $bootDrive.Path
$tdc_vhdx_location = $pre_tdc_vhdx_location -replace 'PRE-',''
Copy-Item -Path $pre_tdc_vhdx_location -Destination $tdc_vhdx_location -Force

return $true