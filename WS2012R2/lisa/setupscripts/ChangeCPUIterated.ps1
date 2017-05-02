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
    Test LIS and shutdown with multiple CPUs

.Description
    Test LIS and shutdown with multiple CPUs
    The XML test case definition for this test would
    look similar to the following:
            <test>
            <testName>Multi_Cpu_Test</testName>
            <testScript>setupscripts\ChangeCPUIterated.ps1</testScript>
            <timeout>800</timeout>
            <noReboot>False</noReboot>
            <testParams>
                <param>TC_COVERED=CORE-11</param>
            </testParams>
        </test>

.Parameter
    Name of VM to test

.Parameter
    Name of Hyper-V server hosting the VM

.Parameter
    Semicolon separated list of test parameters

.Example

#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false
$timeout = 200
$maxCPUs = 2
$Vcpu = 0
$sshKey = $null
$ipv4 = $null
$rootDir = $null

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

$params = $testParams.Split(";")

foreach ($p in $params)
{
    $fields = $p.Split("=")
    if ($fields.Length -ne 2)
    {
        # Malformed - just ignore
        continue
    }

    switch ($fields[0].Trim())
    {
    "sshKey"     { $sshKey    = $fields[1].Trim() }
    "ipv4"       { $ipv4      = $fields[1].Trim() }
    "rootdir"    { $rootDir   = $fields[1].Trim() }
    "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    default   {}
    }
}

#
# Make sure the required test params are provided
#
if ($null -eq $sshKey)
{
    "Error: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4)
{
    "Error: Test parameter ipv4 was not specified"
    return $False
}

if (-not $rootDir)
{
    "Error: Test parameter rootDir was not specified"
    return $False
}

#
# Change the working directory for the log files
# Delete any previous summary.log file, then create a new one
#
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist"
    return $retVal
}
cd $rootDir

# Delete any previous summary.log file, then create a new one
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue

Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Source the TCUtils.ps1 file
#
. .\setupscripts\TCUtils.ps1

#######################################################################
#
# Main script block
#
#######################################################################
$OSInfo = get-wmiobject -computername $hvServer win32_processor
if ($OSInfo)
{
    if ($OSInfo.Caption -match '.2008 R2.'){
        $guest_max_cpus = 4
    }else{
        $guest_max_cpus = 64
        if($OSInfo.Caption -match '.2016.'){
            $generation = (Get-VM -Name $vmName -ComputerName $hvServer).Generation
            if($generation -eq 2){
                $guest_max_cpus = 240
            }
        }
    }
    #
    # Get the total number of Logical processor
    #
    $maxCPUs =  ($OSInfo.NumberOfLogicalProcessors | Measure-Object -sum).sum
    if($maxCPUs -gt $guest_max_cpus){
        $maxCPUs = $guest_max_cpus
    }
}

#
# Shutdown VM.
#
Stop-VM -Name $vmName -ComputerName $hvServer
if (-not $?)
{
    "Error: Unable to Shut Down VM!"
    return $False
}

$sts = WaitForVMToStop $vmName $hvServer $timeout
if (-not $sts)
{
    "Error: Unable to Shut Down VM!"
    return $False
}

#
# Now iterate through different CPU counts and assign to VM
#
for ($numCPUs = $maxCPUs ;$numCPUs -gt 1 ;[int]$numCPUs = $numCPUs /2 )
{
    if ($numCPUs -gt 1 -and $numCPUs -lt 2) {
        $numCPUs = 1;
    }

    $cpu = Set-VM -Name $vmName -ComputerName $hvServer -ProcessorCount $numCPUs
    if ($? -eq "True")
    {
       "CPU count updated to $numCPUs"
    }
    else
    {
        "Error: Unable to update CPU count to $numCPUs !"
        return $False
    }

    Start-VM -Name $vmName -ComputerName $hvServer
    #wait for ssh to start
    if (-not (WaitForVMToStartSSH $ipv4 $timeout))
    {
        "Error: Test case timed out for VM to be running again!"
        return $False
    }

    "Info: VM $vmName started with $numCPUs cores"
    $Vcpu = .\bin\plink -i ssh\${sshKey} root@${ipv4} "cat /proc/cpuinfo | grep processor | wc -l"
    if($Vcpu -eq $numCPUs)
    {
        "CPU count inside VM is $numCPUs"
        $retVal=$true

        Stop-VM -Name $vmName -ComputerName $hvServer
        if (-not $?)
        {
            "Error: Unable to Shut Down VM!"
            return $False
        }

        #
        # Making sure the VM is stopped
        #
        $sts = WaitForVMToStop $vmName $hvServer $timeout
        if (-not $sts)
        {
            "Error: Unable to Shut Down VM!"
            return $False
        }
    }
    else
    {
        "Error: Wrong vCPU count detected on the VM!"
        return $False
    }
}

return $retVal
