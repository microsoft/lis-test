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
# Linux Deployed Shielded VMs pester tests
#

Param(    
    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'Share location')]
    [ValidateNotNullorEmpty()]
    [String]$sharePath,
    
    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'User name which has access to share')]
    [ValidateNotNullorEmpty()]
    [String]$shareUser,
    
    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'Account password which has access to share')]
    [ValidateNotNullorEmpty()]
    [String]$sharePassword,
    
    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'SSH key to access the VM')]
    [ValidateNotNullorEmpty()]
    [String]$sshKey,
    
    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'VHD that will be used to create a dependency VM')]
    [ValidateNotNullorEmpty()]
    [String]$dependencyVhdPath,

    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'VHD that will be used to create a dependency VM')]
    [ValidateNotNullorEmpty()]
    [String]$second_GH_name
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

# Import Shielded_TDC.ps1; It cointains a couple of functions we can re-use
if (Test-Path ".\setupScripts\Shielded_TDC.ps1") {
    . .\setupScripts\Shielded_TDC.ps1
}
else {
    "ERROR: Could not find setupScripts\Shielded_TDC.ps1"
    return $false
}

# Import Shielded_PRO.ps1
if (Test-Path ".\setupScripts\Shielded_PRO.ps1") {
    . .\setupScripts\Shielded_PRO.ps1
}
else {
    "ERROR: Could not find setupScripts\Shielded_PRO.ps1"
    return $false
}

# Import TCUtils.ps1
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
}
else {
    "ERROR: Could not find setupScripts\TCUtils.ps1"
    return $false
}

Describe "Preparation tasks for Deployed Shielded VMs testing"{
    Context "1. Copy template and PDK from share
            2. Provison a test VM
            3. Turn off the VM and take a snapshot" {
        It "LSVM-DEP-Preparation" {
            # Copy VHDx from share
            Copy_template_from_share $sharePath | Should be $true

            # Make a local copy for DEP test  suite
            Copy-Item -Path $test_vhd_path -Destination $dep_vhd_path -Force -EA SilentlyContinue
            $? | Should be $true

            # Copy PDK file from share
            Copy-Item -Path $(Get-ChildItem $sharePath -Filter *.pdk).FullName -Destination $dep_pdk_path -Force -EA SilentlyContinue
            $? | Should be $true

            # Provision the VM
            Provision "LSVM_Dep_Test" "no" | Should be $false

            # Check if the deployed VM has booted
            $vm_ipv4 = GetDEP_ipv4 "LSVM_Dep_Test"
            $vm_ipv4 | Should not Be $null

            TakeSnapshot "LSVM_Dep_Test" | Should be $true
        }
    }
}

Describe "Update the kernel on a LSVM and verify the VM continues to boot successfully" {
    Context "1. Create a Linux Shielded VM from a known good template.
            2.  Verify the VM boots.
            3.  Run a distro specific command to update the kernel.
            4.  Verify the kernel packages were update successfully.
            5.  Reboot the VM" {

        It "LSVM-DEP-01" {
            ApplySnapshot "LSVM_Dep_Test" | Should be $true

            # Check if the deployed VM has booted
            $ipv4 = GetDEP_ipv4 "LSVM_Dep_Test"
            $ipv4 | Should not Be $null

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'utils.sh' | Should be $true

            # Run the test script and wait for the results
            RunScript $ipv4 $sshKey 'SR-IOV_UpgradeKernel.sh' | Should be $true

            # Compare kernels
            CompareKernels $ipv4 $sshKey "LSVM_Dep_Test" | Should be $true
        }
    }
}

Describe "Update a boot component on a LSVM and verify the VM boots successfully" {
    Context "1. Create a Linux Shielded VM from a known good template.
            2.  Verify the VM boots.
            3.  Run a distro specific command to update one of the boot components.
            4.  Reboot the VM." {
        
        It "LSVM-DEP-02" {
            ApplySnapshot "LSVM_Dep_Test" | Should be $true

            # Check if the deployed VM has booted
            $ipv4 = GetDEP_ipv4 "LSVM_Dep_Test"
            $ipv4 | Should not Be $null

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'utils.sh' | Should be $true

            # Send shielded_deployed_functions.sh to VM
            SendFile $ipv4 $sshKey 'shielded_deployed_functions.sh' | Should be $true

            # Run the test script
            UpgradeGrub $ipv4 $sshKey "LSVM_Dep_Test" | Should be $true
        }
    } 
}

