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
# Linux Shielded VMs Provisioning pester tests
#

Param(
    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'Name of the VHDx where lsvmprep has been run')]
    [ValidateNotNullorEmpty()]
    [String]$lsvmprepVhdName,

    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'User name of the Guarded Host')]
    [ValidateNotNullorEmpty()]
    [String]$guardedHostUser,

    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'Account password of the Guarded Host')]
    [ValidateNotNullorEmpty()]
    [String]$guardedHostPassword,
    
    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'IP of the Guarded Host')]
    [ValidateNotNullorEmpty()]
    [String]$guardedHostIP,
    
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
    [String]$dependencyVhdPath
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

Describe "Preparation tasks for Provisioning testing"{
    Context "1. Create a Linux Shielded VM template
            2.  Upload template to share" {

        It "LSVM-Preparation" {
            # Get full VHDx path
            $vhdPath = Get_Full_VHD_Path $lsvmprepVhdName
            $vhdPath | Should not Be $null

            # Search for the certificate or create one
            $signCert = Get_Certificate
            $signCert | Should not Be $null

            # Make the template
            Run_TDC $vhdPath $signcert | Should be $true
            
            # Make a copy for this test suite
            $lsvm_vhd_path = $test_vhd_path -replace '_test',''
            Copy-Item -Path $vhdPath -Destination $lsvm_vhd_path -Force
            
            # Upload template to share for later use
            Upload_File $lsvm_vhd_path $sharePath | Should be $true
        }
    }
}

Describe "Verify a provisioned Linux Shielded VM boots successfully" {
    Context "1. Create a Linux Shielded VM using a known good template.
            2.  During VM creation, note the specialization data specified.
            3.  Verify the VM boots.
            4.  Review the syslog for any errors or warnings related to LSVM." {

        It "LSVM-PRO-01" {
            Set-Item WSMan:\localhost\Client\TrustedHosts -value * -Force
            # Copy VHDx from share
            Copy_template_from_share $sharePath | Should be $true
            
            # Create the PDK file
            Generate-PDKFile 'Encryptionsupported' $sharePath | Should be $true
            
            # Make credentials object for the guarded host
            $gh_creds = Create-CredentialObject $guardedHostUser $guardedHostPassword 
            $gh_creds | Should not Be $null
            
            # Make credentials object for the share account
            $share_creds = Create-CredentialObject $shareUser $sharePassword 
            $share_creds | Should not Be $null
            
            # Copy files to the Guarded Host
            Copy_Files_to_GH $guardedHostIP $sharePath $gh_creds $share_creds | Should be $true
            
            # Provision the Shielded VM
            Provision_VM $guardedHostIP $gh_creds 'no' | Should be $true
            
            # Get ipv4 from the provisioned VM
            $vm_ipv4 = Get_VM_ipv4 $guardedHostIP $gh_creds
            $vm_ipv4 | Should not Be $null
            
            # Login to the provisioned VM and verify logs for errors
            $provisioned_vm_traces = Verify_provisioned_VM $vm_ipv4 $sshKey 
            
            # Clean the Shielded VM
            Clean_provisioned_VM $guardedHostIP $gh_creds | Should be $true
            
            $provisioned_vm_traces | Should be $false
        }
    }
}

