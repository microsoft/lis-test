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
    Copy a VM from a VM repository share to localhost.

.Description
    Copy a VM from a VM repository share to localhost if the VM does not exist in localhost HyperV.
    If the VM exists, the script will return with no action taken. 
    
.Parameter LisVmRootDir
    The VM repository share. 

.Parameter VMName
    The VM folder name.

.Parameter LocalVmRootDir
    The folder will keep the VM on the localhost.

.Parameter LogFolder
    A folder to save the script running logs.

.Exmple
    Copy-LisaVM.ps1 \\myserver\myVmRepositoryShare Windows-X86-01 D:\LocalVMs D:\Logs

#>

param( [string]$LisVmRootDir, [string]$VMName, [string]$LocalVmRootDir, [string]$LogFolder )

#----------------------------------------------------------------------------
# Start a new PowerShell log.
#----------------------------------------------------------------------------
Start-Transcript "$LogFolder\Copy-LisaVM.ps1.log" -force

#----------------------------------------------------------------------------
# Print running information
#----------------------------------------------------------------------------
Write-Host "Running [Copy-LisaVM.ps1]..." -foregroundcolor cyan
Write-Host "`$LisVmRootDir   = $LisVmRootDir" 
Write-Host "`$VMName         = $VMName" 
Write-Host "`$LocalVmRootDir = $LocalVmRootDir" 
Write-Host "`$LogFolder      = $LogFolder" 

#----------------------------------------------------------------------------
# Verify required parameters
#----------------------------------------------------------------------------
if ($LisVmRootDir -eq $null -or $LisVmRootDir -eq "")
{
    Throw "Parameter LisVmRootDir is required."
}
if ($VMName -eq $null -or $VMName -eq "")
{
    Throw "Parameter VMName is required."
}
if ($LocalVmRootDir -eq $null -or $LocalVmRootDir -eq "")
{
    Throw "Parameter LocalVmRootDir is required."
}
if ($LogFolder -eq $null -or $LogFolder -eq "")
{
    Throw "Parameter LogFolder is required."
}

$vmNumber = 0
If ($VMName.Contains(":"))
{
    $VmList = $VMName.Split(":")
    $vmNumber = $VmList.Count
    Write-Host "There are $vmNumber VMs defined in the LISA XML (separator char ':'): $VMName"
}
else
{
    $VmList = $VMName
    $vmNumber = 1
    Write-Host "There is one VM defined in the LISA XML: $VMName"
}

for ($i=0; $i -lt $vmNumber; $i++)
{
    if ($vmNumber -eq 1)
    {
        $theVMFullName = $VmList
    }
    else
    {
        $theVMFullName = $VmList[$i]
    }

    $theVMName = $theVMFullName.Split("@")[0]
    $theVMComputerName = $theVMFullName.Split("@")[1]

    #----------------------------------------------------------------------------
    # Remove a VM if its name already exists in HyperV manager (if not, the start vm will fail because the VM files are being used by HyperV)
    #----------------------------------------------------------------------------
    Write-Host "Get-VM: $theVMName  from $theVMComputerName"
    $VM = Get-VM -Name $theVMName -ComputerName $theVMComputerName

    if($VM -ne $null)
    {
	    Write-Host "The VM: $theVMName was found already exist in the HyperV manager of $theVMComputerName. Exiting..."
    }
    else
    {
        $desShare = "\\" + $theVMComputerName + "\" + $LocalVmRootDir.Replace(":","$") + "\" + $theVMName
        Write-Host "Copying the VM: $theVMName to $theVMComputerName by using Robocopy ..." 
        cmd /c "robocopy /mir /R:2 /W:1 $LisVmRootDir\$theVMName $desShare  > $LogFolder\CopySUTVMByRobocopy-$theVMComputerName.log"
    }
}
Write-Host "Running [Copy-LisaVM.ps1] FINISHED (NOT VERIFIED)."

Stop-Transcript
exit