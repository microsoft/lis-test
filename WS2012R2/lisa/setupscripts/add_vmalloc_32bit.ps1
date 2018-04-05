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
    Pretest script that will add the vmalloc parameter to grub boot.
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)
$retVal = $true
$NICcount = 0
$remotescript = "add_vmalloc.sh"
$value = 128

############################################################################
#
# Main entry point for script
#
############################################################################
#
# Check input arguments
#
if ($vmName -eq $null -or $vmName.Length -eq 0)
{
    "Error: VM name is null"
    return $false
}

if ($hvServer -eq $null -or $hvServer.Length -eq 0)
{
    "Error: hvServer is null"
    return $false
}

if ($testParams -eq $null -or $testParams.Length -lt 3)
{
    "Error: No testParams provided"
    return $false
}

#
# Source the TCUtils.ps1 file so we have access to the 
# functions it provides.
#
if (Test-Path ".\setupScripts\TCUtils.ps1")
{
    . .\setupScripts\TCUtils.ps1
}
else
{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}

Start-VM -name $vmname -computer $hvServer

$sts = WaitForVMToStartKVP $vmname $hvserver 200
if ( -not $sts[-1]) {
	"VM not starting"
	return $False
}

$ipv4 = GetIPv4 $vmName $hvServer
if ( $ipv4 -eq $null ) {
	"Could not get IPv4 of VM"
	return $False
}

#
# Parse the testParams string
#
$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    if ($fields.count -ne 2)
    {
        continue
    }
    $rValue = $fields[1].Trim()

    switch ($fields[0].Trim())
    {      
    "ipv4"       { $ipv4     = $rValue }
    "sshKey"     { $sshKey    = $rValue }
    "NIC"        { $NICcount += 1 }
    default      {}       
    }
}

$is_rhel6 = SendCommandToVm $ipv4 $sshKey "grep -i -r `'6\.[0-9]`' /etc/*-release"
if (-not $is_rhel6[-1]) {
	"Error at geting centos/rhel version"
	Stop-VM -name $vmname -computername $hvserver
	"Shuting down the VM."

	$sts = WaitForVMToStop $vmname $hvserver 200
	if (-not $sts[-1]) {
		"VM not stopping"
		return $False
	}
	return $False
}
if ( ($NICcount -ge 2) -and ($is_rhel6 -eq $True) ) {
	$gen = (Get-VM -name $vmname -computer $hvserver).Generation
	
	$value = 128 + ($NICcount - 1) * 80
	$value = $value.ToString() + "MB"
	$sts = SendCommandToVm $ipv4 $sshKey "echo value=$value >> /root/constants.sh"
	if (-not $sts[-1]) {
		"Error at inserting constant on VM"
		Stop-VM -name $vmname -computername $hvserver
		"Shuting down the VM."

		$sts = WaitForVMToStop $vmname $hvserver 200
		if (-not $sts[-1]) {
			"VM not stopping"
			return $False
		}
		return $False
	}
	$sts = SendCommandToVm $ipv4 $sshKey "echo VmGeneration=$gen >> /root/constants.sh"
	if (-not $sts[-1]) {
		"Error at inserting constant on VM"
		Stop-VM -name $vmname -computername $hvserver
		"Shuting down the VM."

		$sts = WaitForVMToStop $vmname $hvserver 200
		if (-not $sts[-1]) {
			"VM not stopping"
			return $False
		}
		return $False
	}
	$sts = SendCommandToVm $ipv4 $sshKey "dos2unix /root/constants.sh"
	$sts = SendFileToVM $ipv4 $sshkey "./remote-scripts/ica/utils.sh" "/root/utils.sh" $True
	if (-not $sts[-1]) {
		"Could not send utils.sh to VM"
	}
	$sts = RunRemoteScript $remotescript
	if ( -not $sts[-1]) {
		"Error at executing $remotescript on VM"
		Stop-VM -name $vmname -computername $hvserver
		"Shuting down the VM."

		$sts = WaitForVMToStop $vmname $hvserver 200
		if (-not $sts[-1]) {
			"VM not stopping"
			return $False
		}
		return $False
	}
	Stop-VM -name $vmname -computername $hvserver
	"Shuting down the VM."

	$sts = WaitForVMToStop $vmname $hvserver 200
	if (-not $sts[-1]) {
		"VM not stopping"
		return $False
	}
}

"Shuting down the VM."
Stop-VM -name $vmname -computername $hvserver

$sts = WaitForVMToStop $vmname $hvserver 200
if (-not $sts[-1]) {
	"VM not stopping"
	return $False
}

return $True
