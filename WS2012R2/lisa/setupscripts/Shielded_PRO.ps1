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
# Linux Shielded VMs Provisioning automation functions
#

function Create-CredentialObject {
param(
    [Parameter(Mandatory=$true)]
    [string] $User,

    [Parameter(Mandatory=$true)]
    [string] $Password
)
    return New-Object System.Management.Automation.PSCredential($User, (ConvertTo-SecureString $Password -AsPlainText -Force))
}

function Generate-PDKFile ([string] $shielding_type, [string] $shareName)
{
    $owner = Get-HgsGuardian -Name 'Owner'
	if (-not $owner){
		return $false
	}
    $guardian = Get-HgsGuardian -Name 'TestFabric'
    if(-not $guardian) {
        return $false
    }
	
	Start-Sleep -s 10
	if (Test-Path $test_vsc_path) {
		Remove-Item $test_vsc_path -Force
	}
	Save-VolumeSignatureCatalog -TemplateDiskPath ${test_vhd_path} –VolumeSignatureCatalogPath ${test_vsc_path}
	if (-not $?) {
		return $false
	}

	New-ShieldingDataFile -ShieldingDataFilePath $test_pdk_path -Owner $owner –Guardian $guardian `
		–VolumeIDQualifier (New-VolumeIDQualifier -VolumeSignatureCatalogFilePath $test_vsc_path -VersionRule Equals) `
		-WindowsUnattendFile '.\Infrastructure\Windows_unattend_file.xml' -policy $shielding_type -EA SilentlyContinue
	if (-not $?) {
        return $false
    }

	$sts = Upload_File $test_pdk_path $shareName
	if (-not $?) {
        return $false
    }
	
	$sts = Upload_File ${test_vhd_path} $shareName
	if (-not $?) {
        return $false
    }

	return $true
}

# Copy VHD to given share
function Upload_File ([string] $fileName, [string] $share_name)
{
	if (-not (Test-Path $share_name)) {
		return $false
	}
	
	$sts = Copy-Item -Path $fileName -Destination $share_name -Force
	if (-not $?) {
        return $false
    }

	return $true
}

# Copy template from share to default VHDx path
function Copy_template_from_share ([string] $share_name)
{
	# Make a copy of the encypted VHDx for testing only
	$destinationVHD = $defaultVhdPath + "LSVM-PRO_test.vhdx"
    Copy-Item -Path $(Get-ChildItem $share_name -Filter *PRO.vhdx).FullName -Destination $destinationVHD -Force
    if (-not $?) {
        return $false
    }
	return $true
}

# Create dependency VM
function CreateVM ([string]$dep_vhd)
{
	# Test dependency VHDx path
    $sts = Test-Path $dep_vhd
    if (-not $?) {
        return $false
    }
	
	# Copy dependency VHDx
	$dependency_vhd_path = $test_vhd_path -replace 'PRO','PRO-Dependency'
	Copy-Item -Path $dep_vhd -Destination $dependency_vhd_path -Force
    if (-not $?) {
        return $false
    }
	
	# Make a new VM
	$newVm = New-VM -Name 'PRO_Dependency' -VHDPath $dependency_vhd_path -MemoryStartupBytes 2048MB -SwitchName 'External' -Generation 1
	if (-not $?) {
        return $false
    }
	
	# Attach the test VHDx to the VM
	$sts = Add-VMHardDiskDrive -VMName 'PRO_Dependency' -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1 -Path $test_vhd_path
	if (-not $?) {
        return $false
    }
	
	# Start VM and get IP
	$sts = Start-VM -Name 'PRO_Dependency'
	$waitTimeOut = 200
	while ($waitTimeOut -gt 0) {
		$vmIp = $(Get-VMNetworkAdapter -VMName 'PRO_Dependency' ).IpAddresses
		if ($vmIp -ne "") {
			$waitTimeOut = 0
		}
		Start-Sleep -s 5
	}
	
	Start-Sleep -s 20
	$vmIpAddr = $(Get-VMNetworkAdapter -VMName 'PRO_Dependency' ).IpAddresses[0]
	return $vmIpAddr
}

