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
# Linux Deployed Shielded VMs automation functions
#

# Import TCUtils.ps1
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
}
else {
    "ERROR: Could not find setupScripts\TCUtils.ps1"
    return $false
}

# Import NET_Utils.ps1
if (Test-Path ".\setupScripts\NET_UTILS.ps1") {
    . .\setupScripts\NET_UTILS.ps1
}
else {
    "ERROR: Could not find setupScripts\NET_UTILS.ps1"
    return $false
}

function Provision ([string] $VMName, [string] $isClustered)
{
    $hasErrors = $false
    if ($isClustered -eq "yes") {
        $dep_vhd_path = $volume_location + "LSVM-DEP_test.vhdx"
        $dep_pdk_path = $volume_location + "PDK_Test.pdk"
        $VMPath = $volume_location + "Provision_Test\"
        $VmVhdPath = $VMPath + '\' + $VMName + '.vhdx'
        $fskFile = $VMPath + '\' + $VMName + '.fsk'
    }

    $sts_folder = Remove-Item -Recurse -Force -Path $VMPath -EA SilentlyContinue
    $sts_folder = New-Item -ItemType directory -Path $VMPath

    New-ShieldedVMSpecializationDataFile -ShieldedVMSpecializationDataFilePath $fskfile -SpecializationDataPairs @{ '@ComputerName@' = "$VMName"; '@TimeZone@' = 'Pacific Standard Time' }
    Copy-Item -Path $dep_vhd_path -Destination $VmVhdPath -Force

    # Create VM
    $vm = New-VM -Name $VMName -Generation 2 -VHDPath $VmVhdPath -MemoryStartupBytes 2GB -Path $VMPath -SwitchName 'External' -erroraction Stop
    Start-Sleep -s 5 
    Set-VMFirmware -VM $vm -SecureBootTemplate OpenSourceShieldedVM

    $kp = Get-KeyProtectorFromShieldingDataFile -ShieldingDataFilePath $dep_pdk_path
    $sts_vmkp = Set-VMkeyProtector -VM $vm -KeyProtector $kp

    # Get PDK security policy
    $importpdk = Invoke-CimMethod -ClassName  Msps_ProvisioningFileProcessor -Namespace root\msps -MethodName PopulateFromFile -Arguments @{FilePath=$dep_pdk_path }
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
    $sts_init = Initialize-ShieldedVM -VM $vm -ShieldingDataFilePath $dep_pdk_path -ShieldedVMSpecializationDataFilePath $fskfile -EA SilentlyContinue
    if (-not $?){
        $hasErrors = $true
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
            }
            $provisionComplete = $true
        }
        elseif ($status.PercentComplete -eq 100) {
            Write-Host $status
            $provisionComplete = $true
            if ($status.JobState -eq 10) {
                Write-Error "The provisioning session is complete, but failed to provision the VM."
                $hasErrors = $true
            }

            # Find event
            Start-Sleep -Seconds 5
            $event = Get-winevent -logname *shield* |? {$_.Id -eq 407}
            if ($event -eq $null) {
                Write-Error "Shielded VM Event 407 (denotes a successful shielded VM provision) is not present"
                $hasErrors = $true
            }
        }
        elseif ($status.ErrorCode -ne 0) {
            Write-Error ("Error found with code " + $status.ErrorCode)
            $errorCode = $status.ErrorCode
            Write-Error $status.ErrorDescription
            $hasErrors = $true
            $provisionComplete = $true
        }
        else {
            Write-Host ("Percent complete: " + $status.PercentComplete)
            Write-Host ($status.Jobstatus)
            Write-Host "Sleeping for 30 seconds"
            Start-Sleep -Seconds 30
        }
    }

    return $hasErrors
}

function GetDEP_ipv4 ([string] $VMName)
{
    $waitTimeOut = 200
    while ($waitTimeOut -gt 0) {
        $vmIp = $(Get-VMNetworkAdapter -VMName $VMName).IpAddresses
        if ($vmIp -ne "") {
            $waitTimeOut = 0
        }
        Start-Sleep -s 5
    }
    Start-Sleep -s 20
    $vmIpAddr = $(Get-VMNetworkAdapter -VMName $VMName).IpAddresses[0]
    return $vmIpAddr
}

