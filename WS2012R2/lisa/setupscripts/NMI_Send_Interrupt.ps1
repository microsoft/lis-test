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
	Sends a NMI to a given VM by using the Debug-VM cmdlet

.Description
	The script will send a NMI to the specific VM. Script must be executed 
	under PowerShell running with Administrator rights, unprivileged user 
	can not send the NMI to VM.
	This must be used along with the nmi_verify_interrupt.sh bash script to 
	check if the NMI is successfully detected by the Linux guest VM.

    The test case definition for this test case would look similar to:
        <test>
            <testName>NMI_Send_Interrupt</testName>
            <testScript>setupscripts\NMI_Send_Interrupt.ps1</testScript>
            <timeout>600</timeout>
            <onError>Continue</onError>
			<testParams>
                <param>TC_COVERED=NMI-01</param>
                <param>rootDir=D:\lisa</param>
            </testParams>
            <noReboot>True</noReboot>
        </test>
		
		<test>
            <testName>NMI_Verify_Interrupt</testName>
            <testScript>nmi_verify_interrupt.sh</testScript>
			<files>remote-scripts\ica\nmi_verify_interrupt.sh</files>
            <timeout>600</timeout>
            <onError>Continue</onError>
            <testParams>
                <param>TC_COVERED=NMI-01</param>
            </testParams>
			<noReboot>False</noReboot>
        </test>

.Parameter vmName
    Name of the VM to perform the test with.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.

.Example
    .\NMI_Send_Interrupt.ps1 -vmName "MyVM" -hvServer "localhost" -testParams "rootDir=D:\lisa;TC_COVERED=NMI-01"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false

#
# Check input arguments
#
if (-not $vmName)
{
    "Error: VM name is null."
    return $retVal
}

if (-not $hvServer)
{
    "Error: hvServer is null."
    return $retVal
}

if (-not $testParams)
{
    "Error: No testParams provided!"
    "This script requires the test case ID and the logs folder as the test parameters."
    return $retVal
}

#
# Checking the mandatory testParams
#
$TC_COVERED = $null
$rootDir = $null

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    if ($fields[0].Trim() -eq "TC_COVERED")
    {
        $TC_COVERED = $fields[1].Trim()
    }
     if ($fields[0].Trim() -eq "rootDir")
    {
        $rootDir = $fields[1].Trim()
    }
}

if (-not $TC_COVERED)
{
    "Error: Missing testParam TC_COVERED value"
    return $retVal
}

if (-not $rootDir)
{
    "Error: Missing testParam rootDir value"
    return $retVal
}

# Change the working directory for the log files
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $retVal
}
cd $rootDir

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Checking if PowerShell is running as Administrator
#
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-output "You do not have Administrator rights to run this script." | Tee-Object -Append -file $summaryLog
    return $False
}

#
# The VM must be in a running state
#
$vm = Get-VM $vmName -ComputerName $hvServer
if (-not $vm)
{
    Write-output "Error: Cannot find the VM ${vmName} on server ${hvServer}" | Tee-Object -Append -file $summaryLog
    return $False
}

if ($($vm.State) -ne [Microsoft.HyperV.PowerShell.VMState]::Running )
{
    "Error: VM ${vmName} is not in the running state!"
    return $False
}

#
# Sending NMI to VM
#
Debug-VM -Name $vmName -InjectNonMaskableInterrupt -ComputerName $hvServer -Confirm:$False -Force
if($?)
{
	Write-output "Successfully sent a NMI to VM $vmName" | Tee-Object -Append -file $summaryLog
    $retVal = $true
}
else
{
    Write-output "NMI could not be sent to VM $vmName" | Tee-Object -Append -file $summaryLog
    $retVal = $false
}

return $retval
