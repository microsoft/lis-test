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
 Configure Dynamic Memory for given Virtual Machines.

 Description:
   Configure Dynamic Memory parameters for a set of Virtual Machines.
   The testParams have the format of:

      vmName=Name of a VM, enableDM=[yes|no], minMem= (decimal) [MB|GB|%], maxMem=(decimal) [MB|GB|%], 
      startupMem=(decimal) [MB|GB|%], memWeight=(0 < decimal < 100) 

   vmName is the name of a existing Virtual Machines.

   enable specifies if Dynamic Memory should be enabled or not on the given Virtual Machines.
     accepted values are: yes | no

   minMem is the minimum amount of memory assigned to the specified virtual machine(s)
    the amount of memory can be specified as a decimal followed by a qualifier
    valid qualifiers are: MB, GB and % . %(percent) means percentage of free Memory on the host

   maxMem is the maximum memory amount assigned to the virtual machine(s)
    the amount of memory can be specified as a decimal followed by a qualifier
    valid qualifiers are: MB, GB and % . %(percent) means percentage of free Memory on the host
      
   startupMem is the amount of memory assigned at startup for the given VM
    the amount of memory can be specified as a decimal followed by a qualifier
    valid qualifiers are: MB, GB and % . %(percent) means percentage of free Memory on the host

   memWeight is the priority a given VM has when assigning Dynamic Memory
    the memory weight is a decimal between 0 and 100, 0 meaning lowest priority and 100 highest.

   The following is an example of a testParam for configuring Dynamic Memory

       "vmName=sles11x64sp3;enableDM=yes;minMem=512MB;maxMem=50%;startupMem=1GB;memWeight=20"

   All setup and cleanup scripts must return a boolean ($true or $false)
   to indicate if the script completed successfully or not.
   
   .Parameter vmName
    Name of the VM to remove NIC from .

    .Parameter hvServer
    Name of the Hyper-V server hosting the VM.

    .Parameter testParams
    Test data for this test case

    .Example
    setupScripts\DM_CONFIGURE_MEMORY -vmName sles11sp3x64 -hvServer localhost -testParams "vmName=sles11x64sp3;enableDM=yes;minMem=512MB;maxMem=50%;startupMem=1GB;memWeight=20"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)


# Convert a string to int64 for use with the Set-VMMemory cmdlet
function ConvertToMemSize([String] $memString, [String]$hvServer)
{
    $memSize = [Int64] 0

    if ($memString.EndsWith("MB"))
    {
        $num = $memString.Replace("MB","")
        $memSize = ([Convert]::ToInt64($num)) * 1MB
    }
    elseif ($memString.EndsWith("GB"))
    {
        $num = $memString.Replace("GB","")
        $memSize = ([Convert]::ToInt64($num)) * 1GB
    }
    elseif( $memString.EndsWith("%"))
    {
        $osInfo = Get-WMIObject Win32_OperatingSystem -ComputerName $hvServer
        if (-not $osInfo)
        {
            "Error: Unable to retrieve Win32_OperatingSystem object for server ${hvServer}"
            return $False
        }

        $hostMemCapacity = $osInfo.FreePhysicalMemory * 1KB
        $memPercent = [Convert]::ToDouble("0." + $memString.Replace("%",""))
        $num = [Int64] ($memPercent * $hostMemCapacity)

        # Align on a 4k boundry
        $memSize = [Int64](([Int64] ($num / 2MB)) * 2MB)
    }
    # we received the number of bytes
    else
    {
        $memSize = ([Convert]::ToInt64($memString))
    }

    return $memSize
}


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

if (-not $testParams)
{
  "Error: testParams is null"
  return $false
}

[string]$tPvmName = $null
$tpEnabled = $null
[int64]$tPminMem = 0
[int64]$tPmaxMem = 0
[int64]$tPstartupMem = 0
[int64]$tPmemWeight = -1


#
# Parse the testParams string, then process each parameter
#
$params = $testParams.Split(';')

