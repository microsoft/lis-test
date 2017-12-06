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
# Linux Shielded VMs TDC pester tests
#

Param(
    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'Name of the VHDx where lsvmprep has been run')]
    [ValidateNotNullorEmpty()]
    [String]$lsvmprepVhdName,

    [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'Path of the VHDx that will be used for dependency VM')]
    [ValidateNotNullorEmpty()]
    [String]$dependencyVhdPath,
	
	[Parameter(Mandatory = $true,Position = 0,HelpMessage = 'SSH key for connecting to the Dependency VM')]
    [ValidateNotNullorEmpty()]
    [String]$sshKey,
	
	[Parameter(Mandatory = $true,Position = 0,HelpMessage = 'Path of the encrypted VHDx with no lsvmtools')]
    [ValidateNotNullorEmpty()]
    [String]$vhdNoLsvmtools
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

Describe "Run the TDC wizard with a Linux VHDX file" {
    Context "Submit the VHDX file (after running lsvmprep) to the TDC Wizard." {

        It "Running TDC-01" {
            # Get full VHDx path
            $vhdPath = Get_Full_VHD_Path $lsvmprepVhdName
            $vhdPath | Should not Be $null

            # Search for the certificate or create one
            $signCert = Get_Certificate
            $signCert | Should not Be $null

            # Make the template
            Run_TDC $vhdPath $signcert | Should be $true
        }
    }
}

Describe "Verify the output LSVM VHDX file from the TDC Wizard" {
    Context "1.  Verify the Volume Signature Catalog (VSC) file was created.
            2.  Attach the templatized VHDX file as a disk on a Linux VM.
            3.  Create the following directory: /lsvmefi
            4.  Mount the EFI partition of the templatized VHDX file on the /lsvmefi mount point.
            5.  Verify the boot loader is the Minimal OS, not the Shim, or MBLoad.
            6.  Examine the contents of the VSC file and look for the hashes for various partitions." {
        
        It "Running TDC-02" {			
            # Get full VHDx path
            $vhdPath = Get_Full_VHD_Path $lsvmprepVhdName
            $vhdPath | Should not Be $null

			# Search for the certificate or create one
            $signCert = Get_Certificate
            $signCert | Should not Be $null
			
			# Make the template
            Run_TDC $vhdPath $signcert | Should be $true
			
			# Run the test
            Verify_TDC $vhdPath $dependencyVhdPath $sshKey | Should be $true
			
			# Clean the dependency VM
			CleanupDependency 'TDC_Dependency'
        }
    } 
}

Describe "Verify a VHDX file that has not had lsvmprep run fails TDC" {
    Context "1.  Create Gen 2 Linux VM.
            2.  Do not install lsvmtools.
            3.  Submit the VHDX file from the VM in step 1 to the TDC Wizard." {
        
        It "Running TDC-03" {
			# Copy VHDx from share
            $vhdPath = Copy_vhdx_from_share $vhdNoLsvmtools
			$vhdPath | Should not Be $null
			
			# Search for the certificate or create one
            $signCert = Get_Certificate
            $signCert | Should not Be $null
			
			# Make the template
            Run_TDC $vhdPath $signcert | Should be $false
        }
    }
}

Describe "Test TDC using Linux VHDX file and an invalid certificate" {
    Context "1.  Submit a properly prepared Linux VHDX file to the TDC Wizard
            2.  Specify an invalid certificate.
            3.  Submit the VHDX file from the VM in step 1 to the TDC Wizard." {
        
        It "Running TDC-04" {
		    # Get full VHDx path
            $vhdPath = Get_Full_VHD_Path $lsvmprepVhdName
            $vhdPath | Should not Be $null

			# Search for the invalid certificate or create one
            $signCert = Get_invalid_certificate
			$signCert | Should not Be $null
			
			# Make the template
            Run_TDC $vhdPath $signcert | Should be $false
        }
    }
}
