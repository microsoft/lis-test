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
    Remove a floppy from VMs floppy drive.

.Description
    Remove a floppy in the VMs floppy drive
    
.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.
.Exmple
 <test>
            <testName>FloppyDisk</testName>
            <testScript>STOR_Floppy_Disk.sh</testScript>    
            <files>remote-scripts\ica\STOR_Floppy_Disk.sh</files> 
            <setupScript>setupscripts\AddFloppyDisk.ps1</setupScript> 
            <cleanupScript>setupScripts\RemoveFloppyDisk.ps1</cleanupScript>
	        <noReboot>False</noReboot>
     	    <testParams>               
                <param>TC_COVERED=STOR-01</param>
            </testParams>
            <timeout>600</timeout>			
  </test>

#>



param ([String] $vmName, [String] $hvServer)


#############################################################
#
# Main script body
#
#############################################################

$retVal = $False

#
# Check the required input args are present
#
if (-not $vmName)
{
    "Error: null vmName argument"
    return $False
}

if (-not $hvServer)
{
    "Error: null hvServer argument"
    return $False
}

#
# Display some info for debugging purposes
#
"VM name     : ${vmName}"
"Server      : ${hvServer}"

#
# Remove the VFD , setting path to null will remove the floppy disk 
#
Set-VMFloppyDiskDrive -Path $null -VMName $vmName -ComputerName $hvServer
if ($? -eq "True")
{
    $retVal = $True
}
else
{
    "Error: Unable to mount floppy"
}

return $retVal
