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
	Attempts to send a NMI as an unprivileged user.

.Description
	The script will try to send a NMI to a specific VM. A user with insufficient 
	privileges attempting to send a NMI will receive an error. This is the expected
	behavior and the test case will return the results as such.

    The test case definition for this test case would look similar to:
        <test>
            <testName>NMI_SendAs_Unprivileged</testName>
            <testScript>setupscripts\NMI_SendAs_Unprivileged.ps1</testScript>
            <timeout>600</timeout>
            <onError>Continue</onError>
			<testParams>
                <param>TC_COVERED=NMI-03</param>
                <param>rootDir=D:\lisa</param>
            </testParams>
            <noReboot>True</noReboot>
        </test>

.Parameter vmName
    Name of the VM to perform the test with.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.

.Example
    .\NMI_SendAs_Unprivileged.ps1 -vmName "MyVM" -hvServer "localhost" -testParams "rootDir=D:\lisa;TC_COVERED=NMI-03"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false
$random = Get-Random -minimum 1024 -maximum 4096

#######################################################################
#
# function CreateLocalUser ()
# This function create a new Windows local user account
#
#######################################################################
function CreateLocalUser()
{
    $ComputerName = $env:COMPUTERNAME
    $Computer = [adsi]"WinNT://$ComputerName"
    $UserName = "TestUser_$random"
    $Password = "P@ssw0rd123"
    echo $Password | out-file -encoding ASCII -filePath ./pass.txt
    $User = $Computer.Create("user",$UserName)
    $User.SetPassword($Password)
    $User.SetInfo()
    if(!$?)
    {
		Write-Output "Unable to create a temporary username."  | Tee-Object -Append -file $summaryLog
        return $false
    }
	else
	{
		Write-Output "Successfully created temporary username: $UserName"  | Tee-Object -Append -file $summaryLog
		$retval = $true	
	}
}

#######################################################################
#
# function DeleteLocalUser ()
# This function will delete a Windows local user account
#
#######################################################################
function DeleteLocalUser()
{
    $ComputerName = $env:COMPUTERNAME
    $Computer = [adsi]"WinNT://$ComputerName"
	$UserName = "TestUser_$random"
    $User = $Computer.Delete("user",$UserName)
    if(!$?)
    {
		Write-Output "Unable to delete the temporary username $UserName"  | Tee-Object -Append -file $summaryLog
        return $false
    }
	else
	{
		Write-Output "Successfully removed the temporary username $UserName"  | Tee-Object -Append -file $summaryLog
		$retval = $true	
	}
}

#
# Check the input arguments
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
    "This script requires the test case ID and the logs folder as test parameters."
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

#
# Change the working directory for the log files
# Delete any previous summary.log file, then create a new one
#
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $retVal
}
cd $rootDir

$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Verifies if the VM exists and if it is running
#
$VM = Get-VM $vmName -ComputerName $hvServer
if (-not $VM)
{
    Write-Output "Error: Cannot find the VM ${vmName} on server ${hvServer}" | Tee-Object -Append -file $summaryLog
    return $False
}

if ($($vm.State) -ne [Microsoft.HyperV.PowerShell.VMState]::Running )
{
    "Error: VM ${vmName} is not running!"
    return $False
}

#
# Creating a local user account with limited privileges on the Hyper-V host
#
CreateLocalUser
if(!$?)
{
    Write-Output "Error: User could not be created" | Tee-Object -Append -file $summaryLog
    return $false
}

#
# Read the password from the file
#
$passwd = Get-Content ./pass.txt | ConvertTo-SecureString -asplaintext -force
if(!$?)
{
    Write-Output "Error: Could not read the password from the specified file" | Tee-Object -Append -file $summaryLog
    return $false
}

#
# Create a credential object
#
$creds = New-Object -Typename System.Management.Automation.PSCredential -ArgumentList "TestUser_$random",$passwd
if(!$?)
{
    Write-Output "Error: Could not created the credential object" | Tee-Object -Append -file $summaryLog
    return $false
}

#
# Attempting to send NMI to Linux VM using the unprivileged credentials through a job
#
$cmd = [Scriptblock]::Create("Debug-VM -Name $vmName -InjectNonMaskableInterrupt -ComputerName $hvServer 2>&1")
$newJob = Start-job -scriptblock $cmd -credential $creds
$job = Get-Job -id $newJob.Id

While ($job.State -ne "Completed")
{
    if($job.State -eq "Failed")
    {
        Write-Output "Job Failed!" | Tee-Object -Append -file $summaryLog
        return $false
    }
    start-sleep 2
}
$nmi_status = Receive-Job -Id $newJob.Id -Wait -WriteJobInResults -WriteEvents

#
# Deleting the previously created user account
#
DeleteLocalUser
if(!$?)
{
    Write-Output "Error: Temporary restricted user could not be deleted!" | Tee-Object -Append -file $summaryLog
}

#
# Verifying the job output
#
$errorstr = "A parameter is invalid. Hyper-V was unable to find a virtual machine with name $vmname."
$match = $nmi_status | select-string -Pattern $errorstr -Quiet
if ($match -eq "True")
{
    Write-Output "Test passed! NMI could not be sent to Linux VM with unprivileged user." | Tee-Object -Append -file $summaryLog
    $retval = $true
}
else
{
    Write-Output "Test failed! Error: NMI request was sent to Linux VM using unprivileged user account!" | Tee-Object -Append -file $summaryLog
    return $false
}

return $retval
