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
# Linux Shielded VMs PRE-TDC pester tests
#

Param(    
    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'Encrypted VHDx location')]
    [ValidateNotNullorEmpty()]
    [String]$CLImageStorDir,
    
    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'Path to LSVM packages')]
    [ValidateNotNullorEmpty()]
    [String]$lsvm_folder_path,

    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'Path to Decryption VHDx')]
    [ValidateNotNullorEmpty()]
    [String]$decrypt_vhd_folder,

    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'Path to RHEL VHDx')]
    [ValidateNotNullorEmpty()]
    [String]$rhel_folder_path,

    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'Path to SLES VHDx')]
    [ValidateNotNullorEmpty()]
    [String]$sles_folder_path,

    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'Path to Ubuntu VHDx')]
    [ValidateNotNullorEmpty()]
    [String]$ubuntu_folder_path,

    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'SSH key to access the VM')]
    [ValidateNotNullorEmpty()]
    [String]$sshKey
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

# Import Shielded_DEP.ps1
if (Test-Path ".\setupScripts\Shielded_DEP.ps1") {
    . .\setupScripts\Shielded_DEP.ps1
}
else {
    "ERROR: Could not find setupScripts\Shielded_DEP.ps1"
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

Describe "Preparation tasks for LSVM-PRE testing" {
    Context "1. Create a VM using a specific VHDX
            2. Attach unlock disk
            3. Install LSVMTools
            4. Take a snapshot" {
    
        It "LSVM-Install" {
            CleanupDependency 'Shielded_PRE-TDC'     
            Start-Sleep -s 60
               
			Create_Test_VM $CLImageStorDir | Should be $true

            $ipv4 = AttachDecryptVHDx $decrypt_vhd_folder
            $ipv4 | Should not Be $false

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'utils.sh' | Should be $true

            Install_lsvm $sshKey $ipv4 $lsvm_folder_path | Should be $true

            DettachDecryptVHDx | Should be $true
        }
    } 
}

Describe "Verify the distro specific Linux Shielded VM tools package is installed" {
    Context "Run a distro specific command to verify the lsvmtools package is installed.
            For RPM based systems:
                rpm -qa | grep -q LSVMTools
            For Debian based systems:
                dpkg -l | grep -q LSVMTools" {
    
        It "LSVM-PRE-01" {           
            $snap = Get-VMSnapshot -VMName 'Shielded_PRE-TDC' -Name 'ICABase'
            Restore-VMSnapshot $snap -Confirm:$false

            $ipv4 = AttachDecryptVHDx $decrypt_vhd_folder
            $ipv4 | Should not Be $false

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'utils.sh' | Should be $true

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'shielded_verify_lsvm.sh' | Should be $true

            Verify_script $ipv4 $sshKey 'shielded_verify_lsvm.sh' | Should be $true

            DettachDecryptVHDx | Should be $true
        }
    } 
}

Describe "Verify dependent packages are installed" {
    Context "1. Verify all vendor specific dependent packages are installed.
            For RHEL/CentOS
                cryptsetup, cryptsetup-bin, dracut, cryptsetup, device-mapper
            For Ubuntu
                cryptsetup, cryptsetup-bin, initramfs-tools, initramfs-tools-bin, initramfs-tools-core, dmeventd, dmsetup" {
    
        It "LSVM-PRE-02" {
            $snap = Get-VMSnapshot -VMName 'Shielded_PRE-TDC' -Name 'ICABase'
            Restore-VMSnapshot $snap -Confirm:$false

            $ipv4 = AttachDecryptVHDx $decrypt_vhd_folder
            $ipv4 | Should not Be $false

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'utils.sh' | Should be $true

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'shielded_verify_dependencies.sh' | Should be $true

            Verify_script $ipv4 $sshKey 'shielded_verify_dependencies.sh' | Should be $true

            DettachDecryptVHDx | Should be $true 
        }
    } 
}