# Modify VSC on the template
function Modify_VSC ([string] $sshKey, [string] $dep_IP, [string] $shareName)
{
	# Mount the template
	$sts =  echo y | .\bin\plink.exe -i ssh\$sshKey root@${dep_IP} "mkdir lsvmefi && mount /dev/sdb1 lsvmefi"
	
	# Remove VSC
	$vsc_removal = .\bin\plink.exe -i ssh\$sshKey root@${dep_IP} "vsc_location=`$(find -name '*vsc') && rm -f `$vsc_location"
	if ($vsc_removal -ne $null) {
		return $false
	}
	
	# Dettach VHD
	$umount = .\bin\plink.exe -i ssh\$sshKey root@${dep_IP} "umount /dev/sdb1"

	# Stop VM and delete it
	$sts = CleanupDependency 'PRO_Dependency'    
	if (-not $?) {
        return $false
    }
	
	# Upload the modified template to share
	$sts = Upload_File $test_vhd_path $shareName
	if (-not $?) {
        return $false
    }
	
	return $true
}

# Modify boot partition on the template
function Modify_boot_partition ([string] $sshKey, [string] $dep_IP, [string] $shareName)
{
	# Unlock sdb2 - boot partition
	$sts =  echo y | .\bin\plink.exe -i ssh\$sshKey root@${dep_IP} "yes passphrase | cryptsetup luksOpen /dev/sdb2 encrypted_boot"
	# Mount the template
	$sts =  echo y | .\bin\plink.exe -i ssh\$sshKey root@${dep_IP} "mkdir boot_part && mount /dev/mapper/encrypted_boot boot_part/"
	
	# Erase config files
	$config_removal = .\bin\plink.exe -i ssh\$sshKey root@${dep_IP} "cd boot_part && rm -rf config*"
	if ($config_removal -ne $null) {
		return $false
	}
	
	# Remove VHD
	$umount = .\bin\plink.exe -i ssh\$sshKey root@${dep_IP} "umount /dev/mapper/encrypted_boot"

	# Stop VM and delete it
	$sts = CleanupDependency 'PRO_Dependency'    
	if (-not $?) {
        return $false
    }
	
	# Upload the modified template to share
	$sts = Upload_File $test_vhd_path $shareName
	if (-not $?) {
        return $false
    }
	
	return $true
}

# Modify root partition on the template
function Modify_root_partition ([string] $sshKey, [string] $dep_IP, [string] $shareName)
{
	# Unlock sdb3 - root partition
	$sts =  echo y | .\bin\plink.exe -i ssh\$sshKey root@${dep_IP} "yes passphrase | cryptsetup luksOpen /dev/sdb3 encrypted_root"
	
	# Change VG name to avoid conflicts
	$sts = .\bin\plink.exe -i ssh\$sshKey root@${dep_IP} "lvm_uuid=`$(vgdisplay | grep UUID | tail -1 | awk {'print `$3'}) && vgrename `$lvm_uuid 'Test_LVM'"
	
	# Make VG active
	$sts = .\bin\plink.exe -i ssh\$sshKey root@${dep_IP} "vgchange -ay && mkdir root_part"
	
	# Mount the root partition
	$sts = .\bin\plink.exe -i ssh\$sshKey root@${dep_IP} "mount /dev/Test_LVM/root root_part"
	
	# Erase files from root folder
	$file_removal = .\bin\plink.exe -i ssh\$sshKey root@${dep_IP} "cd root_part/root/ && rm -rf *"
	if ($file_removal -ne $null) {
		return $false
	}
	
	# Remove VHD
	$umount = .\bin\plink.exe -i ssh\$sshKey root@${dep_IP} "umount /dev/Test_LVM/root"

	# Stop VM and delete it
	$sts = CleanupDependency 'PRO_Dependency'    
	if (-not $?) {
        return $false
    }
	
	# Upload the modified template to share
	$sts = Upload_File $test_vhd_path $shareName
	if (-not $?) {
        return $false
    }
	
	return $true
}

