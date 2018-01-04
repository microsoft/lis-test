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
#
# Linux Shielded VMs TDC automation functions
#

function Get_Full_VHD_Path([string] $vhd_name)
{
    $hostInfo = Get-VMHost
    if (-not $hostInfo) {
        return $false
    }

    $defaultVhdPath = $hostInfo.VirtualHardDiskPath
    if (-not $defaultVhdPath.EndsWith("\")) {
        $defaultVhdPath += "\"
    }

    $full_vhd_path = $defaultVhdPath + $vhd_name
	$tested_vhd_path = $full_vhd_path -replace 'TDC','TDC-Test'
	
	# Make a copy of the encypted VHDx for testing only
    Copy-Item -Path $full_vhd_path -Destination $tested_vhd_path -Force
    if (-not $?) {
        return $false
    }
	
    return $tested_vhd_path
}

function Get_Certificate
{
    # Search certificate
    $thumbprint = ""
    $certificates = Get-ChildItem -Recurse Cert:\LocalMachine\My
    foreach ($certificate in $certificates) {
        if ($certificate.Subject -eq 'CN=Template Disk Signer Certificate'){
            $thumbprint = $certificate.Thumbprint
            break
        }
    }

    # If a certificate was not found, create one. Else, import the existing one
    if ($thumbprint -eq "") {
        $signcert = New-SelfSignedCertificate -Subject 'CN=Template Disk Signer Certificate'
    }
    else {
        $signcert = Get-Item Cert:\LocalMachine\My\$thumbprint       
    }

    return $signcert
}

function CleanupDependency ([string]$vmName)
{
    # Clean up
    $sts = Stop-VM -Name $vmName -TurnOff

    # Delete New VM created
    $sts = Remove-VM -Name $vmName -Confirm:$false -Force
}

function Run_TDC ([string] $vhd_path, $signcert)
{	
    # Make the Template
	try {
		Protect-TemplateDisk -Path $vhd_path -TemplateName "Shielded_TDC-Testing" -Version '1.0.0.0' -Certificate $signcert -ProtectedTemplateTargetDiskType 'PreprocessedLinux'
	}
	catch {
		return $false
	}
    
	return $true
}

function Verify_TDC ([string] $vhd_path, [string]$dep_vhd, [string]$sshKey)
{
	# Test dependency VHDx path
    $sts = Test-Path $dep_vhd
    if (-not $?) {
        return $false
    }
	
	# Copy dependency VHDx
	$dependency_vhd_path = $vhd_path -replace 'TDC','TDC-Dependency'
	Copy-Item -Path $dep_vhd -Destination $dependency_vhd_path -Force
    if (-not $?) {
        return $false
    }
	
	# Make a new VM
	$newVm = New-VM -Name 'TDC_Dependency' -VHDPath $dependency_vhd_path -MemoryStartupBytes 2048MB -SwitchName 'External' -Generation 1
	if (-not $?) {
        return $false
    }
	
	# Attach the test VHDx to the VM
	$sts = Add-VMHardDiskDrive -VMName 'TDC_Dependency' -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1 -Path $vhd_path
	if (-not $?) {
        return $false
    }
	
	# Start VM and get IP
	$sts = Start-VM -Name 'TDC_Dependency'
	$waitTimeOut = 200
	while ($waitTimeOut -gt 0) {
		$vmIp = $(Get-VMNetworkAdapter -VMName 'TDC_Dependency' ).IpAddresses
		if ($vmIp -ne "") {
			$waitTimeOut = 0
		}
		Start-Sleep -s 5
	}
	
	Start-Sleep -s 20
	$vmIpAddr = $(Get-VMNetworkAdapter -VMName 'TDC_Dependency' ).IpAddresses[0]
	
	# Mount the template
	$sts =  echo y | .\bin\plink.exe -i ssh\$sshKey root@${vmIpAddr} "mkdir lsvmefi && mount /dev/sdb1 lsvmefi"
	
	# Check for vsc file and bootos.wim
	$bootOS = .\bin\plink.exe -i ssh\$sshKey root@${vmIpAddr} "find -name 'bootos.wim'"
	if ($bootOS -eq $null) {
		return $false
	}
	
	$vscFile = .\bin\plink.exe -i ssh\$sshKey root@${vmIpAddr} "find -name '*vsc'"
	if ($vscFile -eq $null) {
		return $false
	}
	
	# Check for encryption on sdb2 and sdb3
	$sts = .\bin\plink.exe -i ssh\$sshKey root@${vmIpAddr} "mount /dev/sdb2 /mnt"
	if ($?) {
        return $false
    }
	
	$sts = .\bin\plink.exe -i ssh\$sshKey root@${vmIpAddr} "mount /dev/sdb3 /mnt"
	if ($?) {
        return $false
    }
	
	return $true
}

function Copy_vhdx_from_share ([string] $vhd_no_lsvmtools)
{
	# Test VHDx path
    $sts = Test-Path $vhd_no_lsvmtools
    if (-not $?) {
        return $false
    }
	
    $defaultVhdPath = $(Get-VMHost).VirtualHardDiskPath
    if (-not $defaultVhdPath.EndsWith("\")) {
        $defaultVhdPath += "\"
    }

	# Make a copy of the encypted VHDx for testing only
	$destination_vhd_path = $defaultVhdPath + "TDC_no_lsvmtools.vhdx"
    Copy-Item -Path $vhd_no_lsvmtools -Destination $destination_vhd_path -Force
    if (-not $?) {
        return $false
    }
    return $destination_vhd_path
}

function Get_invalid_certificate
{
    # Search invalid certificate
    $thumbprint = ""
    $certificates = Get-ChildItem -Recurse Cert:\CurrentUser\My
    foreach ($certificate in $certificates) {
        if ($certificate.Subject -eq 'CN=Shielded Bad Certificate'){
            $thumbprint = $certificate.Thumbprint
            break
        }
    }

    # If a certificate was not found, create one. Else, import the existing one
    if ($thumbprint -eq "") {
        $signcert = New-SelfSignedCertificate -Type Custom -Subject "CN=Shielded Bad Certificate" `
		-TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.4") -KeyUsage DataEncipherment `
		-KeyAlgorithm RSA -KeyLength 1024 -SmimeCapabilities -CertStoreLocation "Cert:\CurrentUser\My"
    }
    else {
        $signcert = Get-Item Cert:CurrentUser\My\$thumbprint       
    }
	
	return $signcert
}