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
    This is a setup script that will run before the VM is booted.
    This script will change the number of CPUs on the specified
    virtual machine, hosted on the specified Hyper-V server.

    Setup scripts (and cleanup scripts) are run in a separate
    PowerShell environment, so they do not have access to the
    environment running the ICA scripts.  Since this script uses
    The PowerShell Hyper-V library, these modules must be loaded
    by this startup script.

    The .xml entry for this script could look like either of the
    following:

        <setupScript>SetupScripts\ChangeCPUIterated.ps1</setupScript>

  The ICA scripts will always pass the vmName, hvServer, and a
  string of testParams from the test definition separated by
  semicolons.  For example, an example would be:

        "iteration=0;iterationParam=1"

  The setup (and cleanup) scripts need to parse the testParam
  string to find any parameters it needs.

  All setup and cleanup scripts must return a boolean ($true or $false)
  to indicate if the script completed successfully or not.


.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

#####################################################################
#
# CheckCurrentStateFor()
#
#####################################################################
function CheckCurrentStateFor([String] $vmName, [UInt16] $newState)
{
    $stateChanged = $False
    $vm = Get-VM $vmName -server $hvServer
    if ($($vm.EnabledState) -eq $newState)
    {
        $stateChanged = $True
    }
    return $stateChanged
}

#####################################################################

$retVal = $false

#
# Check input arguments
#
if ($vmName -eq $null)
{
    "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null)
{
    "Error: hvServer is null"
    return $retVal
}

if ($testParams -eq $null -or $testParams.Length -lt 3)
{
    "Error: No testParams provided"
    "       The script $MyInvocation.InvocationName requires the VCPU test parameter"
    return $retVal
}

$rootDir = $null
$tcCovered = "Undefined"
$ipv4 = $null

"Parsing testParams"
$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {
        "ipv4" { $ipv4 = $fields[1].Trim() }
        "rootDir" { $rootDir = $fields[1].Trim() }
        "sshKey" { $sshKey = $fields[1].Trim() }
        "TC_COVERED" { $tcCovered = $fields[1].Trim() }
        default {}
    }
}

cd $rootDir

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

. .\setupscripts\TCUtils.ps1

#
# for debugging - to be removed
#
"ChangeCPUIterated.ps1 -vmName $vmName -hvServer $hvServer -testParams $testParams"

#
# do a sanity check on the value provided in the testParams
#
$maxCPUs = 2
$procs = get-wmiobject -computername $hvServer win32_processor
if ($procs)
{
    if ($procs -is [array])
    {
        $maxCPUs = $procs[0].NumberOfCores
    }
    else
    {
        $maxCPUs = $procs.NumberOfCores
    }
}

#
# Now iterate through different CPU counts and assign to VM
#
for ($numCPUs = $maxCPUs ;$numCPUs -gt 1 ;$numCPUs = $numCPUs /2 ) 

{
#
# Stop the VM to export it.
#
    $testCaseTimeout = 180
    
    Stop-VM -VM $vmName -Server $hvServer -force    
    while ($testCaseTimeout -gt 0)
    {
        if ( (CheckCurrentStateFor $vmName ([UInt16] [VMState]::stopped)))
        {
            break
        }
        Start-Sleep -seconds 2
        $testCaseTimeout -= 2
    }
    
    $cpu = Set-VMCPUCount -VM $vmName -CPUCount $numCPUs -server $hvServer

    if ($cpu -is [System.Management.ManagementObject])
    {
        write-host "CPU count updated to $numCPUs"
        $retVal = $true
    }
    else
    {
        write-host "Error: Unable to update CPU count"
        return $false
    }

    Start-VM -VM $vmName -Server $hvServer 

   
    $testCaseTimeout = 300
    while ($testCaseTimeout -gt 0)
    {
        if ( (TestPort $ipv4) )
        {
            break
        }
        Start-Sleep -seconds 2
        $testCaseTimeout -= 2
    }


    "Info: VM $vmName started with $numCPUs cores"
    $Vcpu = .\bin\plink -i .\ssh\${sshKey} root@${ipv4} "cat /proc/cpuinfo | grep processor | wc -l"
    if($Vcpu -eq $numCPUs)
    {
        "CPU count inside VM is $numCPUs"
        echo "CPU count inside VM is : $numCPUs" >> $summaryLog
        $retVal=$true

    }
    else
    {
        "Error: Wrong vCPU count detected on the VM!"
        return $False
    }
}


return $retVal