# Copy template and PDK to the Guarded host
function Copy_Files_to_GH ([string] $GH_IP, [string] $share_path, $gh_creds, $share_creds)
{	
	$copy_files_cmd = Invoke-Command $GH_IP -Credential $gh_creds -ErrorAction SilentlyContinue -ScriptBlock { `
		$sts = $true
		$defaultVhdPath = $(Get-VMHost).VirtualHardDiskPath
		if (-not $defaultVhdPath.EndsWith("\")) {
			$defaultVhdPath += "\"
		}
		$destination_template = $defaultVhdPath + "LSVM-PRO_test.vhdx"
		$destination_pdk = $defaultVhdPath + "PDK_Test.pdk"
		New-PSDrive -PSProvider FileSystem -Name "PRO_Test" -Root $using:share_path -Credential $using:share_creds -ErrorAction SilentlyContinue
		
		Copy-Item -Path $(Get-ChildItem $using:share_path -Filter *test.vhdx).FullName -Destination $destination_template -Force -ErrorAction SilentlyContinue
		if (-not $?){
			$sts = $false
		}
		
		Copy-Item -Path $(Get-ChildItem $using:share_path -Filter *.pdk).FullName -Destination $destination_pdk -Force -ErrorAction SilentlyContinue
		if (-not $?){
			$sts = $false
		}
		Remove-PSDrive -Name "PRO_Test"
		return $sts
	}	
	Restart-Service WinRm -Force
	return $copy_files_cmd
}

function Provision_VM ([string] $GH_IP, $gh_creds, [string] $change_fsk)
{
	$provision_vm_cmd = Invoke-Command $GH_IP -Credential $gh_creds -ScriptBlock { `
		# Prepare files
		$sts = $true
		$defaultVhdPath = $(Get-VMHost).VirtualHardDiskPath
		if (-not $defaultVhdPath.EndsWith("\")) {
			$defaultVhdPath += "\"
		}
		$VMName = "LSVM_PRO_Test"
		$TemplateDiskPath = $defaultVhdPath + "LSVM-PRO_test.vhdx"
		$PdkFile = $defaultVhdPath + "PDK_Test.pdk"
		$VMPath = $defaultVhdPath + "Provision_Test\"
		$sts_folder = Remove-Item -Recurse -Force -Path $VMPath -EA SilentlyContinue
		$sts_folder = New-Item -ItemType directory -Path $VMPath
		
		$VmVhdPath = $VMPath + '\' + $VMName + '.vhdx'
		$fskFile = $VMPath + '\' + $VMName + '.fsk'
		if ($using:change_fsk -eq 'yes') {
			New-ShieldedVMSpecializationDataFile -ShieldedVMSpecializationDataFilePath $fskfile -SpecializationDataPairs @{ '@TimeZone@' = 'Pacific Standard Time'}
			$content = Get-Content $fskfile
			Set-Content -Path $fskfile -Value $content.Substring(20,33)
		}
		elseif ($using:change_fsk -eq 'extra') {
			New-ShieldedVMSpecializationDataFile -ShieldedVMSpecializationDataFilePath $fskfile -SpecializationDataPairs @{ '@ComputerName@' = "$VMName"; '@TimeZone@' = 'Pacific Standard Time'; '@extraTestInfo@'  = 'Extra'}
		}
		else {
			New-ShieldedVMSpecializationDataFile -ShieldedVMSpecializationDataFilePath $fskfile -SpecializationDataPairs @{ '@ComputerName@' = "$VMName"; '@TimeZone@' = 'Pacific Standard Time' }
		}
		Copy-Item -Path $TemplateDiskPath -Destination $VmVhdPath -Force
		
		# Create VM
		$vm = New-VM -Name $VMName -Generation 2 -VHDPath $VmVhdPath -MemoryStartupBytes 2GB -Path $VMPath -SwitchName 'External' -erroraction Stop
		Start-Sleep -s 5 
		Set-VMFirmware -VM $vm -SecureBootTemplate OpenSourceShieldedVM
		
		$kp = Get-KeyProtectorFromShieldingDataFile -ShieldingDataFilePath $PdkFile
		$sts_vmkp = Set-VMkeyProtector -VM $vm -KeyProtector $kp
		
		# Get PDK security policy
		$importpdk = Invoke-CimMethod -ClassName  Msps_ProvisioningFileProcessor -Namespace root\msps -MethodName PopulateFromFile -Arguments @{FilePath=$PdkFile }
		$cimvm = Get-CimInstance  -Namespace root\virtualization\v2 -Class Msvm_ComputerSystem -Filter "ElementName = '$VMName'"
		 
		$vsd = Get-CimAssociatedInstance -InputObject $cimvm -ResultClassName "Msvm_VirtualSystemSettingData"
		$vmms = gcim -Namespace root\virtualization\v2 -ClassName Msvm_VirtualSystemManagementService
		$ssd = Get-CimAssociatedInstance -InputObject $vsd -ResultClassName "Msvm_SecuritySettingData"
		$ss = Get-CimAssociatedInstance -InputObject $cimvm -ResultClassName "Msvm_SecuritySErvice"
		$cimSerializer = [Microsoft.Management.Infrastructure.Serialization.CimSerializer]::Create()
		$ssdString = [System.Text.Encoding]::Unicode.GetString($cimSerializer.Serialize($ssd, [Microsoft.Management.Infrastructure.Serialization.InstanceSerializationOptions]::None))
		$result = Invoke-CimMethod -InputObject $ss -MethodName SetSecurityPolicy -Arguments @{"SecuritySettingData"=$ssdString;"SecurityPolicy"=$importPdk.ProvisioningFile.PolicyData}
		 
		# Initialize Shileded VM
		$sts_vmtpm = Enable-VMTPM -vm $vm
		$sts_init = Initialize-ShieldedVM -VM $vm -ShieldingDataFilePath $PdkFile -ShieldedVMSpecializationDataFilePath $fskfile -EA SilentlyContinue
		if (-not $?){
			$sts = $false
		}
		
		# Wait for provisioning completion
		$provisionComplete = $false
		while (-not $provisionComplete) {
			# The Get-ShieldedVMProvisioningStatus cmdlet can throw errors if it completes provisioning quickly and the job CIM is gone
			$status = Get-ShieldedVMProvisioningStatus -VM $vm -ErrorAction SilentlyContinue
			if ($status -eq $null) {
				$event = Get-winevent -logname *shield* |? {$_.Id -eq 407}
				if ($event -eq $null) {
					$hasErrors = $true
					$sts = $false
				}
				$provisionComplete = $true
			}
			elseif ($status.PercentComplete -eq 100) {
				Write-Host $status
				$provisionComplete = $true
				if ($status.JobState -eq 10) {
					Write-Error "The provisioning session is complete, but failed to provision the VM."
					$HasErrors = $true
					$sts = $false
				}

				# Find event
				Start-Sleep -Seconds 5
				$event = Get-winevent -logname *shield* |? {$_.Id -eq 407}
				if ($event -eq $null) {
					Write-Error "Shielded VM Event 407 (denotes a successful shielded VM provision) is not present"
					$hasErrors = $true
					$sts = $false
				}
			}
			elseif ($status.ErrorCode -ne 0) {
				Write-Error ("Error found with code " + $status.ErrorCode)
				$errorCode = $status.ErrorCode
				Write-Error $status.ErrorDescription
				$hasErrors = $true
				$sts = $false
				$provisionComplete = $true
			}
			else {
				Write-Host ("Percent complete: " + $status.PercentComplete)
				Write-Host ($status.Jobstatus)
				Write-Host "Sleeping for 30 seconds"
				Start-Sleep -Seconds 30
			}
		}
		return $sts
		}
	
	Restart-Service WinRm -Force
	return $provision_vm_cmd
}

function Get_VM_ipv4 ([string] $GH_IP, $gh_creds)
{
	$get_ipv4_cmd = Invoke-Command $GH_IP -Credential $gh_creds -ScriptBlock { `
		$waitTimeOut = 200
		while ($waitTimeOut -gt 0) {
			$vmIp = $(Get-VMNetworkAdapter -VMName "LSVM_PRO_Test" ).IpAddresses
			if ($vmIp -ne "") {
				$waitTimeOut = 0
			}
			Start-Sleep -s 5
		}
		Start-Sleep -s 20
		$vmIpAddr = $(Get-VMNetworkAdapter -VMName "LSVM_PRO_Test" ).IpAddresses[0]
		
		return $vmIpAddr
	}
	Restart-Service WinRm -Force
	return $get_ipv4_cmd
}

function Verify_provisioned_VM([string]$vm_ipv4, [string]$sshKey)
{
	# Command that verifies call traces in system logs
	$cmd_trace = '[[ -f "/var/log/syslog" ]] && logfile="/var/log/syslog" || logfile=/var/log/messages && cat $logfile | grep Call'
	
	# Send cmd
	$sts =  echo y | .\bin\plink.exe -i ssh\$sshKey root@${vm_ipv4} $cmd_trace
	
	return $?
}

function Clean_provisioned_VM ([string] $GH_IP, $gh_creds)
{
	$clean_cmd = Invoke-Command $GH_IP -Credential $gh_creds -ScriptBlock { `
		$sts = $true
		# Clean up
		$cmd_sts = Stop-VM -Name "LSVM_PRO_Test" -TurnOff
		if (-not $?){
			$sts = $false
		}
		Start-Sleep -s 5
		# Delete New VM created
		$cmd_sts = Remove-VM -Name "LSVM_PRO_Test" -Confirm:$false -Force
		if (-not $?){
			$sts = $false
		}
		Start-Sleep -s 5
		return $sts
	}
	
	Restart-Service WinRm -Force
	return $clean_cmd
}

# Construct global variables
$defaultVhdPath = $(Get-VMHost).VirtualHardDiskPath
if (-not $defaultVhdPath.EndsWith("\")) {
	$defaultVhdPath += "\"
}
$test_vhd_path = $defaultVhdPath + "LSVM-PRO_test.vhdx"
$test_vsc_path = $defaultVhdPath + "VSC_Test.vsc"
$test_pdk_path = $defaultVhdPath + "PDK_Test.pdk"