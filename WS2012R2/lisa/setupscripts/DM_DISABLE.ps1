#####################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
#####################################################################

<#
.Synopsis
 Disable Dynamic Memory for given Virtual Machine.

 Description:
   Disable Dynamic Memory parameters for a set of Virtual Machines.
   The testParams have the format of:

      vmName=Name of a VM, enableDM=[yes|no], staticMem=(decimal) [MB|GB|%],memWeight=(0-100)

    vmName is the name of an existing Virtual Machine.

    staticMem is the minimum amount of memory assigned to the specified virtual machine(s)
    the amount of memory can be specified as a decimal followed by a qualifier
    valid qualifiers are: MB, GB and % . %(percent) means percentage of free Memory on the host
    this value will be set as minimum, maximum and startup Memory.

   memWeight is the priority a given VM has when assigning Dynamic Memory
    the memory weight is a decimal between 0 and 100, 0 meaning lowest priority and 100 highest.
    The default value should be 50.

   All setup and cleanup scripts must return a boolean ($true or $false)
   to indicate if the script completed successfully or not.

   .Parameter vmName
    Name of the VM to configure.

    .Parameter hvServer
    Name of the Hyper-V server hosting the VM.

    .Parameter testParams
    Test data for this test case

    .Example
    setupScripts\DM_DISABLE.ps1 -vmName vm -hvServer localhost -testParams "enableDM=no;staticMem=512MB;memWeight=50"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

Set-PSDebug -Strict

#
# Check input arguments
#
if (-not $vmName)
{
    "Error: VM name is null. "
    return $false
}

if (-not $hvServer)
{
    "Error: hvServer is null"
    return $false
}

if ($testParams -eq $null)
{
    "Error: testParams is null"
    return $False
}

# change working directory to root dir
$testParams -match "RootDir=([^;]+)"
if (-not $?)
{
    "Mandatory param RootDir=Path; not found!"
    return $false
}
$rootDir = $Matches[1]

if (Test-Path $rootDir)
{
    Set-Location -Path $rootDir
    if (-not $?)
    {
        "Error: Could not change directory to $rootDir !"
        return $false
    }
    "Changed working directory to $rootDir"
}
else
{
    "Error: RootDir = $rootDir is not a valid path"
    return $false
}

# call DM_CONFIGURE_MEMORY.ps1
if (Test-Path ".\setupScripts\DM_CONFIGURE_MEMORY.ps1")
{
    #nothing to do
}
else
{
    "Error: Could not find setupScripts\DM_CONFIGURE_MEMORY.ps1"
    return $false
}

[string]$dmTestParam = ""
$tpEnabled = $null
#Parse the testParams string
$params = $testParams.Split(';')

foreach ($p in $params)
{
    $temp = $p.Trim().Split('=')

    if ($temp.Length -ne 2)
    {
        # Ignore and move on to the next parameter
        continue
    }

    if($temp[0].Trim() -eq "enableDM")
    {
      $tpEnabled = $temp[1].Trim()
    }
}
# if no enableDM parameter, raise error
if (-not $tpEnabled)
{
  "Error: no enableDM value received."
  return $false
}

#if there is enableDM=yes, replace as enableDM=no
$dmTestParam = $testParams.replace("enableDM=yes","enableDM=no")
"Got params $dmTestParam"

$res = .\setupScripts\DM_CONFIGURE_MEMORY.ps1 -vmName $vmName -hvServer $hvServer -testParams $dmTestParam

if (-not $res[-1])
{
    "Error: Unable to configure dynamic memory!"
    return $false
}

return $true