function TakeSnapshot ([string] $VMName)
{
    if ((Get-VM -Name $VMName).State -ne "Off") {
        Stop-VM -Name $VMName -Force -Confirm:$false
    }

    Start-Sleep -s 5
    Checkpoint-VM -Name  $VMName -SnapshotName 'Deployed'
    if (-not $?) {
        return $false
    }

    return $true
}

function ApplySnapshot ([string] $VMName)
{
    if ((Get-VM -Name $VMName).State -ne "Off") {
        Stop-VM -Name $VMName -Force -Confirm:$false
        Start-Sleep -s 5
    }

    $snap = Get-VMSnapshot -VMName $VMName -Name 'Deployed'

    Restore-VMSnapshot $snap -Confirm:$false
    if ($? -ne "True") {
        return $false
    }
    else {
        Start-VM $VMName
        WaitForVMToStartKVP $VMName 'localhost' 150
        return $true
    } 
}

function SendFile ([string] $ipv4, [string] $sshKey, [string] $fileName)
{
    $retVal = SendFileToVM $ipv4 $sshKey ".\remote-scripts\ica\$fileName" "/root/$fileName"
    $retVal = SendCommandToVM $ipv4 $sshKey "cd /root && dos2unix $fileName && chmod u+x $fileName"
    Start-Sleep -s 5
    return $retVal
}

function RunScript ([string] $ipv4, [string] $sshKey, [string] $fileName)
{
    $sts = RunRemoteScript $fileName
    return $sts[-1]
}

function RestartVM ([string] $vmName)
{
    Restart-VM -VMName $vmName -Force
    $timeout = 200
    if (-not (WaitForVMToStartKVP $vmName 'localhost' $timeout )){
        return $false
    }

    Start-Sleep -s 15
    # Get the ipv4, maybe it may change after the reboot
    $ipv4 = GetIPv4 $vmName 'localhost'
    Write-Host "${vmName} IP Address after reboot: ${ipv4}"

    return $ipv4
}

function CompareKernels ([string] $ipv4, [string] $sshKey, [string] $vmName)
{
    # Get the actual kernel version
    $old_kernel_verion = check_kernel
    Write-Host $old_kernel_verion

    # Restart VM
    $ipv4 =  RestartVM $vmName
    Write-Host $ipv4

    # Get the new kernel version
    $new_kernel_verion = check_kernel
    Write-Host $new_kernel_verion

    # Check if kernel version is different
    if ($old_kernel_verion -ne $new_kernel_verion) {
        return $true
    }
    else {
        return $false
    }
}

function UpgradeGrub ([string] $ipv4, [string] $sshKey, [string] $vmName)
{
    # Update grub
    $retVal = SendCommandToVM $ipv4 $sshKey ". shielded_deployed_functions.sh && UpgradeBootComponent && cat state.txt"
    if (-not $retVal) {
        return $false
    }
    # Check status
    $state = .\bin\plink.exe -i ssh\$sshKey root@$ipv4 "cat state.txt"
    if ($state -ne "TestCompleted") {
        return $false
    }

    # Restart VM
    $ipv4 = ""
    $ipv4 =  RestartVM $vmName
    if ($ipv4 -eq "") {
        return $false
    }

    return $true
}

function CopyVHD ([string] $VMName)
{
    if ((Get-VM -Name $VMName).State -ne "Off") {
        Stop-VM -Name $VMName -Force -Confirm:$false
        Start-Sleep -s 5
    }

    # Get parent VHD
    $parent = GetParentVHD $VMName 'localhost'

    # Make a copy
    $parent_clone = $parent -replace '.vhdx','_Clone.vhdx'

    Copy-Item -Path $parent -Destination $parent_clone -Force
    if (-not $?) {
        return $false
    }
    Write-Host $parent_clone
    Set-Variable -Name 'parentClone' -Value $parent_clone -Scope Global
    return $true
}

