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

.Description
    This is a PowerShell test case script that runs on the on
    the ICA host rather than the VM.

    This script exports the VM, Imports it back, verifies that the imported VM has the snapshots also. 
     Finally it deletes the imported VM.
    

    The ICA scripts will always pass the vmName, hvServer, and a
    string of testParams to the PowerShell test case script. For
    example, if the <testParams> section was written as:

        <testParams>
            <param>TestCaseTimeout=300</param>
        </testParams>

    The string passed in the testParams variable to the PowerShell
    test case script script would be:

        "TestCaseTimeout=300"

    The PowerShell test case scripts need to parse the testParam
    string to find any parameters it needs.

    All setup and cleanup scripts must return a boolean ($true or $false)
    to indicate if the script completed successfully or not.

.Parameter vmName
    Name of the VM to test.
    
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
    
.Parameter testParams
    Test data for this test case
    
.Example

#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$rootDir = $null
$vmIPAddr = $null
$testCaseTimeout = 600

#####################################################################
#
# CheckCurrentStateFor()
#
#####################################################################
function CheckCurrentStateFor([String] $vmName, [UInt16] $newState)
{
    $stateChanged = $False
    
    $vm = Get-VM $vmName -server $hvServer
    
    if ($($vm.EnabledState) -eq $newState)
    {
        $stateChanged = $True
    }
    
    return $stateChanged
}

#####################################################################
#
# TestPort()
#
#####################################################################
function TestPort ([String] $serverName, [Int] $port=22, [Int] $to=3)
{
    $retVal = $False
    $timeout = $to * 1000
  
    #
    # Try an async connect to the specified machine/port
    #
    $tcpclient = new-Object system.Net.Sockets.TcpClient
    $iar = $tcpclient.BeginConnect($serverName,$port,$null,$null)
    
    #
    # Wait for the connect to complete. Also set a timeout
    # so we don't wait all day
    #
    $connected = $iar.AsyncWaitHandle.WaitOne($timeout,$false)
    
    # Check to see if the connection is done
    if($connected)
    {
        #
        # Close our connection
        #
        try
        {
            $sts = $tcpclient.EndConnect($iar) | out-Null
            $retVal = $true
        }
        catch
        {
            # Nothing we need to do...
        }

        #if($sts)
        #{
        #    $retVal = $true
        #}
    }
    $tcpclient.Close()

    return $retVal
}

#####################################################################
#
# Main script body
#
#####################################################################

$retVal = $False

#
# Check input arguments
#
if ($vmName -eq $null)
{
    "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null)
{
    "Error: hvServer is null"
    return $retVal
}

#
# Parse the testParams string
#
$params = $testParams.Split(';')
foreach ($p in $params)
{
    if ($p.Trim().Length -eq 0)
    {
        continue
    }

    $tokens = $p.Trim().Split('=')
    
    if ($tokens.Length -ne 2)
    {
	    "Warn : test parameter '$p' is being ignored because it appears to be malformed"
        continue
    }
    
    if ($tokens[0].Trim() -eq "RootDir")
    {
        $rootDir = $tokens[1].Trim()
    }
    
    if ($tokens[0].Trim() -eq "ipv4")
    {
        $vmIPAddr = $tokens[1].Trim()
    }
}

if ($rootDir -eq $null)
{
    "Error: The RootDir test parameter is not defined."
    return $retVal
}

if ($vmIPAddr -eq $null)
{
    "Error: The ipv4 test parameter is not defined."
    return $retVal
}

cd $rootDir

#
#Creating the test summary file.
#
$summaryLog  = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers TC92" | Out-File $summaryLog

#
# Load the PowerShell HyperV Library
#
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2Sp1\HyperV.psd1
}

#
# Check that the VM is present on the server and it is in running state.
#
$vm = Get-VM $vmName -server $hvServer
if (-not $vm)
{
    "Error: Cannot find VM ${vmName} on server ${hvServer}"
    Write-Output "VM ${vmName} not found" | Out-File -Append $summaryLog
    return $retVal
}

if ($($vm.EnabledState) -ne 2)
{
    "Error: VM ${vmName} is not in the running state!"
    return $retVal
}

#
# While checking for VM startup Wait for TCP port 22 to be available on the VM
#
while ($testCaseTimeout -gt 0)
{

    if ( (TestPort $vmIPAddr) )
    {
        break

    }
     
    Start-Sleep -seconds 2
    $testCaseTimeout -= 2
}

if ($testCaseTimeout -eq 0)
{
    "Error: Test case timed out for VM to go to Running"
    return $retVal
}

