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
# AddKeyvalue.ps1
#
# Description:
#     This is a PowerShell test case script to add a key value pair to the KVP Pool 0 on guest OS.
#               
#
#    This test case should be run after the KVP Basic test. 
#
############################################################################
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
    "This script requires the Key & value as the test parameters"
    return $retVal
}

#
# Find the testParams we require.  Complain if not found
#
$Key = $null
$Value = $null


$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    if ($fields[0].Trim() -eq "Key")
    {
        $Key = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "Value")
    {
        $Value = $fields[1].Trim()
    }
     if ($fields[0].Trim() -eq "RootDir")
    {
        $rootDir = $fields[1].Trim()
    }
            
}

if (-not $Key)
{
    "Error: Missing testParam Key to be added"
    return $retVal
}
if (-not $Value)
{
    "Error: Missing testParam Value to be added"
    return $retVal
}


#
# Import the HyperV module
#

$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
   Import-module .\HyperVLibV2Sp1\Hyperv.psd1 
}

#
# Add the Key Value pair to the Pool 0 on guest OS.
#

$VMManagementService = Get-WmiObject -class "Msvm_VirtualSystemManagementService" -namespace "root\virtualization" -ComputerName $hvServer
$VMGuest = Get-WmiObject -Namespace root\virtualization -ComputerName $hvServer -Query "Select * From Msvm_ComputerSystem Where ElementName='$VmName'"
$Msvm_KvpExchangeDataItemPath = "\\$hvServer\root\virtualization:Msvm_KvpExchangeDataItem"
$Msvm_KvpExchangeDataItem = ([WmiClass]$Msvm_KvpExchangeDataItemPath).CreateInstance()
$Msvm_KvpExchangeDataItem.Source = 0

$tmp = $Msvm_KvpExchangeDataItem.PSBase.GetText(1)

write-output "Adding Key value pair to Pool 0" $key, $Value

$Msvm_KvpExchangeDataItem.Name = $Key
$Msvm_KvpExchangeDataItem.Data = $Value
$result = $VMManagementService.AddKvpItems($VMGuest, $Msvm_KvpExchangeDataItem.PSBase.GetText(1))
$job = [wmi]$result.Job

while($job.jobstate -lt 7) {
	$job.get()
} 

if ($job.ErrorCode -ne 0)
{
Write-host "Error while adding the key value pair"  
Write-Host "Add key value Job error code" $job.ErrorCode
return $retVal
}

Write-Output $job.JobStatus
$retVal = $true
Write-host "Key value pair got added successfully to Pool0 on guest" 
 
return $retVal