Describe "Clone a Linux Shielded VM VHDX and confirm it fails to boot" {
    Context "1. Create a Linux Shielded VM from a known good template.
            2.  Verify the VM boots.
            3.  Shutdown a function Linux Shielded VM.
            4.  Make a copy of the Linux Shielded VMs VHDX file.
            5.  On the same host, create a new Gen 2 VM with Secure boot enabled, and a vTPM.
            6.  Use the copied VHDX file as the boot disk of the VM created in step 3.
            7.  Boot the new VM." {
        
        It "LSVM-DEP-03" {
            ApplySnapshot "LSVM_Dep_Test" | Should be $true

            # Make a copy of the vhd used to provision the vm
            CopyVHD "LSVM_Dep_Test" | Should be $true

            # Make a VHD clone and attach it to the provisioned VM
            ClonedVHD $sshKey "LSVM_Dep_Test" | Should be $false

            # Clean VM
            CleanupDependency 'LSVM_Dep_Test_Clone'
        }
    }
}

Describe "Verify well known DMCrypt/LUKS passwords no longer work" {
    Context "1. Create a Linux Shielded VM from a known good template.
        2.  Verify the VM boots.
        3.  Shutdown the VM.
        4.  Make a copy of the VHDX file from the VM in step 1.
        5.  Using a second Linux VM (non-shielded VM), connect the copied VHDX file as a data disk.
        6.  In the second Linux VM, try to mount the boot/root partition using well-known passphrase." {
        
        It "LSVM-DEP-04" {
            ApplySnapshot "LSVM_Dep_Test" | Should be $true

            # Make a copy of the vhd used to provision the vm
            CopyVHD "LSVM_Dep_Test" | Should be $true

            # Create a Dependency VM
            $vm_ipv4 = DependencyVM $dependencyVhdPath 
            $vm_ipv4 | Should not be $null

            VerifyPassphrase $sshKey $vm_ipv4 | Should be $true

            # Clean VM
            CleanupDependency 'LSVM_Dependency'
        }
    }
}

Describe "Upgrade MBLoad to a newer version" {
    Context "1. Create a Linux Shielded VM from a known good template.
            2.  Verify the VM boots successfully.
            3.  Install an updated version of the LSVMTools package.
            4.  Run the utility to upgrade MBLoad.
            5.  Reboot the VM." {
        
        It "LSVM-DEP-05" {
            ApplySnapshot "LSVM_Dep_Test" | Should be $true

            # Check if the deployed VM has booted
            $ipv4 = GetDEP_ipv4 "LSVM_Dep_Test"
            $ipv4 | Should not Be $null

            Modify_MBLoad "upgrade" $ipv4 $sshKey "LSVM_Dep_Test" | Should be $true
        }
    }
}

Describe "Downgrade MBLoad to an older version." {
    Context "1. Create a Linux Shielded VM from a known good template.
            2.  Verify the VM boots successfully.
            3.  Install an older version of the LSVMTools package.
            4.  Run the utility to upgrade the MBLoad.
            5.  Reboot the VM." {
        
        It "LSVM-DEP-06" {
            ApplySnapshot "LSVM_Dep_Test" | Should be $true

            # Check if the deployed VM has booted
            $ipv4 = GetDEP_ipv4 "LSVM_Dep_Test"
            $ipv4 | Should not Be $null

            Modify_MBLoad "downgrade" $ipv4 $sshKey "LSVM_Dep_Test" | Should be $true
        }
    }
}

Describe "Live Migrate a LSVM" {
    Context "1. Create a Linux Shielded VM from a known good template.
            2.  Verify the VM boots successfully.
            3.  Migrate the Linux Shielded VM to another Hyper-V host in the same HGS fabric.
            4.  Reboot the VM two or more times after it has been migrated." {
        
        It "LSVM-DEP-07" {
            PrepareClusteredVM | Should be $true

            # Provision VM on the cluster shared volume
            Provision "LSVM_Dep_Clustered" "yes" | Should be $false

            # Configure High Availability
            TestClusteredVM "LSVM_Dep_Clustered" | Should be $true
        }
    }
}

Describe "Export/Import a LSVM" {
    Context "1. Create a Linux Shielded VM from a known good template.
            2.  Verify the VM boots successfully.
            3.  Export the VM to a shared directory.
            4.  On a separate Hyper-V host, import the exported VM." {
        
        It "LSVM-DEP-08" {
            ApplySnapshot "LSVM_Dep_Test" | Should be $true

            # Export the test VM
            ExportVM "LSVM_Dep_Test" | Should be $true

            # Copy files to second GH and import the VM
            ImportVM $second_GH_name "LSVM_Dep_Test" | Should be $true

            # Boot the VM and verify if it gets an IP
            VerifyImport $second_GH_name "LSVM_Dep_Test" | Should be $true

            CleanImport $second_GH_name "LSVM_Dep_Test"
        }
    }
}