Describe "Verify lsvmprep correctly configures the Linux VHDX for templatization" {
    Context "1. Run the script /opt/lsvmtools-<version>/bin/lsvmprep
            2.  Monitor the progress of the script" {
        
        It "LSVM-PRE-03" {
            $snap = Get-VMSnapshot -VMName 'Shielded_PRE-TDC' -Name 'ICABase'
            Restore-VMSnapshot $snap -Confirm:$false

            $ipv4 = AttachDecryptVHDx $decrypt_vhd_folder
            $ipv4 | Should not Be $false

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'utils.sh' | Should be $true

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'shielded_verify_lsvmprep.sh' | Should be $true

            Verify_script $ipv4 $sshKey 'shielded_verify_lsvmprep.sh' | Should be $true

            DettachDecryptVHDx | Should be $true 
        }
    }
}

Describe "Run lsvmprep on VHDX where root partition is not encrypted" {
    Context "1. Create a Gen 2 Linux VM.
            2.  When installing Linux, do not encrypt the root partition.
            3.  Install the LSVMTools packate.
            4.  Run the lsvmprep utility" {
        
        It "LSVM-PRE-04" {
            $snap = Get-VMSnapshot -VMName 'Shielded_PRE-TDC' -Name 'ICABase'
            Restore-VMSnapshot $snap -Confirm:$false

            $ipv4 = AttachDecryptVHDx $decrypt_vhd_folder
            $ipv4 | Should not Be $false

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'utils.sh' | Should be $true

            Verify_not_encrypted $ipv4 $sshKey $rhel_folder_path $sles_folder_path $ubuntu_folder_path $lsvm_folder_path | Should be $true

            DettachDecryptVHDx | Should be $true 
        }
    }
}

Describe "Root partition passphrase is not the well-known passphrase" {
    Context "1. Change the passphrase
            2. Check if lsvpmrep fails with a changed passphrase" {
        
        It "LSVM-PRE-05" {
            $snap = Get-VMSnapshot -VMName 'Shielded_PRE-TDC' -Name 'ICABase'
            Restore-VMSnapshot $snap -Confirm:$false

            $ipv4 = AttachDecryptVHDx $decrypt_vhd_folder
            $ipv4 | Should not Be $false

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'utils.sh' | Should be $true

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'shielded_verify_passphrase_noSpace.sh' | Should be $true

            Verify_passphrase_noSpace $ipv4 $sshKey 'shielded_verify_passphrase_noSpace.sh' 'yes' 'no' | Should be $true

            DettachDecryptVHDx | Should be $true 
        }
    }
}

Describe "Insufficient space to encrypt boot partition" {
    Context "1. Fill the boot partition
            2. Check if lsvmprep fails with a filled partitions" {
        
        It "LSVM-PRE-06" {
            $snap = Get-VMSnapshot -VMName 'Shielded_PRE-TDC' -Name 'ICABase'
            Restore-VMSnapshot $snap -Confirm:$false

            $ipv4 = AttachDecryptVHDx $decrypt_vhd_folder
            $ipv4 | Should not Be $false

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'utils.sh' | Should be $true

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'shielded_verify_passphrase_noSpace.sh' | Should be $true

            Verify_passphrase_noSpace $ipv4 $sshKey 'shielded_verify_passphrase_noSpace.sh' 'no' 'yes' | Should be $true

            DettachDecryptVHDx | Should be $true
        }
    }
}

Describe "Prepare VM for TDC testing" {
    Context "1. Delete checkpoint
            2. Change boot order" {
        
        It "LSVM-Prepare_TDC" {
            $snap = Get-VMSnapshot -VMName 'Shielded_PRE-TDC' -Name 'ICABase'
            Restore-VMSnapshot $snap -Confirm:$false

            $ipv4 = AttachDecryptVHDx $decrypt_vhd_folder
            $ipv4 | Should not Be $false

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'utils.sh' | Should be $true

            # Send utils.sh to VM
            SendFile $ipv4 $sshKey 'shielded_verify_lsvmprep.sh' | Should be $true

            Verify_script $ipv4 $sshKey 'shielded_verify_lsvmprep.sh' | Should be $true

            DettachDecryptVHDx | Should be $true

			Prepare_VM $sshKey | Should be $true
        }
    }
}