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
    Modify an existing KVP item.

.Description
    Modifie an existing KVP item on a Linux VM.  The operation
    is performed on the host side.
     
    A sample XML test definition for this test case would look
    similar to the following: 

        <test>  <!-- ModifyPool0KVPDataOnGuest -->
            <testName>KVP_Modify_Key_Values</testName>
            <testScript>setupscripts\ModifyKeyValue.ps1</testScript>
            <files>setupscripts\ModifyKeyValue.ps1</files>
            <timeout>600</timeout>
            <onError>Abort</onError>
            <noReboot>False</noReboot>
            <testparams>
                <param>TC_COVERED=KVP-0//3</param>
                <param>Key=EEE</param>
                <param>Value=555</param>
                <param>Pool=0</param>
            </testparams>
        </test>
.Parameter vmName
    Name of the VM to read intrinsic data from.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\ModifyKeyValue.ps1 -vmName "myVm" -hvServer "localhost -TestParams "key=aaa;value=222"

.Link
    None.
#>



############################################################################
#
# Main script body
#
############################################################################

param([string] $vmName, [string] $hvServer, [string] $testParams)


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
    "       This script requires the Key & value test parameters"
    return $False
}

#
# Find the testParams we require.  Complain if not found
#
$Key = $null
$Value = $null
$rootDir = $null
$tcCovered = "unknown"

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    switch ($fields[0].Trim())
    {
    "key"        { $key       = $fields[1].Trim() }
    "value"      { $value     = $fields[1].Trim() }
    "rootDir"    { $rootDir   = $fields[1].Trim() }
    "tc_covered" { $tcCovered = $fields[1].Trim() }
    default   {}  # unknown param - just ignore it
    }
}        

if (-not $key)
{
    "Error: Missing testParam Key to be added"
    return $False
}
if (-not $value)
{
    "Error: Missing testParam Value to be added"
    return $False
}

if (-not $rootDir)
{
    "Warn : no rootDir test parameter was supplied"
}
else
{
    cd $rootDir
}

#
# Creating the summary file
#
$summaryLog  = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers ${tcCovered}" | Out-File -Append $summaryLog

#
# Modify the Key Value pair from the Pool 0 on guest OS. If the Key is already not present, will return proper message.
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

"Info : Modifying Key '${key}'to '${Value}'"

$Msvm_KvpExchangeDataItem.Source = 0
$Msvm_KvpExchangeDataItem.Name = $Key
$Msvm_KvpExchangeDataItem.Data = $Value
$result = $VMManagementService.ModifyKvpItems($VMGuest, $Msvm_KvpExchangeDataItem.PSBase.GetText(1))
$job = [wmi]$result.Job

#
# Check if the modify worked
#
while($job.jobstate -lt 7) {
	$job.get()
}

if ($job.ErrorCode -ne 0)
{
    "Error: while modifying the key value pair"
    "Error: Job error code = $($Job.ErrorCode)"

    if ($job.ErrorCode -eq 32773)
    {  
        "Error: Key does not exist.  Key = '${key}'"
        return $False
    }
    else
    {
        "Error: Unable to modify key"
        return $False
    }
}

if ($job.Status -ne "OK")
{
    "Error: KVP modify job did not complete with status OK"
    return $False
}

"Info : KVP item successfully modified"

return $True
