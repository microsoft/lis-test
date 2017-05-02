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
    Check the VM shuts down using a host side trigger

.Description
	TestVMShutdown will send a shutdown request to the specific VM.
	It then will wait to confirm the VM left the Running state.

    The test case definition for this test case would look similar to:
		<test>
			<testName>LISShutdownVM</testName>
			<setupScript>setupScripts\ChangeCPU.ps1</setupScript>
			<testScript>setupscripts\INST_LIS_TestVMShutdown.ps1</testScript>
			<testParams>
				<param>TC_COVERED=CORE-07</param>
				<param>vCPU=5</param>
			</testParams>
			<timeout>600</timeout>
			<onError>Continue</onError>
			<noReboot>False</noReboot>
        </test>

.Parameter vmName
    Name of the VM to perform the test with.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.

.Example
    .\INST_LIS_TestVMShutdown.ps1 -vmName "MyVM" -hvServer "localhost" -testParams "TC_COVERED=CORE-07;vCPU=5"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$rootDir = $null
$vmIPAddr = $null
$vcpu = $null
$testCaseTimeout = 600

#####################################################################
#
# CheckVMState()
#
#####################################################################
function CheckVMState([String] $vmName, [String] $newState)
{
    $stateChanged = $False
    
    $vm = Get-VM $vmName -ComputerName $hvServer    
    if ($($vm.State.ToString()) -eq $newState)
    {
        $stateChanged = $True
    }
    
    return $stateChanged
}

#####################################################################
#
# Main script body
#
#####################################################################

# Check input arguments
if ($vmName -eq $null)
{
    "Error: VM name is null"
    return $False
}

if ($hvServer -eq $null)
{
    "Error: hvServer is null"
    return $False
}

#
# Parse the testParams string
#
$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {      
    "ipv4"       { $vmIPAddr  = $fields[1].Trim() }
    "rootdir"    { $rootDir   = $fields[1].Trim() }
    "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    "VCPU"       { $vcpu      = $fields[1].Trim() }
    default  {}       
    }
}

if ($rootDir -eq $null)
{
    "Error: The RootDir test parameter is not defined."
    return $False
}

if ($vmIPAddr -eq $null)
{
    "Error: The ipv4 test parameter is not defined."
    return $False
}

if (-not (Test-Path $rootDir) )
{
    "Error: The test root directory '${rootDir}' does not exist"
    return $False
}

cd $rootDir

# Delete any previous summary.log file, then create a new one
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# Source TCUtils.ps1 for test related functions
if (Test-Path ".\setupScripts\TCUtils.ps1")
{
	. .\setupScripts\TCUtils.ps1
}
else
{
	"Error: Could not find setupScripts\TCUtils.ps1"
	return $false
}

#
# The VM should be in a running state.  Ask Hyper-V to invoke a shut-down.
# The VMs state will go from Running to Stopping, then Stopped.
#
"Info: Verifying if the VM is running"
$vm = Get-VM $vmName -ComputerName $hvServer
if (-not $vm)
{
    "Error: Cannot find VM ${vmName} on server ${hvServer}"
    Write-Output "VM ${vmName} not found" | Out-File -Append $summaryLog
    return $False
}

if ($($vm.State) -ne [Microsoft.HyperV.PowerShell.VMState]::Running )
{
    "Error: VM ${vmName} is not in the running state!"
    return $False
}

#
# If a VCPU test parameter was passed, we are doing a test with
# multiple CPUs.  Make sure the VM has the correct number of
# CPUs configured.
#
if ($vcpu)
{
    if ($vm.ProcessorCount -ne $vcpu)
    {
        "Error: VM ${vmName} is configure with the wrong number of VCPUs"
        "       The VM has $($vm.ProcessorCount) processors. It should have ${vcpu}"
        return $False
    }
}

#
# Ask Hyper-V to request the VM to shut-down, then wait for the 
# VM to go into a Stopped state
#
"Info: Shutting down the VM"
Stop-VM -Name $vmName -ComputerName $hvServer -Force
while ($testCaseTimeout -gt 0)
{
    if ( (CheckVMState $vmName "Off"))
    {
        break
    }   

    Start-Sleep -seconds 2
    $testCaseTimeout -= 2
}

if ($testCaseTimeout -eq 0)
{
    "Error: Test case timed out waiting for VM to go to Stopped"
    return $False
}

"Info: VM Shut-down successful"

#
# Now start the VM so the automation scripts can finish
#
"Info: Starting the VM"
Start-VM -Name $vmName -ComputerName $hvServer -Confirm:$false
if ($? -ne "True")
{
    "Error: Unable to restart the VM!"
    return $False
}

while ($testCaseTimeout -gt 0)
{
    if ( (CheckVMState $vmName "Running"))
    {
        break
    }   

    Start-Sleep -seconds 2
    $testCaseTimeout -= 2
}

if ($testCaseTimeout -eq 0)
{
    "Error: Test case timed out for VM to go to Running"
    return $False
}

"Info: VM successfully started"

#
# Finally, we need to wait for TCP port 22 to be available on the VM
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
    "Error: Test case timed out for VM returned to Running"
    return $False
}

"Info: SSH is running on the test VM"

#
# If we got here, the VM was shut-down and restarted
#
"Test completed successfully"
return $True
