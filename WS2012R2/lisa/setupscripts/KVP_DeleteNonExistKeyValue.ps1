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
    Try to Delete a Non-Exist KVP item from a Linux guest.
.Description
    Try to Delete a Non-Exist KVP item from pool 0 on a Linux guest.
   
.Parameter vmName
    Name of the VM to read intrinsic data from.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\KVP_DeleteNonExistKeyValue.ps1 -vmName "myVm" -hvServer "localhost -TestParams "key=aaa;value=222"

.Link
    None.
#>



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
    "     : This script requires key & value test parameters"
    return $False
}

#
# Find the testParams we require.  Complain if not found
#
"Info : Parsing test parameters"

$key = $null
$value = $null
$rootDir = $null
$tcCovered = "Unknown"

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

"Info : Checking for required test parameters"

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
    "Warn : no rootDir test parameter specified"
}
else
{
    cd $rootDir
}

#
# creating the summary file
#
$summaryLog  = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers ${tcCovered}" | Out-File -Append $summaryLog

#
# Delete the Non-Existing Key Value pair from the Pool 0 on guest OS. If the Key is already present, will return proper message.
#
"Info : Creating VM Management Service object"
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

"Info : Creating Msvm_KvpExchangeDataItem object"

$Msvm_KvpExchangeDataItemPath = "\\$hvServer\root\virtualization\v2:Msvm_KvpExchangeDataItem"
$Msvm_KvpExchangeDataItem = ([WmiClass]$Msvm_KvpExchangeDataItemPath).CreateInstance()
if (-not $Msvm_KvpExchangeDataItem)
{
    "Error: Unable to create Msvm_KvpExchangeDataItem object"
    return $False
}
"Info : Detecting Host version of Windows Server"
$osInfo = GWMI Win32_OperatingSystem -ComputerName $hvServer
if (-not $osInfo)
{
    "Error: Unable to collect Operating System informatioin"
    return $False
}

"Info : Deleting Key '${key}' from Pool 0"

$Msvm_KvpExchangeDataItem.Source = 0
$Msvm_KvpExchangeDataItem.Name = $Key
$Msvm_KvpExchangeDataItem.Data = $Value
$result = $VMManagementService.RemoveKvpItems($VMGuest, $Msvm_KvpExchangeDataItem.PSBase.GetText(1))
$job = [wmi]$result.Job

while($job.jobstate -lt 7) {
	$job.get()
} 
Write-Output $job.ErrorCode
Write-Output $job.Status
#
# Due to a change in behavior between Server 2012 and 2012 R2, we need to modify
# acceptance criteria based on the version of the HyperVisor.
#
switch ($osInfo.BuildNumber)
{
	"9200" # Server 2012
	{
		if ($job.ErrorCode -eq 32773)
		{
			"Info : RemoveKvpItems() correctly returned 32773"
			return $True
		}
		"Error: RemoveKVPItems() returned error code $($job.ErrorCode) rather than 32773"
		return $False
	}
	"9600" # Server 2012 R2
	{
		if ($job.ErrorCode -eq 0)
		{
			"Info : Server 2012 R2 returns success even when the KVP item does not exist"
			return $True
		}
		"Error: RemoveKVPItems() returned error code $($job.ErrorCode)"
		return $False
	}
	Default # An unsupported version of Windows Server
	{
		#
		# We should only hit this case when testing on Windows.Next
		#
		"Error: Unsupported build of Windows Server"
		return $False
	}
}