Describe "Modify VSC, verify a VM created from the Linux VHDX template fails provisioning" {
    Context "1. Modify a field of the VSC of a known good Linux Shielded template VHDX/VSC.
            2.  Create a Shielded VM using this modified template/VSC.
            3.  Start the VM and verify provisioning fails." {
        
        It "LSVM-PRO-02" {
            Set-Item WSMan:\localhost\Client\TrustedHosts -value * -Force       
            # Copy VHDx from share
            Copy_template_from_share $sharePath | Should be $true
            
            # Create the PDK file
            Generate-PDKFile 'Encryptionsupported' $sharePath | Should be $true
            
            # Create dependency VM
            $dep_ipv4 = CreateVM $dependencyVhdPath
            $dep_ipv4 | Should not Be $null
            
            # Modify VSC
            Modify_VSC $sshKey $dep_ipv4 $sharePath | Should be $true
            
            # Make credentials object for the guarded host
            $gh_creds = Create-CredentialObject $guardedHostUser $guardedHostPassword 
            $gh_creds | Should not Be $null
            
            # Make credentials object for the share account
            $share_creds = Create-CredentialObject $shareUser $sharePassword 
            $share_creds | Should not Be $null
            
            # Copy files to the Guarded Host
            Copy_Files_to_GH $guardedHostIP $sharePath $gh_creds $share_creds | Should be $true
            
            # Provision the Shielded VM
            Provision_VM $guardedHostIP $gh_creds 'no' | Should be $false
            
            # Clean the Shielded VM
            Clean_provisioned_VM $guardedHostIP $gh_creds | Should be $true
        }
    } 
}

Describe "Modify file in boot partition of Linux VHDX template and verify provisioning fails" {
    Context "1. Using an existing known good Linux Shielded template VHDX and VSC, connect the VHDX file as a data disk in an existing Linux VM.
            2.  Mount the boot partition using the well-known DMCrypt/LUKS passphrase.
            3.  Modify a file in the boot partition – e.g. one of the /boot/config* files.
            4.  Unmount the VHDX file.
            5.  Use the modified template VHDX file and its VSC to create a Linux Shielded VM." {
        
        It "LSVM-PRO-03" {
            Set-Item WSMan:\localhost\Client\TrustedHosts -value * -Force       
            # Copy VHDx from share
            Copy_template_from_share $sharePath | Should be $true
            
            # Create the PDK file
            Generate-PDKFile 'Encryptionsupported' $sharePath | Should be $true
            
            # Create dependency VM
            $dep_ipv4 = CreateVM $dependencyVhdPath
            $dep_ipv4 | Should not Be $null
            
            # Modify VSC
            Modify_boot_partition $sshKey $dep_ipv4 $sharePath | Should be $true
            
            # Make credentials object for the guarded host
            $gh_creds = Create-CredentialObject $guardedHostUser $guardedHostPassword 
            $gh_creds | Should not Be $null
            
            # Make credentials object for the share account
            $share_creds = Create-CredentialObject $shareUser $sharePassword 
            $share_creds | Should not Be $null
            
            # Copy files to the Guarded Host
            Copy_Files_to_GH $guardedHostIP $sharePath $gh_creds $share_creds | Should be $true
            
            # Provision the Shielded VM
            Provision_VM $guardedHostIP $gh_creds 'no' | Should be $false
            
            # Clean the Shielded VM
            Clean_provisioned_VM $guardedHostIP $gh_creds | Should be $true
        }
    }
}

Describe "Modify file in root partition of Linux VHDX template and verify provisioning fails" {
    Context "1. Using an existing known good Linux Shielded template VHDX and VSC, connect the VHDX file as a data disk in an existing Linux VM.
            2.  Mount the root partition of this VHDX file using the well-known DMCrypt/LUKS passphrase.
            3.  Modify a file in the root partition.
            4.  Unmount the VHDX file.
            5.  Use the modified template VHDX file and its VSC to create a Linux Shielded VM." {
        
        It "LSVM-PRO-04" {
            Set-Item WSMan:\localhost\Client\TrustedHosts -value * -Force       
            # Copy VHDx from share
            Copy_template_from_share $sharePath | Should be $true
            
            # Create the PDK file
            Generate-PDKFile 'Encryptionsupported' $sharePath | Should be $true
            
            # Create dependency VM
            $dep_ipv4 = CreateVM $dependencyVhdPath
            $dep_ipv4 | Should not Be $null
            
            # Modify VSC
            Modify_root_partition $sshKey $dep_ipv4 $sharePath | Should be $true
            
            # Make credentials object for the guarded host
            $gh_creds = Create-CredentialObject $guardedHostUser $guardedHostPassword 
            $gh_creds | Should not Be $null
            
            # Make credentials object for the share account
            $share_creds = Create-CredentialObject $shareUser $sharePassword 
            $share_creds | Should not Be $null
            
            # Copy files to the Guarded Host
            Copy_Files_to_GH $guardedHostIP $sharePath $gh_creds $share_creds | Should be $true
            
            # Provision the Shielded VM
            Provision_VM $guardedHostIP $gh_creds 'no' | Should be $false
            
            # Clean the Shielded VM
            Clean_provisioned_VM $guardedHostIP $gh_creds | Should be $true
        }
    }
}

