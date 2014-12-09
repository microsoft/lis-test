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
    This PowerShell test script retrieves and verifies the Intrinsic (pool2) key value pairs.
    Parameters to be passed are - VM Name, HV server name, test case number           

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false

#
# Check input arguments
#
if (-not $vmName)
{
    "Error: VM name is null"
    return $retVal
}

if (-not $hvServer)
{
    "Error: hvServer is null"
    return $retVal
}

if (-not $testParams)
{
    "Error: No testParams provided"
    "This script requires the test case number as the test parameters"
    return $retVal
}

#
# Find the testParams we require.  Complain if not found
#
$TC_COVERED = $null
$rootDir = $null

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    if ($fields[0].Trim() -eq "TC_COVERED")
    {
        $TC_COVERED = $fields[1].Trim()
    }
     if ($fields[0].Trim() -eq "RootDir")
    {
        $rootDir = $fields[1].Trim()
    }
                
}

if (-not $TC_COVERED)
{
    "Error: Missing testParam Value to be added"
    return $retVal
}

#
# Change the working directory to where we need to be
#
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

cd $rootDir

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers ${TC_COVERED}" | Out-File -Append $summaryLog


$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
   Import-module .\HyperVLibV2Sp1\Hyperv.psd1 
}

#
# Verify that the Intrinsic values are available and can be read.
#

filter Import-IntrinsicXml
{
    $CimXml = [Xml]$_
    $CimObj = New-Object -TypeName System.Object
    foreach ($CimProperty in $CimXml.SelectNodes("/INSTANCE/PROPERTY"))
    {
        $CimObj | Add-Member -MemberType NoteProperty -Name $CimProperty.NAME -Value $CimProperty.VALUE
    }
    $CimObj
}

$Vm = Get-WmiObject -Namespace root\virtualization -Query "Select * From Msvm_ComputerSystem Where ElementName=`'$VmName`'"
$Kvp = Get-WmiObject -Namespace root\virtualization -Query "Associators of {$Vm} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent"
if ($kvp.GuestIntrinsicExchangeItems.Count -eq 0)
{
 Write-Output "Error: intrinsic values are not available in pool 2" | Out-File -Append $summaryLog
 return $retVal
}
Write-host "Verifying the Intrinsic values on guest"
$Kvp.GuestIntrinsicExchangeItems | Import-IntrinsicXml

Write-Output " Intrinsic values are verfied and available on guest OS" | Out-File -Append $summaryLog
$retVal = $true

return $retVal

