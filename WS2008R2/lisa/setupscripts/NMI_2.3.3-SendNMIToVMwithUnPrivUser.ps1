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
    

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>
#######################################################################
# NMI_2.3.3-SendNMIToVMwithUnPrivUser.ps1
#
# Description:
# This powershell automates the TC-2.3.3 - A user with insufficient
# privileges attempting to send a NMI should receive an error.
#
#######################################################################

param([string] $vmName, [string] $hvServer, [string] $testParams)

#######################################################################
# function CreateLocalUser ()
#
# This function create a local user account
#
#######################################################################
function CreateLocalUser()
{
    $ComputerName = $env:COMPUTERNAME
    $Computer = [adsi]"WinNT://$ComputerName"
    $UserName = "TestUser"
    $Password = "Password1"
    echo $Password | out-file -encoding ASCII -filePath ./pass.txt
    $User = $Computer.Create("user",$UserName)
    $User.SetPassword($Password)
    $User.SetInfo()
    if(!$?)
    {
        return $false
    }
}
#######################################################################
# function DeleteLocalUser ()
#
# This function delete a local user account
#
#######################################################################
function DeleteLocalUser()
{
    $ComputerName = $env:COMPUTERNAME
    $Computer = [adsi]"WinNT://$ComputerName"
    $UserName = "TestUser"
    $User = $Computer.Delete("user",$UserName)
    if(!$?)
    {
        return $false
    }
}
#######################################################################
#
# Main script body
#
#######################################################################
$retVal = $false

#
# Check input arguments
#
if (-not $vmName)
{
    "Error: VM name is null. "
    return $retVal
}

if (-not $hvServer)
{
    "Error: hvServer is null"
    return $retVal
}

if (-not $testParams)
{
    "Error: testParams is null"
    return $retVal
}

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    switch ($fields[0].Trim())
    {
    "rootdir" { $rootDir = $fields[1].Trim() }
    default   {}  # unknown param - just ignore it
    }
}

#
# Change the working directory to where we need to be
#
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

cd $rootDir

#
# Updating the summary log with Testcase ID details
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers NMI TC-2.3.3" | Out-File $summaryLog



#
# Creating a local user account with no prvileges on the hyper-v host
#
CreateLocalUser
if(!$?)
{
    Write-Output "Error: User could not be created" | Out-File -Append $summaryLog
    return $false
}


#
# Read the password from the file
#
$passwd = Get-Content ./pass.txt | ConvertTo-SecureString -asplaintext -force
if(!$?)
{
    Write-Output "Error: Could not read the password from the specified file" | Out-File -Append $summaryLog
    return $false
}


#
# Create a credential object
#
$creds = New-Object -Typename System.Management.Automation.PSCredential -ArgumentList "TestUser",$passwd
if(!$?)
{
    Write-Output "Error: Could not created the credential object" | Out-File -Append $summaryLog
    return $false
}


#
# Now try to send NMI to Linux VM using the unprvileged credentials through a job.
#
$cmd = [Scriptblock]::Create("Debug-VM -Name $vmName -InjectNonMaskableInterrupt -ComputerName $hvServer 2>&1")

$newJob = Start-job -scriptblock $cmd -credential $creds

$job = Get-Job -id $newJob.Id

While ($job.State -ne "Completed")
{
    if($job.State -eq "Failed")
    {
        break
    }
    start-sleep 2
}
$nmistatus = Receive-Job -Id $newJob.Id

#
# Deleting the previously created user account
#
DeleteLocalUser
if(!$?)
{
    Write-Output "Error: User could not be deleted" | Out-File -Append $summaryLog
}

#
# Verifying the job output
#
$errorstr = "Hyper-V was unable to find a virtual machine"
$match = $nmistatus | select-string -Pattern $errorstr -Quiet
if ($match -eq "True")
{
    Write-Output "Test Passed. NMI could not be sent to Linux VM with unprivileged user" | Out-File -Append $summaryLog
    $retval = $true
}
else
{
    Write-Output "Error: Test Failed. NMI request was sent to Linux VM using unprivileged user account" | Out-File -Append $summaryLog
    return $false
}

return $retval