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
.synopsis
    Configure a VM.

.Description
    Configure a VM with the parameters defined in the XML global section, for example vmCpuNumber, vmMemory, etc.
	
.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the test VM.

.Parameter testParams
    Test parameters are a way of passing variables into the test case script.

.Example:
    .\setupscripts\Config-VM.ps1 SLES11SP3X64 localhost "vmCpuNumber=4;vmMemory=20GB;TC_COVERED=PERF-TeraSort;SLAVE_SSHKEY=id_rsa;"
#>


param( [String] $vmName, [String] $hvServer, [String] $testParams )

#display and return params to caller script
$vmName
$hvServer
$testParams

#defined variables used
$vmCpuNumber = 0
$vmMemory = 0GB

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {      
    "vmCpuNumber"  { $vmCpuNumber  = $fields[1].Trim() }
    "vmMemory"     { $vmMemory     = $fields[1].Trim() }
    default        {}       
    }
}

if ($vmCpuNumber -ne 0)
{
    "CPU: $vmCpuNumber"
    Set-VM -ComputerName $hvServer -VMName $vmName -ProcessorCount $vmCpuNumber
}

if ($vmMemory -ne 0GB)
{
    $regex = "(\d+)([G|g|M|m])([B|b])"
    if($vmMemory -match $regex)
    {
        $num=$Matches[1].Trim()
        $mg=$Matches[2].Trim()
        $b=$Matches[3].Trim()
		
		[int64]$memorySize = 1024 * 1024
        if ($mg.Contains('G'))
        {
            $memorySize = $memorySize * 1024 * $num
        }
        else
        {
            $memorySize = $memorySize * $num
        }

        "Memory: $memorySize Bytes ($($num+$mg+$b))"
        if($memorySize -gt 32 * 1024 * 1024)
        {
            Set-VM -ComputerName $hvServer -VMName $vmName -MemoryStartupBytes $memorySize
        }
        else
        {
            "Memory size is provided but it is too small (should greater than 32MB): $vmMemory"
            return $false
        }
    }
    else
    {
        "Memory size is provided but it is not recognized: $vmMemory. Example: 2GB or 200MB"
        return $false
    }
}

return $true