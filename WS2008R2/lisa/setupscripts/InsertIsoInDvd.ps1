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
    Mount a .iso in the default DVD drive.

.Description
    Mount a .iso in the default DVD drive.

.Parameter vmName
    Name of the VM with the DVD drive to mount.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParam
    Semicolon separated list of test parameters.

.Example
    .\InsertIsoInDvd.ps1 "testVM" "localhost" "isoFilename=test.iso"
#>



param ([String] $vmName, [String] $hvServer, [String] $testParams)

#######################################################################
#                                                                     #
#                         Main script body                            #
#                                                                     #
#######################################################################
"insertIsoInDvd.ps1"
"  vmName = ${vmName}"
"  hvServer = ${hvServer}"
"  testParams = ${testParams}"

$retVal = $False

$isoFilename = $null

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

if (-not $testParams)
{
    "Error: Missing testParams argument"
    return $False
}

$rootDir = $null

#
# Extract the testParams we are concerned with
#
$params = $testParams.Split(';')
foreach ($p in $params)
{
    if ($p.Trim().Length -eq 0)
    {
        continue
    }

    $tokens = $p.Trim().Split('=')
    
    if ($tokens.Length -ne 2)
    {
	    # Just ignore it
        continue
    }
    
    $lValue = $tokens[0].Trim()
    $rValue = $tokens[1].Trim()
    
    if ($lValue -eq "IsoFilename")
    {
        $isoFilename = $rValue
    }

    

}

#Importing HyperV library module

$sts = get-module | select-string -pattern HyperV -quiet 
if (! $sts)
{ 
    $HYPERV_LIBRARY = ".\HyperVLibV2SP1\Hyperv.psd1"
    if ( (Test-Path $HYPERV_LIBRARY) ) 
    { 
        Import-module .\HyperVLibV2SP1\Hyperv.psd1
    } 
    else 
    {
        "Error: The PowerShell HyperV library does not exist" 
        return $False 
    } 
}
#
# Make sure we found the parameters we need to do our job
#
if (-not $isoFilename)
{
    "Error: Test parameters is missing the IsoFilename parameter"
    return $False
}

$error.Clear()

# #
# # Insert the .iso file into the VMs DVD drive
# #

$sts = Add-VMDisk -VM $vmName -ControllerID 1 -LUN 0 -Path $isoFilename -Server $hvServer -Optical 

#Check if the ISO was mounted successfully
if ($sts -eq $null)
{
    "Error: Unable to mount"
    $error[0].Exception
    return $False
}
else
{
    $retVal = $True
}
return $retVal