Describe "Online Backup/Restore a data disk on a Linux Shielded VM" {
    Context "1. Create a Linux Shielded VM from a known good template.
            2.  Verify the VM boots successfully.
            3.  Add an additional disk drive to the VM.  This will be referred to as the data disk.
            4.  Add some files to the data disk.
            5.  Perform an online backup of the data disk.
            6.  Create an additional file on the data disk.
            7.  Modify the contents of an existing file on the data disk.
            8.  Restore the data disk from the backup created in step 5." {
        
        It "LSVM-DEP-09" {
            ApplySnapshot "LSVM_Dep_Test" | Should be $true

            # Create a data disk
            CreateDataDisk "LSVM_Dep_Test" $sshKey | Should be $true

            # Backup the VM
            BackupVM "LSVM_Dep_Test" "F:" | Should be $true

            # Write additional data
            WriteDataOnVM "LSVM_Dep_Test" $sshKey  "echo 'Second' > dataDisk/secondFile" | Should be $true
            WriteDataOnVM "LSVM_Dep_Test" $sshKey  "echo 'Test' > dataDisk/firstFile" | Should be $true

            # Restore VM
            RestoreVM | Should be $true

            # Check VM
            CheckRestoreStatus $sshKey 'yes' 'dataDisk/secondFile' 'Second' | Should be $true
            CheckRestoreStatus $sshKey 'yes' 'dataDisk/firstFile' 'Test' | Should be $true

            # Clean Backup
            BackupClean | Should be $true
        }
    }
}

Describe "Online Backup, then Restore the system disk of a Linux Shielded VM" {
    Context "1. Create a Linux Shielded VM from a known good template.
            2.  Verify the VM boots successfully.
            3.  Perform an online backup of the system disk.
            4.  Create an additional file on the system disk
            5.  Modify the contents of an existing file.
            6.  Shutdown the VM.
            7.  Restore the system disk from the backup created in step 3.
            8.  Boot the VM." {
        
        It "LSVM-DEP-10" {
            ApplySnapshot "LSVM_Dep_Test" | Should be $true

            # Write data
            WriteDataOnVM "LSVM_Dep_Test" $sshKey "echo 'First' > firstFile" | Should be $true
            
            # Backup the VM
            BackupVM "LSVM_Dep_Test" "F:" | Should be $true

            # Write additional data
            WriteDataOnVM "LSVM_Dep_Test" $sshKey  "echo 'Test' > secondFile" | Should be $true
            WriteDataOnVM "LSVM_Dep_Test" $sshKey  "echo 'Test' > firstFile" | Should be $true

            # Restore VM
            RestoreVM | Should be $true

            # Check VM
            CheckRestoreStatus $sshKey 'no' 'secondFile' 'Test' | Should be $true
            CheckRestoreStatus $sshKey 'no' 'firstFile' 'Test' | Should be $true

            # Clean Backup
            BackupClean | Should be $true
        }
    }
}

Describe "Use Backup to restore the system disk to an older version of MBLoad" {
    Context "1. Create a Linux Shielded VM from a known good template.
            2.  Verify the VM boots successfully.
            3.  Perform a backup of the system disk.
            4.  Install an upgraded LSVMTools package and update MBLoad.
            5.  Verify the VM continues to boot.
            6.  Create a new file on the system disk
            7.  Restore the system disk from the backup created in step 3.
            8.  Reboot the VM." {
        
        It "LSVM-DEP-11" {
            ApplySnapshot "LSVM_Dep_Test" | Should be $true
            
            # Backup the VM
            BackupVM "LSVM_Dep_Test" "F:" | Should be $true

            # Write additional data & upgrade LSVMTools
            WriteDataOnVM "LSVM_Dep_Test" $sshKey  "echo 'Test' > firstFile" | Should be $true

            # Upgrade bootloader
            $ipv4 = GetIPv4 "LSVM_Dep_Test" 'localhost'
            Modify_MBLoad "upgrade" $ipv4 $sshKey "LSVM_Dep_Test" | Should be $true

            # Restore VM
            RestoreVM | Should be $true

            # Check VM
            CheckRestoreStatus $sshKey 'no' 'firstFile' 'Test' | Should be $true

            # Clean Backup
            BackupClean | Should be $true
        }
    }
}