function ClonedVHD ([string] $sshKey, [string] $VMName)
{
    # Make a new Gen2 VM
    $VMName_clone = $vmName + "_Clone"
    New-ShieldedVMSpecializationDataFile -ShieldedVMSpecializationDataFilePath $fskfile -SpecializationDataPairs @{ '@ComputerName@' = "$VMName_clone"; '@TimeZone@' = 'Pacific Standard Time' }
    $vm = New-VM -Name $VMName_clone -Generation 2 -VHDPath $parentClone -MemoryStartupBytes 1GB -Path $VMPath
    Set-VMFirmware -VM $vm -SecureBootTemplate OpenSourceShieldedVM

    $kp = Get-KeyProtectorFromShieldingDataFile -ShieldingDataFilePath $dep_pdk_path
    $sts_vmkp = Set-VMkeyProtector -VM $vm -KeyProtector $kp

    # Get PDK security policy
    $importpdk = Invoke-CimMethod -ClassName  Msps_ProvisioningFileProcessor -Namespace root\msps -MethodName PopulateFromFile -Arguments @{FilePath=$dep_pdk_path }
    $cimvm = Get-CimInstance  -Namespace root\virtualization\v2 -Class Msvm_ComputerSystem -Filter "ElementName = '$VMName_clone'"
     
    $vsd = Get-CimAssociatedInstance -InputObject $cimvm -ResultClassName "Msvm_VirtualSystemSettingData"
    $vmms = gcim -Namespace root\virtualization\v2 -ClassName Msvm_VirtualSystemManagementService
    $ssd = Get-CimAssociatedInstance -InputObject $vsd -ResultClassName "Msvm_SecuritySettingData"
    $ss = Get-CimAssociatedInstance -InputObject $cimvm -ResultClassName "Msvm_SecuritySErvice"
    $cimSerializer = [Microsoft.Management.Infrastructure.Serialization.CimSerializer]::Create()
    $ssdString = [System.Text.Encoding]::Unicode.GetString($cimSerializer.Serialize($ssd, [Microsoft.Management.Infrastructure.Serialization.InstanceSerializationOptions]::None))
    $result = Invoke-CimMethod -InputObject $ss -MethodName SetSecurityPolicy -Arguments @{"SecuritySettingData"=$ssdString;"SecurityPolicy"=$importPdk.ProvisioningFile.PolicyData}
    Enable-VMTPM -VM $vm

    # Check if the VM boots. It's expected to fail
    Start-VM $VMName_clone
    if (-not $?) {
        return $false
    }
    $timeout = 120
    if (-not (WaitForVMToStartKVP $vmName 'localhost' $timeout )){
        return $false
    }
    else {
        return $true    
    }  
}

function DependencyVM ([string] $dep_vhd)
{
    # Test dependency VHDx path
    $sts = Test-Path $dep_vhd
    if (-not $?) {
        return $false
    }
    $dependency_destination = $dep_vhd_path -replace 'DEP_test','Dependency'
    Copy-Item -Path $dep_vhd -Destination $dependency_destination -Force
    if (-not $?) {
        return $false
    }
    
    # Make a new VM
    $newVm = New-VM -Name 'LSVM_Dependency' -VHDPath $dependency_destination -MemoryStartupBytes 2048MB -SwitchName 'External' -Generation 1
    if (-not $?) {
        return $false
    }
    
    # Attach the test VHDx to the VM
    $sts = Add-VMHardDiskDrive -VMName 'LSVM_Dependency' -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1 -Path $parentClone
    if (-not $?) {
        return $false
    }
    
    # Start VM and get IP
    $sts = Start-VM -Name 'LSVM_Dependency'
    $timeout = 150
    if (-not (WaitForVMToStartKVP 'LSVM_Dependency' 'localhost' $timeout )){
        return $false
    }
    Start-Sleep -s 15
    $ipv4 = GetIPv4 'LSVM_Dependency' 'localhost'
    
    return $ipv4   
}