Write-Output "VM ${vmName} is present on server and running" 

#
# Stop the VM to export it. 
#

while ($testCaseTimeout -gt 0)
{
    Hyperv\stop-VM -VM $vmName -Server $hvServer -Wait -Force -Verbose
        
    if ( (CheckCurrentStateFor $vmName ([UInt16] [VMState]::stopped)))
    {
        break
    }   

    Start-Sleep -seconds 2
    $testCaseTimeout -= 2
}

if ($testCaseTimeout -eq 0)
{
    "Error: Test case timed out waiting for VM to stop"
    return $retVal
}

Write-Output "VM ${vmName} is stopped successfully" 

#
# Create a Snapshot before exporting the VM
#
New-VMSnapshot -VM $vmName -Server $hvServer -Wait -Force | Rename-VMSnapshot -NewName "TestExport" -Force
if ($? -ne "True")
{
    Write-Output "Error while creating the snapshot" | Out-File -Append $summaryLog
    return $retVal
}

Write-Output "Successfully created a new snapshot before exporting the VM" 

#
# export the VM.
#
HyperV\Export-VM -VM $vmName -Server $hvServer -Path $rootDir  -wait -CopyState -Verbose
if ($? -ne "True")
{
    Write-Output "Error while exporting the VM" | Out-File -Append $summaryLog
    return $retVal
}

Write-Output "VM ${vmName} exported successfully"  

#
# Before importing the VM from exported folder, Delete the created snapshot from the orignal VM.
#

Get-VMSnapshot -VM $vmName -Server $hvServer -Name "TestExport" | Remove-VMSnapshot -Force


#
# Save the GUID of exported VM.
#

$ExportedVM = Get-VM $vmName -server $hvServer

$ExportedVMID = $ExportedVM.Name

#
# Import back the above exported VM.
#


HyperV\Import-VM -Paths ${rootDir}\${vmName} -Server $hvServer -ReimportVM $vmName  -Force -wait | Out-Null
if ($? -ne "True")
{
    Write-Output "Error while importing the VM" | Out-File -Append $summaryLog
    return $retVal
}

Write-Output "VM ${vmName} is imported back successfully"  

#
# Check that the imported VM has a snapshot 'TestExport', apply the snapshot and start the VM.
#
$Vms = Hyperv\Get-VM $vmName -server $hvServer
foreach ($vm in $Vms)
{
    if ($ExportedVMID -ne $vm.Name)
    {
        Hyperv\Set-VM $vm -Name "ImportedVM" -Server $hvServer -Confirm:$false
        break
    }
   
}
Get-VMSnapshot -Server $hvServer -vm "ImportedVM"  -Name "TestExport" | Restore-VMSnapshot -Force -Verbose
if ($? -ne "True")
{
    Write-Output "Error while applying the snapshot to imported VM" | Out-File -Append $summaryLog
    return $retVal
}

Start-VM "ImportedVM" -Wait 
Start-Sleep -Seconds 120
   
#
# Verify that the imported VM has started successfully
#
        
$ImportedVM = Get-VM "ImportedVM" -server $hvServer

while ($testCaseTimeout -gt 0)
{
    if ($($ImportedVM.EnabledState) -eq 2)
    {
        break
    }
    Start-Sleep -seconds 2
    $testCaseTimeout -= 2
}

if ($testCaseTimeout -eq 0)
{
    "Error: Test case timed out waiting for Imported VM to reboot"
    return $retVal
}

Write-Output "Imported VM has a snapshot TestExport, applied the snapshot and VM started successfully" 

#
# Clean-up - stop the imported VM, remove it and delete the export folder. 
# 
Stop-VM "ImportedVM" -Wait -force -Verbose
if ($? -ne "True")
{
    Write-Output "Error while stopping the imported VM" | Out-File -Append $summaryLog
    return $retVal
}
   
Remove-VM "ImportedVM" -wait -Force -Verbose
if ($? -ne "True")
{
    Write-Output "Error while removing the VM" | Out-File -Append $summaryLog
    return $retVal
}
  
Remove-Item -Path ${rootDir}\${VmName} -Recurse -Force | Out-Null
if ($? -ne "True")
{
    Write-Output "Error while deleting the export folder trying again"
    del -Recurse -Path "${rootDir}\${VmName}" -Force | Out-Null
}
   
Write-Output "Imported VM ${vmName} is stopped and deleted successfully" 
Write-Output "VM exported with a new snapshot and imported back successfully" | Out-File -Append $summaryLog

return $true