Describe "Add COM port to LSVM" {
    Context "1. Create a Linux Shielded VM from a known good template.
            2.  Verify the VM boots successfully.
            3.  Shutdown the VM.
            4.  Use the PowerShell cmdlet Set-VMComPort to add/configure a COM port to the VM." {
        
        It "LSVM-DEP-12" {
            ApplySnapshot "LSVM_Dep_Test" | Should be $true

            # Check if the deployed VM has booted
            $ipv4 = GetDEP_ipv4 "LSVM_Dep_Test"
            $ipv4 | Should not Be $null

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'utils.sh' | Should be $true

            # Send shielded_deployed_functions.sh to VM
            SendFile $ipv4 $sshKey 'shielded_deployed_functions.sh' | Should be $true

            # Make necessary grub config
            ModifyGrub $ipv4 $sshKey "LSVM_Dep_Test" | Should be $true

            AddComPort "LSVM_Dep_Test" | Should be $true
        }
    }
}

Describe "Attack a VHDX file of a functioning LSVM" {
    Context "1. Create a Linux Shielded VM from a known good template.
            2.  Verify the VM boots successfully.
            3.  Shutdown the VM.
            4.  Make a copy the VHDX file from the Linux Shielded VM created in step 1.
            5.  Add the copied VHDX file as a data disk to a separate existing Linux VM.
            6.  Mount the EFI partition from the copied VHDX file in the second Linux VM.
            7.  Replace MBLoad in the EFI partition with Grub.
            8.  Copy the grub.cfg to the same directory.
            9.  Unmount the VHDX file from the second VM.
            10. Replace the LSVMs boot disk with the modified VHDX file.
            11. Boot the VM." {
        
        It "LSVM-DEP-13" {
            ApplySnapshot "LSVM_Dep_Test" | Should be $true

            # Make a copy of the vhd used to provision the vm
            CopyVHD "LSVM_Dep_Test" | Should be $true

            # Create a Dependency VM
            $vm_ipv4 = DependencyVM $dependencyVhdPath 
            $vm_ipv4 | Should not be $null

            # Make the changes to the cloned VHDx
            ModifyBoot $vm_ipv4 $sshKey "LSVM_Dep_Test" | Should be $true
        }
    }
}

Describe "Replicate a LSVM to a different host which uses the same HGS" {
    Context "1. Create a Linux Shielded VM from a known good template.
            2.  Verify the VM boots successfully.
            3.  Replicate the VM to a different Hyper-V host which is using the same HGS that the original Hyper-V host is using.
            4.  Boot the VM." {
        
        It "LSVM-DEP-14" -Pending{
        }
    }
}

Describe "VHD recovery with LSVM recovery key" {
    Context "1. Create a Linux Shielded VM from a known good template.
            2.  Verify the VM boots successfully.
            3.  Shutdown the VM.
            4.  Make a copy of the VMs VHDX file.
            5.  Copy the VHDX file to a separate Hyper-V host.
            6.  Using a Linux VM on the separate Hyper-V host, and attach the VHDX file as a data disk to the VM.
            7.  Boot the Linux VM.
            8.  Use the LSVM recovery key to recover the boot partition and root partition passphrases.
            9.  Mount the boot partition.
            10. Mount the root partition." {
        
        It "LSVM-DEP-15" {
            ApplySnapshot "LSVM_Dep_Test" | Should be $true

            # Check if the deployed VM has booted
            $ipv4 = GetDEP_ipv4 "LSVM_Dep_Test"
            $ipv4 | Should not Be $null

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'utils.sh' | Should be $true
            
            # Send shielded_deployed_functions.sh to VM
            SendFile $ipv4 $sshKey 'shielded_deployed_functions.sh' | Should be $true

            # Add Recovery key
            AddRecoveryKey "LSVM_Dep_Test" $ipv4 $sshKey | Should be $true

            # Make a copy of the vhd used to provision the vm
            CopyVHD "LSVM_Dep_Test" | Should be $true

            # Remake the snapshot
            TakeSnapshot "LSVM_Dep_Test" | Should be $true

            # Make a new VM on the second GH
            MakeVMonSecondGH $second_GH_name $dependencyVhdPath | Should be $true

            # Test Recovery key
            TestRecoveryKey $second_GH_name $sshKey | Should be $true
        }
    }
}

Describe "Disable Secure Boot and verify Linux Shielded VM fails to boot" {
    Context "1. Create a Linux Shielded VM from a known good template.
            2.  Verify the VM boots successfully.
            3.  Shutdown theVM.
            4.  Disable Secure Boot for the VM.
            5.  Boot the VM." {
        
        It "LSVM-DEP-16" {
            ApplySnapshot "LSVM_Dep_Test" | Should be $true

            # Disable SecureBoot
            DisableSecureBoot "LSVM_Dep_Test" | Should be $true

            # Clean up the VM
            CleanupDependency "LSVM_Dep_Test"
        }
    }
}