function VerifyPassphrase ([string] $sshKey, [string] $ipv4)
{
    $sts_root = SendCommandToVM $ipv4 $sshkey "yes passphrase | cryptsetup luksOpen /dev/sdb3 encrypted_root"
    $sts_boot = SendCommandToVM $ipv4 $sshkey "yes passphrase | cryptsetup luksOpen /dev/sdb2 encrypted_boot"

    if (($sts_root -eq $True) -or ($sts_root -eq $True)) {
        return $false
    }
    else {
        return $true
    }
}

function ExportVM ([string] $VMName)
{
    StopVM $VMName "localhost"

    $exportPath = (Get-VMHost).VirtualMachinePath + "\ExportTest\"
    Set-Variable -Name 'export_path' -Value $exportPath -Scope Global
    $vmPath = $exportPath + $vmName +"\"
    Set-Variable -Name 'export_path_vm' -Value $vmPath -Scope Global

    # Delete existing export, if any.
    Remove-Item -Path $vmPath -Recurse -Force -ErrorAction SilentlyContinue

    # Export the VM
    Export-VM -Name $vmName -ComputerName 'localhost' -Path $exportPath -Confirm:$False -Verbose
    if ($? -ne "True") {
        Write-Output "Error while exporting the VM" | Out-File -Append $summaryLog
        return $false
    }

    return $true
}

