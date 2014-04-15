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
    Add a value to a guest VM from the host.

.Description
    Use WMI to add a key value pair to the KVP Pool 0 on guest
    a Linux guest VM.  A typical xml test case definition would
    look similar to the following:
    <test>
        <testName>WriteKVPDataToGuest</testName>
        <testScript>VerifyKeyValue.sh</testScript>
        <files>remote-scripts\ica\VerifyKeyValue.sh,tools/KVP/kvp_client</files>
        <PreTest>setupScripts\AddKeyValue.ps1</PreTest>
        <timeout>600</timeout>
        <onError>Abort</onError>
        <noReboot>False</noReboot>
        <testparams>
            <param>TC_COVERED=KVP-02</param>
            <param>Key=EEE</param>
            <param>Value=555</param>
            <param>Pool=0</param>
            <param>rootDir=D:\lisa\trunk\lisablue</param>
        </testparams>
    </test>

.Parameter vmName
    Name of the VM to read intrinsic data from.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\AddKeyValue.ps1 -vmName "myVm" -hvServer "localhost -TestParams "key=aaa;value=111"

.Link
    None.
#>



############################################################################
#
# Main script body
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
    return $False
}

if (-not $hvServer)
{
    "Error: hvServer is null"
    return $False
}

if (-not $testParams)
{
    "Error: No testParams provided"
    "This script requires the Key & value as the test parameters"
    return $False
}

#
# Find the testParams we require.  Complain if not found
#
$Key = $null
$Value = $null
$rootDir = $null

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
    return $False
}
if (-not $Value)
{
    "Error: Missing testParam Value to be added"
    return $False
}

if (-not $rootDir)
{
    "Warn : No rootDir test parameter was provided"
}
else
{
    cd $rootDir
}

write-output "Info : Adding Key=value of: ${key}=${value}"

#
# Add the Key Value pair to the Pool 0 on guest OS.
#
$VMManagementService = Get-WmiObject -class "Msvm_VirtualSystemManagementService" -namespace "root\virtualization\v2" -ComputerName $hvServer
if (-not $VMManagementService)
{
    "Error: Unable to create a VMManagementService object"
    return $False
}

$VMGuest = Get-WmiObject -Namespace root\virtualization\v2 -ComputerName $hvServer -Query "Select * From Msvm_ComputerSystem Where ElementName='$VmName'"
if (-not $VMGuest)
{
    "Error: Unable to create VMGuest object"
    return $False
}

$Msvm_KvpExchangeDataItemPath = "\\$hvServer\root\virtualization\v2:Msvm_KvpExchangeDataItem"
$Msvm_KvpExchangeDataItem = ([WmiClass]$Msvm_KvpExchangeDataItemPath).CreateInstance()
if (-not $Msvm_KvpExchangeDataItem)
{
    "Error: Unable to create Msvm_KvpExchangeDataItem object"
    return $False
}

#
# Populate the Msvm_KvpExchangeDataItem object
#
$Msvm_KvpExchangeDataItem.Source = 0
$Msvm_KvpExchangeDataItem.Name = $Key
$Msvm_KvpExchangeDataItem.Data = $Value

#
# Set the KVP value on the guest
#
$result = $VMManagementService.AddKvpItems($VMGuest, $Msvm_KvpExchangeDataItem.PSBase.GetText(1))
$job = [wmi]$result.Job

while($job.jobstate -lt 7) {
	$job.get()
} 

if ($job.ErrorCode -ne 0)
{
    "Error: Unable to add KVP value to guest"  
    "       error code $($job.ErrorCode)"
    return $False
}

if ($job.Status -ne "OK")
{
    "Error: KVP add job did not complete with status OK"
    return $False
}

"Info : KVP item added successfully on guest" 
 
return $True