Describe "VM fails to boot if the specialization file has been modified" {
    Context "1. Create a Linux Shielded VM using an existing known good Linux Shielded template VHDX.
            2.  Complete the provisioning phase, but do not boot the VM after the provisioning completes.
            3.  Modify the specialization file.
            4.  Boot the VM." {
        
        It "LSVM-PRO-05" {
            Set-Item WSMan:\localhost\Client\TrustedHosts -value * -Force
            # Copy VHDx from share
            Copy_template_from_share $sharePath | Should be $true
            
            # Create the PDK file
            Generate-PDKFile 'Encryptionsupported' $sharePath | Should be $true
            
            # Make credentials object for the guarded host
            $gh_creds = Create-CredentialObject $guardedHostUser $guardedHostPassword 
            $gh_creds | Should not Be $null
            
            # Make credentials object for the share account
            $share_creds = Create-CredentialObject $shareUser $sharePassword 
            $share_creds | Should not Be $null
            
            # Copy files to the Guarded Host
            Copy_Files_to_GH $guardedHostIP $sharePath $gh_creds $share_creds | Should be $true
            
            # Provision the Shielded VM
            Provision_VM $guardedHostIP $gh_creds 'yes'| Should be $false
            
            # Clean the Shielded VM
            Clean_provisioned_VM $guardedHostIP $gh_creds | Should be $true
        }
    }
}

Describe "Unsupported specialization items are logged" {
    Context "1. Create a Linux Shielded VM using an existing known good Linux Shielded template VHDX.
            2.  When creating the Linux Shielded VM, specify specialization items that are not supported.
            e.g.  myBirthDay=yesterday
            3.  Boot the VM and complete provisioning.
            4.  Boot the VM and login." {
        
        It "LSVM-PRO-06" {
            Set-Item WSMan:\localhost\Client\TrustedHosts -value * -Force
            # Copy VHDx from share
            Copy_template_from_share $sharePath | Should be $true
            
            # Create the PDK file
            Generate-PDKFile 'Encryptionsupported' $sharePath | Should be $true
            
            # Make credentials object for the guarded host
            $gh_creds = Create-CredentialObject $guardedHostUser $guardedHostPassword 
            $gh_creds | Should not Be $null
            
            # Make credentials object for the share account
            $share_creds = Create-CredentialObject $shareUser $sharePassword 
            $share_creds | Should not Be $null
            
            # Copy files to the Guarded Host
            Copy_Files_to_GH $guardedHostIP $sharePath $gh_creds $share_creds | Should be $true
            
            # Provision the Shielded VM
            Provision_VM $guardedHostIP $gh_creds 'extra' | Should be $true
            
            # Get ipv4 from the provisioned VM
            $vm_ipv4 = Get_VM_ipv4 $guardedHostIP $gh_creds
            $vm_ipv4 | Should not Be $null
            
            # Login to the provisioned VM and verify logs for errors
            $provisioned_vm_traces = Verify_provisioned_VM $vm_ipv4 $sshKey 
            
            # Clean the Shielded VM
            Clean_provisioned_VM $guardedHostIP $gh_creds | Should be $true
            
            $provisioned_vm_traces | Should be $false
        }
    }
}