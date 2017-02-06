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
    This script shuts down all dependency VMs

.Example
    <test>
        <testName>VerifyVF_basic</testName>
        <testScript>SR-IOV_VerifyVF_basic.sh</testScript>
        <files>remote-scripts\ica\SR-IOV_VerifyVF_basic.sh,remote-scripts/ica/utils.sh</files> 
        <setupScript>
            <file>setupscripts\RevertSnapshot.ps1</file>
            <file>setupscripts\SR-IOV_enable.ps1</file>
        </setupScript> 
        <noReboot>False</noReboot>
        <testParams>
            <param>TC_COVERED=??</param>
            <param>VM2NAME=vm1</param>
            <param>VM3NAME=vm2</param>
            <param>VM4NAME=vm3/param>
            <param>REMOTE_SERVER=serverName</param>
        </testParams>
        <timeout>600</timeout>
    </test>
#>

param ([String] $vmName, [String] $hvServer, [string] $testParams)

# Shut Down function
function ShutDownVM([String]$vmToShutDown, [String]$remoteSrv) 
{
    Stop-VM $vmToShutDown -ComputerName $remoteSrv -force

    if (-not $?)
    {
        "ERROR: Failed to shutdown $vmToShutDown"
        return $false
    }

    # wait for VM to finish shutting down
    $timeout = 60
    while (Get-VM -Name $vmToShutDown -ComputerName $remoteSrv|  Where { $_.State -notlike "Off" })
    {
        if ($timeout -le 0)
        {
            "ERROR: Failed to shutdown $vmToShutDown"
            return $false
        }

        start-sleep -s 5
        $timeout = $timeout - 5
    }
}

#
# Main body
#
# Process parameters
$params = $testParams.Split(';')
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim()) {
        "VM2NAME" { $vm2Name = $fields[1].Trim() }
        "VM3NAME" { $vm3Name = $fields[1].Trim() }
        "VM4NAME" { $vm4Name = $fields[1].Trim() }
        "REMOTE_SERVER" { $remoteServer = $fields[1].Trim() }
        default   {}  # unknown param - just ignore it
    }
}

if (-not $remoteServer) {
    $remoteServer = $hvServer
}

# Shut down VMs
for ($i=2; $i -lt 5; $i++){
    $vm_Name = Get-Variable -Name "vm${i}Name" -ValueOnly -ErrorAction SilentlyContinue

    if ($vm_Name) {
        if (Get-VM -Name $vm_Name -ComputerName $remoteServer -ErrorAction SilentlyContinue) {
            ShutDownVM $vm_Name $remoteServer
            $vm_Name = $null
        }
        else {
            ShutDownVM $vm_Name $hvServer
            $vm_Name = $null
        }
    }
}

return $True