foreach ($p in $params)
{
    $temp = $p.Trim().Split('=')
    
    if ($temp.Length -ne 2)
    {
        # Ignore and move on to the next parameter
        continue
    }
    
    $vm = $null

    if ($temp[0].Trim() -eq "vmName")
    {
        $tPvmName = $temp[1]

        $vm = Get-VM -Name $tPvmName -ComputerName $hvServer -ErrorAction SilentlyContinue

        if (-not $vm)
        {
            "Error: VM ${tPvmName} does not exist"
            return $False
        }

        "vmName: $tPvmName"
        
    }
    elseif($temp[0].Trim() -eq "enableDM")
    {

      if ($temp[1].Trim() -ilike "yes")
      {
        $tpEnabled = $true
      }
      else 
      {
        $tpEnabled = $false
      }

      "dm enabled: $tpEnabled"

    }
    elseif($temp[0].Trim() -eq "minMem")
    {

      $tPminMem = ConvertToMemSize $temp[1].Trim() $hvServer

      if ($tPminMem -le 0)
      {
        "Error: Unable to convert minMem to int64."
        return $false
      }

      "minMem: $tPminMem"

    }

    elseif($temp[0].Trim() -eq "maxMem")
    {
      $tPmaxMem = ConvertToMemSize $temp[1].Trim() $hvServer

      if ($tPmaxMem -le 0)
      {
        "Error: Unable to convert maxMem to int64."
        return $false
      }

      "maxMem: $tPmaxMem"

    }

    elseif($temp[0].Trim() -eq "startupMem")
    {

      $tPstartupMem = ConvertToMemSize $temp[1].Trim() $hvServer

      if ($tPstartupMem -le 0)
      {
        "Error: Unable to convert minMem to int64."
        return $false
      }

      "startupMem: $tPstartupMem"

    }

    elseif($temp[0].Trim() -eq "memWeight")
    {
      $tPmemWeight = [Convert]::ToInt32($temp[1].Trim())

      if ($tPmemWeight -lt 0 -or $tPmemWeight -gt 100)
      {
        "Error: Memory weight needs to be between 0 and 100."
        return $false
      }

      "memWeight: $tPmemWeight"

    }


    # check if we have all variables set
    if ($tPvmName -and ($tpEnabled -eq $false -or $tpEnabled -eq $true) -and $tPminMem -and $tPmaxMem -and $tPstartupMem -and ([int64]$tPmemWeight -ge [int64]0))
    {

      # make sure VM is off
      if (Get-VM -Name $tPvmName |  Where { $_.State -like "Running" })
      {

        "Stopping VM $tPvmName"
        Stop-VM $tPvmName -force
        
        if (-not $?)
        {
          "Error: Unable to shut $tPvmName down (in order to set Memory parameters)"
          return $false
        }
        
        # wait for VM to finish shutting down
        $timeout = 60
        while (Get-VM -Name $tPvmName |  Where { $_.State -notlike "Off" })
        {
          if ($timeout -le 0)
          {
            "Error: Unable to shutdown $tPvmName"
            return $false
          }
          
          start-sleep -s 5
          $timeout = $timeout - 5
        }
        
      }

      if ($tpEnabled)
      {

        Set-VMMemory -vmName $tPvmName -ComputerName $hvServer -DynamicMemoryEnabled $tpEnabled `
                      -MinimumBytes $tPminMem -MaximumBytes $tPmaxMem -StartupBytes $tPstartupMem `
                      -Priority $tPmemWeight
      }
      else 
      {
          Set-VMMemory -vmName $tPvmName -ComputerName $hvServer -DynamicMemoryEnabled $tpEnabled `
                    -StartupBytes $tPstartupMem
      }
      if (-not $?)
      {
        "Error: Unable to set VM Memory for $tPvmName."
        "DM enabled: $tpEnabled"
        "min Mem: $tPminMem"
        "max Mem: $tPmaxMem"
        "startup Mem: $tPstartupMem"
        "weight Mem: $tPmemWeight"
        return $false
      }

      # reset all variables
      [string]$tPvmName = $null
      $tpEnabled = $null
      [int64]$tPminMem = 0
      [int64]$tPmaxMem = 0
      [int64]$tPstartupMem = 0
      [int64]$tPmemWeight = -1

    }

}

Write-Output $true
return $true