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
	Configure Runtime Memory Resize for a given VM.

	.Parameter vmName
	Name of the VM which will be asssigned a new Memory value

	.Parameter hvServer
	Name of the Hyper-V server hosting the VM.

	.Parameter testParams
	Test data for this test case

	.Example
	setupScripts\Runtime_Mem_Configure.ps1 -vmName VM -hvServer localhost -testParams "vmName=VM;startupMem=2GB"
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
if (-not $vmName){
    "Error: VM name is null. "
    return $false
}

if (-not $hvServer){
    "Error: hvServer is null"
    return $false
}

if (-not $testParams){
  "Error: testParams is null"
  return $false
}

# No dynamic memory needed; set false as default
$DM_Enabled = $false

[int64]$startupMem = 0

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

    elseif($temp[0].Trim() -eq "startupMem")
    {

      $startupMem = ConvertToMemSize $temp[1].Trim() $hvServer

      if ($startupMem -le 0)
      {
        "Error: Unable to convert startupMem to int64."
        return $false
      }

      "startupMem: $startupMem"
    }

    # check if we have all variables set
    if ($vmName -and $DM_Enabled -eq $false -and $startupMem)
    {

      # make sure VM is off
      if (Get-VM -Name $vmName -ComputerName $hvServer |  Where { $_.State -like "Running" })
      {

        "Stopping VM $vmName"
        Stop-VM $vmName -force

        if (-not $?)
        {
          "Error: Unable to shut $vmName down (in order to set Memory parameters)"
          return $false
        }

        # wait for VM to finish shutting down
        $timeout = 60
        while (Get-VM -Name $vmName -ComputerName $hvServer |  Where { $_.State -notlike "Off" })
        {
          if ($timeout -le 0)
          {
            "Error: Unable to shutdown $vmName"
            return $false
          }

          start-sleep -s 5
          $timeout = $timeout - 5
        }

      }

      # Verify VM Version is greater than 7
      $version = Get-VM -Name $vmName -ComputerName $hvServer | select -ExpandProperty Version
      [int]$version = [convert]::ToInt32($version[0],10)

      if ( $version -lt 7 )
      {
        "Error: $vmName is version $version. It needs to be version 7 or greater"
        return $false
      }
      
      Set-VMMemory -vmName $vmName -ComputerName $hvServer -DynamicMemoryEnabled $DM_Enabled `
                      -StartupBytes $startupMem 
      if (-not $?)
      {
        "Error: Unable to set VM Memory for $vmName."
        "DM enabled: $DM_Enabled"
        "startup Mem: $startupMem"
        return $false
      }
    }

}

Write-Output $true
return $true