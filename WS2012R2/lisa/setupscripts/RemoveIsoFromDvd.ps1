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
    Remove the .iso file from the default DVD drive.

.Description
    Remove the .iso file from the default DVD drive.

.Parameter vmName
    Name of the VM that will a DVD drive modified.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.

.Example
    .\RemoveIsoFromDvd.ps1 "MyVm" "localhost"
#>

#######################################################################
#
# RemoveIsoFromDvd.ps1
#
# Description:
#    This script will "unmount" a .iso file in the DVD drive (IDE 1 0)
#
#######################################################################

param ([String] $vmName, [String] $hvServer, [String] $testParams)


#######################################################################
#
# Main script body
#
#######################################################################
"removeIsoFromDvd.ps1"
"  vmName = ${vmName}"
"  hvServer = ${hvServer}"
"  testParams = ${testParams}"

$isoFilename = $null
$controllerNumber=$null
$vmGeneration = $null

#
# Check arguments
#
if (-not $vmName)
{
    "Error: Missing vmName argument"
    return $False
}

if (-not $hvServer)
{
    "Error: Missing hvServer argument"
    return $False
}

#
# This script does not use any testParams
#
$error.Clear()

#
# Remove the .iso file from the VMs DVD drive
#

$vmGeneration = Get-VM $vmName -ComputerName $hvServer| select -ExpandProperty Generation -ErrorAction SilentlyContinue
if ($? -eq $False)
{
   $vmGeneration = 1
}
#
# Make sure the DVD drive exists on the VM
#
if ($vmGeneration -eq 1)
{
    $controllerNumber=1
}
else
{
    $controllerNumber=0
}

$dvdcount = $(Get-VMDvdDrive -VMName $vmName -ComputerName $hvServer).ControllerLocation.count 
for ($i=0; $i -le $dvdcount; $i++)
{
    $dvd = Get-VMDvdDrive -VMName $vmName -ComputerName $hvServer -ControllerNumber $controllerNumber -ControllerLocation $i
    if ($dvd)
    {
        Remove-VMDvdDrive -VMName $vmName -ComputerName $hvServer -ControllerNumber $controllerNumber -ControllerLocation $i
    }
}
if (-not $?)
{
    "Error: Unable to remove the .iso from the DVD"
    return $False
}

return $True
