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
    Test Linux VM boot with maximum supported CPU cores count.

.Description
    Test LIS with maximum CPU cores count supported
    for a Hyper-V VM, based on VM generation and
    distro architecture

.Parameter
    Name of VM to test

.Parameter
    Name of Hyper-V server hosting the VM

.Parameter
    Semicolon separated list of test parameters
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

# default to 64 cores for a generic VM
$guest_max_cpus = 64
$Vcpu = $null
$retVal = $false
$sshKey = $null
$ipv4 = $null
$rootDir = $null

#
# Check input arguments
#
if ($vmName -eq $null) {
    "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null) {
    "Error: hvServer is null"
    return $retVal
}

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    if ($fields.Length -ne 2) {
        # Malformed - just ignore
        continue
    }

    switch ($fields[0].Trim()) {
    "sshKey"     { $sshKey    = $fields[1].Trim() }
    "ipv4"       { $ipv4      = $fields[1].Trim() }
    "rootdir"    { $rootDir   = $fields[1].Trim() }
    default   {}
    }
}

#
# Make sure the required test params are provided
#
if ($null -eq $sshKey) {
    "Error: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4) {
    "Error: Test parameter ipv4 was not specified"
    return $False
}

if (-not $rootDir) {
    "Error: Test parameter rootDir was not specified"
    return $False
}

#
# Change the working directory for the log files
#
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist"
    return $retVal
}
Set-Location $rootDir

# Delete any previous summary.log file, then create a new one
$summaryLog = "${vmName}_summary.log"
Remove-Item $summaryLog -ErrorAction SilentlyContinue

# Source TCUtils.ps1 for test related functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
} else {
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}

#######################################################################
#
# Main script block
#
#######################################################################
$OSInfo = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $hvServer
if ($OSInfo) {
    if ($OSInfo.Caption -match '.2008 R2.') {
        $guest_max_cpus = 4
    } else {
        # Check VM OS architecture and set max CPU allowed
        $linuxArch = .\bin\plink -i ssh\${sshKey} root@${ipv4} "uname -m"
        if ($linuxArch -eq "i686") {
            $guest_max_cpus = 32
        }
        if ($linuxArch -eq "x86_64") {
            $guest_max_cpus = 64
        }

        if ((GetVMGeneration $vmName $hvServer) -eq "2" ) {
            $guest_max_cpus = 240
        }
    }

    #
    # Get the total number of Logical processors
    #
    $maxCPUs =  Get-WmiObject -Class Win32_ComputerSystem -ComputerName $hvServer | `
                Select-Object -ExpandProperty "NumberOfLogicalProcessors"
    if ($guest_max_cpus -gt $maxCPUs) {
        "VM maximum cores is limited by the number of Logical cores: $maxCPUs" | `
        Tee-Object -Append -file $summaryLog
    }
}

#
# Shutdown VM in order to change the cores count
#
try {
    Stop-VM -Name $vmName -ComputerName $hvServer
} catch [system.exception] {
    "Error: Unable to stop VM $vmName!" | Tee-Object -Append -file $summaryLog
    return $False
}

try {
    WaitForVMToStop $vmName $hvServer 200
} catch [system.exception] {
    "Error: Timed out while stopping VM $vmName!" | Tee-Object -Append -file $summaryLog
    return $False
}

Set-VM -Name $vmName -ComputerName $hvServer -ProcessorCount $guest_max_cpus
if ($? -eq "True") {
    "CPU cores count updated to $guest_max_cpus"
} else {
    "Error: Unable to update CPU count to $guest_max_cpus!" | Tee-Object -Append -file $summaryLog
    return $False
}

#
# Start VM and wait for SSH access
#
Start-VM -Name $vmName -ComputerName $hvServer
$new_ipv4 = GetIPv4AndWaitForSSHStart $vmName $hvServer $sshKey 300
if ($new_ipv4) {
    # In some cases the IP changes after a reboot
    Set-Variable -Name "ipv4" -Value $new_ipv4
} else {
    "Error: VM $vmName failed to start after setting $guest_max_cpus vCPUs" | `
    Tee-Object -Append -file $summaryLog
    return $False  
}

#
# Determine how many cores the VM has detected
#
$Vcpu = .\bin\plink -i ssh\${sshKey} root@${ipv4} "cat /proc/cpuinfo | grep processor | wc -l"
if ($Vcpu -eq $guest_max_cpus) {
    "CPU count inside VM is $guest_max_cpus"
    $retVal=$true
} else {
    "Error: Wrong vCPU count of $Vcpu detected on the VM, expected $guest_max_cpus!" | `
    Tee-Object -Append -file $summaryLog
    return $False
}

"VM $vmName successfully started with $guest_max_cpus cores." | Tee-Object -Append -file $summaryLog
return $retVal