function ImportVM ([string] $second_GH_name, [string] $VMName)
{
    # Copy exported VM to second Guarded Host
    if (-not (Test-Path $export_path_vm)) {
        return $false
    }

    $remote_defaultVhdPath = $(Get-VMHost -ComputerName $second_GH_name).VirtualHardDiskPath
    if (-not $defaultVhdPath.EndsWith("\")) {
        $defaultVhdPath += "\"
    }
    $copy_path = $remote_defaultVhdPath -replace ':','$'
    $copy_path = '\\' + $second_GH_name + '\' + $copy_path

    Copy-Item $export_path_vm $copy_path -Recurse -Force
    if (-not $?) {
        return $false
    }

    $vmConfig = Invoke-Command $second_GH_name -ScriptBlock{
        $exportPath = $using:remote_defaultVhdPath + $using:VMName + '\Virtual Machines\*.vmcx'
        $(Get-Item $exportPath).Fullname
    }
    Write-Host $vmConfig

    Import-VM -Path $vmConfig -ComputerName $second_GH_name
    if (-not $?) {
        return $false
    }

    return $true
}

function VerifyImport ([string] $second_GH_name, [string] $VMName)
{
    $sts = Start-VM -Name $VMName -ComputerName $second_GH_name
    $timeout = 150
    if (-not (WaitForVMToStartKVP $VMName $second_GH_name $timeout )){
        return $false
    }
    Start-Sleep -s 15
    $ipv4 = GetIPv4 $VMName $second_GH_name   
    if ($ipv4 -ne $null) {
        return $true   
    }
    else {
        return $false
    }
}

function CleanImport ([string] $second_GH_name, [string] $VMName)
{
    # Clean up
    $sts = Stop-VM -Name $VMName -ComputerName $second_GH_name -TurnOff
    $sts = Remove-VM -Name $VMName -ComputerName $second_GH_name -Confirm:$false -Force
}

function CreateDataDisk ([string] $VMName, [string] $sshKey)
{
    StopVM $VMName "localhost"

    # Create the data disk
    $vhdName = $dep_vhd_path -replace 'DEP_test','DataDisk'
    Set-Variable -Name 'dataDiskLocation' -Value $vhdName -Scope Global

    # Delete existing data disk, if any.
    Remove-Item -Path $vhdName -Recurse -Force -ErrorAction SilentlyContinue
    New-Vhd -Path $vhdName -SizeBytes 1GB -Dynamic -BlockSizeBytes 1MB
    if (-not $?) {
        return $false
    }

    # Attach the data disk to the VM
    $sts = Add-VMHardDiskDrive -VMName $VMName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1 -Path $vhdName
    if (-not $?) {
        return $false
    }

    # Start VM and get IP
    $ipv4 = StartVM $VMName 'localhost'
    if (-not (isValidIPv4 $ipv4)) {
        return $false
    }

    # Create partition
    SendCommandToVM $ipv4 $sshkey "(echo n; echo p; echo 2; echo ; echo ;echo w) | fdisk /dev/sdb 2> /dev/null"
    if (-not $?) {
        return $false
    }

    # Format partition && mount it
    SendCommandToVM $ipv4 $sshkey "mkfs -t xfs /dev/sdb2 && mkdir dataDisk && mount /dev/sdb2 dataDisk"
    if (-not $?) {
        return $false
    }

    # Make a new file
    SendCommandToVM $ipv4 $sshkey "echo 'FirstFile' > dataDisk/firstFile"
    if (-not $?) {
        return $false
    }

    return $true
}

function BackupVM ([string] $VMName, [string] $letter)
{
    # Remove Existing Backup Policy
    try { Remove-WBPolicy -all -force }
    Catch { Write-Host 'Removing WBPolicy' }

    # Set up a new Backup Policy
    $policy = New-WBPolicy

    # Set the backup location
    $backupLocation = New-WBBackupTarget -VolumePath $letter
    Set-Variable -Name 'backupLocation' -Value $backupLocation -Scope Global

    # Define VSS WBBackup type
    Set-WBVssBackupOptions -Policy $policy -VssCopyBackup

    # Add the Virtual machines to the list
    $VM = Get-WBVirtualMachine | where vmname -like $VMName
    Add-WBVirtualMachine -Policy $policy -VirtualMachine $VM
    Add-WBBackupTarget -Policy $policy -Target $backupLocation

    # Start the backup
    Write-Host "Backing to $letter"
    Start-WBBackup -Policy $policy

    # Review the results
    $BackupTime = (New-Timespan -Start (Get-WBJob -Previous 1).StartTime -End (Get-WBJob -Previous 1).EndTime).Minutes

    $sts=Get-WBJob -Previous 1
    if ($sts.JobState -ne "Completed" -or $sts.HResult -ne 0) {
        return $false
    }
    Start-Sleep -s 30
    return $true
}

function RestoreVM
{
    # Get BackupSet
    $BackupSet = Get-WBBackupSet -BackupTarget $backupLocation

    # Start restore
    Start-WBHyperVRecovery -BackupSet $BackupSet -VMInBackup $BackupSet.Application[0].Component[0] -Force -WarningAction SilentlyContinue
    $sts=Get-WBJob -Previous 1
    if ($sts.JobState -ne "Completed" -or $sts.HResult -ne 0){
        return $false
    }

    Write-Host "Restore Completed!"
    return $true
}

function CheckRestoreStatus ([string] $sshKey, [string] $mountDisk, [string] $file_location, [string] $file_content)
{
    if (Get-VM -Name $VM_name |  Where { $_.State -notlike "Running" }) {
         # Start VM and get IP
        $ipv4 = StartVM $VM_name 'localhost'
        if (-not (isValidIPv4 $ipv4)) {
            return $false
        }

        # Mount the data disk (if it is required)
        if ($mountDisk -eq 'yes') {
            SendCommandToVM $ipv4 $sshKey "mount /dev/sdb2 dataDisk"
            if (-not $?) {
                return $false
            }    
        }   
    }

    # Check the second file. It should not be present anymore
    $sts = SendCommandToVM $ipv4 $sshKey "cat $file_location | grep $file_content"
    if (-not $sts) {
        return $true
    }
    else {
        return $false
    }
}

function ModifyGrub ([string] $ipv4, [string] $sshKey, [string] $vmName)
{
    # Update grub
    $retVal = SendCommandToVM $ipv4 $sshKey ". shielded_deployed_functions.sh && AddSerial"
    if (-not $retVal) {
        return $false
    }
    # Check status
    $state = .\bin\plink.exe -i ssh\$sshKey root@$ipv4 "cat state.txt"
    if ($state -ne "TestCompleted") {
        return $false
    }

    StopVM $vmName "localhost"
    return $true
}

function BackupClean
{
    try { 
        Remove-WBBackupSet -BackupTarget $backupLocation -Force -WarningAction SilentlyContinue 
    }
    Catch { 
        Write-Host "No existing backup's to remove"
    }
}

function AddComPort ([string] $VMName)
{
    # Get VM Security. We need to know if it's type is Shielded or EncryptionSupported
    if ($(Get-VMSecurity $VMName).Shielded -eq $False) {
        $isShielded = 'no'
    }
    else {
        $isShielded = 'yes'
    }
    # Add COM Port
    Set-VMComPort -vmName $VMName -ComputerName 'localhost' -Number 2 -Path "\\.\pipe\log"

    # Start icaserial
    $currentPath = $pwd.Path
    $jobName = "COM_Reader"
    Remove-Item COM.log -Force -EA SilentlyContinue
    $job = $(Start-Job -Name $jobName -ScriptBlock { Set-Location $args[0]; .\bin\icaserial.exe READ \\localhost\pipe\log | Out-File COM.log } -ArgumentList $currentPath)

    # Start VM
    $ipv4 = StartVM $VMName 'localhost'
    if (-not (isValidIPv4 $ipv4)) {
        return $false
    }

    # Stop icaserial
    Stop-Job -Id $job.id

    # If it's shielded, logs should be empty. If it's not shielded, logs should have boot logs
    if ($isShielded -eq 'no') {
        if ($(Get-Item .\COM.log -EA SilentlyContinue).Length -gt 5kb) {
            return $true
        }
        else {
            return $false
        }
    }
    else {
        if ($(Get-Item .\COM.log -EA SilentlyContinue).Length -gt 1kb) {
            return $false
        }
        else {
            return $true
        }    
    }
}

function ModifyBoot ([string] $ipv4, [string] $sshKey, [string] $VMName)
{
    # Mount the template and make the changes
    $retVal = SendCommandToVM $ipv4 $sshKey "mkdir lsvmefi && mount /dev/sdb1 lsvmefi"
    if (-not $retVal) {
        return $false
    }
    $retVal = SendCommandToVM $ipv4 $sshKey "cd lsvmefi/EFI/boot && rm -rf lsvm* sealedkeys"
    if (-not $retVal) {
        return $false
    }
    $retVal = SendCommandToVM $ipv4 $sshKey "umount /dev/sdb1"
    if (-not $retVal) {
        return $false
    }

    # Clean VM
    CleanupDependency 'LSVM_Dependency'
    
    # Attach the VHD to the existing VMName
    Remove-VMHardDiskDrive -VMName $VMName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0
    if (-not $?) {
        return $false
    }
    Add-VMHardDiskDrive -VMName $VMName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -Path $parentClone
    if (-not $?) {
        return $false
    }

    $ipv4 = StartVM $VMName 'localhost'
    if (-not (isValidIPv4 $ipv4)) {
        return $true
    }
    else {
        return $false 
    }   
}

function DisableSecureBoot ([string] $VMName)
{
    StopVM $VMName "localhost"
    Set-VMFirmware -VMName $VMName -EnableSecureBoot Off
    if (-not $?) {
        return $false
    }

    $ipv4 = StartVM $VMName 'localhost'
    if (-not (isValidIPv4 $ipv4)) {
        return $true
    }
    else {
        return $false  
    }
}

function StopVM ([string] $VMName, [string] $hvServer)
{
    if ((Get-VM -Name $VMName).State -ne "Off") {
        Stop-VM -Name $VMName -ComputerName $hvServer -Confirm:$false
        Start-Sleep -s 5
    }
}

function StartVM ([string] $VMName, [string] $hvServer)
{
    # Start VM and get IP
    $sts = Start-VM -Name $VMName -ComputerName $hvServer 
    $timeout = 150
    if (-not (WaitForVMToStartKVP $VMName $hvServer $timeout )){
        return $false
    }
    Start-Sleep -s 15
    $ipv4 = GetIPv4 $VMName $hvServer
    return $ipv4
}

function WriteDataOnVM ([string] $VMName, [string] $sshKey, [string] $cmdToSend)
{
    $ipv4 = GetIPv4 $VMName 'localhost'
    SendCommandToVM $ipv4 $sshkey $cmdToSend
    if (-not $?) {
        return $false
    }
    else {
        return $true
    }  
}

function PrepareClusteredVM ()
{
    # Copy files to cluster storage
    $volume_location = $($(Get-ClusterSharedVolume).SharedVolumeInfo).FriendlyVolumeName
    if (-not $volume_location.EndsWith("\")) {
        $volume_location += "\"
    }
    Set-Variable -Name 'volume_location' -Value $volume_location -Scope Global

    Copy-Item -Path $dep_vhd_path -Destination $volume_location -Force -EA SilentlyContinue
    if (-not $?) {
        return $false
    }
    Copy-Item -Path $dep_pdk_path -Destination $volume_location -Force -EA SilentlyContinue
    if (-not $?) {
        return $false
    }

    return $true
}

function TestClusteredVM ([string] $VMName)
{
    StopVM $VMName "localhost"

    # Add Cluster Role
    $sts = Add-ClusterVirtualMachineRole -VirtualMachine $VMName
    if (-not $?){
        return $false
    }

    # Start VM
    $ipv4 = StartVM $VMName 'localhost'
    if (-not (isValidIPv4 $ipv4)) {
        return $false
    }

    # Live migrate the VM
    $rootDir = $(pwd).Path
    $sts = .\setupscripts\NET_LIVEMIG.ps1 -vmName $VMName -hvServer 'localhost' -MigrationType 'Live' -testParams "ipv4=${ipv4}; rootDir=${rootDir}; MigrationType=Live"
    if (-not $?) {
        return $false
    }

    # Clean the VM
    CleanupDependency $VMName
    $sts = Remove-ClusterGroup -Name $VMName -RemoveResources -Force

    return $true
}

function AddRecoverykey ([string] $VMName, [string]$ipv4, [string]$sshKey)
{
    # Add recovery key
    $retVal = SendCommandToVM $ipv4 $sshKey ". shielded_deployed_functions.sh && AddRecoveryKey && cat state.txt"
    if (-not $retVal) {
        return $false
    }
    # Check status
    $state = .\bin\plink.exe -i ssh\$sshKey root@$ipv4 "cat state.txt"
    if ($state -ne "TestCompleted") {
        return $false
    }

    # Stop VM and remove checkpoint
    StopVM $VMName "localhost"
    $sts = Remove-VMSnapshot -VMName $VMName -ComputerName "localhost" -Name "Deployed"
    Start-Sleep -s 120
    return $true
}

function MakeVMonSecondGH ([string] $second_GH_name, [string] $dep_vhd)
{
    $remote_defaultVhdPath = $(Get-VMHost -ComputerName $second_GH_name).VirtualHardDiskPath
    if (-not $defaultVhdPath.EndsWith("\")) {
        $defaultVhdPath += "\"
    }
    $copy_path = $remote_defaultVhdPath -replace ':','$'
    $copy_path = '\\' + $second_GH_name + '\' + $copy_path

    # Copy parent VHD
    Copy-Item $parentClone $copy_path -Recurse -Force
    if (-not $?) {
        return $false
    }
    $parentVHD_name = $(Get-ChildItem $parentClone).Name

    # Copy dependency Linux VHD
    Copy-Item $dep_vhd $copy_path -Recurse -Force
        if (-not $?) {
        return $false
    }
    $depVHD_name = $(Get-ChildItem $dep_vhd).Name

    $sts = Invoke-Command $second_GH_name -ScriptBlock{
        # Make a new VM
        $dependency_vhd_path = $using:remote_defaultVhdPath + $using:depVHD_name
        $newVm = New-VM -Name 'Dependency_VM' -VHDPath $dependency_vhd_path -MemoryStartupBytes 2048MB -SwitchName 'External' -Generation 1
        if (-not $?) {
            return $false
        }
        
        # Attach the test VHDx to the VM
        $test_vhd_path = $using:remote_defaultVhdPath + $using:parentVHD_name 
        $sts = Add-VMHardDiskDrive -VMName 'Dependency_VM' -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1 -Path $test_vhd_path
        if (-not $?) {
            return $false
        }

        return $true
    }

    return $sts
}

function TestRecoveryKey ([string] $second_GH_name, [string]$sshKey)
{
    # Start VM and get IP
    $ipv4 = StartVM 'Dependency_VM' $second_GH_name
    if (-not (isValidIPv4 $ipv4)) {
        return $false
    }

    Write-Host $ipv4
    # Send utils.sh to VM
    SendFile $ipv4 $sshKey 'utils.sh' | Should be $true
    
    # Send shielded_deployed_functions.sh to VM
    SendFile $ipv4 $sshKey 'shielded_deployed_functions.sh' | Should be $true

    # Test recovery key
    $retVal = SendCommandToVM $ipv4 $sshKey ". shielded_deployed_functions.sh && TestRecoveryKey && cat state.txt"
    if (-not $retVal) {
        return $false
    }
    # Check status
    $state = .\bin\plink.exe -i ssh\$sshKey root@$ipv4 "cat state.txt"
    if ($state -ne "TestCompleted") {
        return $false
    }

    # Clean up
    $sts = Stop-VM -Name 'Dependency_VM' -ComputerName $second_GH_name -TurnOff
    $sts = Remove-VM -Name 'Dependency_VM' -ComputerName $second_GH_name -Confirm:$false -Force
    
    return $true
}

function Modify_MBLoad ([string] $modifyMBLoad, [string]$ipv4, [string]$sshKey, [string] $vmName)
{
    $mbload_path = $defaultVhdPath + "bootx64.efi"
    # Send the bootloader to the VM
    $retVal = SendFileToVM $ipv4 $sshKey $mbload_path "/root/bootx64.efi"
    if (-not $retVal) {
        return $false
    }

    # Modify the bootloader. First we'll make a copy of the existing bootloader and then we'll copy the new one
    $retVal = SendCommandToVM $ipv4 $sshKey 'cp /boot/efi/EFI/boot/bootx64.efi /root/boot_backup.efi && cp /root/bootx64.efi /boot/efi/EFI/boot/bootx64.efi -rf'
    if (-not $retVal) {
        return $false
    }

    Start-Sleep -s 30
    # Restart the VM. It should reboot fine
    $ipv4 =  RestartVM $vmName
    if ($ipv4 -eq "") {
        return $false
    }

    # Test if already passed if we're testing bootloader upgrade
    if ($modifyMBLoad -eq "upgrade") {
        return $true
    }

    # Continue testing if we are doing a downgrade
    if ($modifyMBLoad -eq "downgrade") {
        $retVal = SendCommandToVM $ipv4 $sshKey "cp /root/boot_backup.efi /boot/efi/EFI/boot/bootx64.efi -rf"
        if (-not $retVal) {
            return $false
        }

        $ipv4 =  RestartVM $vmName
        if ($ipv4 -eq "") {
            return $false
        } 
    }
    return $true
}

# Construct global variables
$VM_name = "LSVM_Dep_Test"
$defaultVhdPath = $(Get-VMHost).VirtualHardDiskPath
if (-not $defaultVhdPath.EndsWith("\")) {
    $defaultVhdPath += "\"
}
$dep_vhd_path = $defaultVhdPath + "LSVM-DEP_test.vhdx"
$dep_pdk_path = $defaultVhdPath + "PDK_Test.pdk"
$VMPath = $defaultVhdPath + "Provision_Test\"
$VmVhdPath = $VMPath + '\' + $VM_name + '.vhdx'
$fskFile = $VMPath + '\' + $VM_name + '.fsk'