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
   This script creates a Nano Server image from scratch. The image will be
   copied to an existing specified server, than boot it into Nano.

.Parameter computerName
    The existing server wich will be booted into Nano Server

.Parameter computerNameNew
    The name given to the Nano Server

.Parameter adminPassword
    The existing server's administrator password, so we can access it and deploy
    Nano on it. The same password will be used for the Nano Server's Administrator
    account.

.Parameter domainName
    If specified, the newly created Nano Server will be joined to this domain.

.Parameter isoFolder
    The folder which contains the WS 2016 ISO with Nano Server as well. If none
    specified, the path with the latest build will be specified. The script will
    select the ISO from the folder.

.Parameter users
    The users which will be added to the Administrators group on the Nano Server
    Please list the users with a space between them.
    Eg: user01 user02 user03

.Parameter workspacePath
    The path which will be used for creating the Nano Server image. If none is
    specified, the working directowy will be used.

.Example
    .\deployNano.ps1 -computerName "Server01" -computerNameNew "Nano-Server" -adminPassword "somepassword" -domainName "domain1" -isoFolder "\\path\to\isoFolder" -users "user01 user02 user03" "-workspacePath "C:\workspace"
#>



#

param([string] $computerName, [string] $computerNameNew, [string] $adminPassword, [string] $domainName, [string] $isoFolder, [string] $users, [string] $workspacePath)

###############################################################################
##This function gets the ISO with the latest build if no path is selected
###############################################################################

function GetIsoLocation
{
    $buildFolder = $(Get-ChildItem \\winbuilds\release\TH2_Release\ | Where-Object {  $_.mode -like 'd*' } | Sort LastWriteTime | Select -Last 1).Name
    if (-not $buildFolder)
    {
        Write-Host "Could not determine the latest Windows Server's build folder"
    }

    $buildInfo = $buildFolder.Substring(0,$buildFolder.IndexOf("."))

    $isoFolder = "\\winbuilds\release\TH2_Release\$buildFolder\amd64fre\iso\iso_server_en-us_vl\"

    return $isoFolder
}

if (-not $isoFolder)
{
    $isoFolder = GetIsoLocation
    if (-not $isoFolder)
    {
        Write-Host "Could not set the ISO's location"
        return $false
    }
}

$isoFile = $(Get-ChildItem $isoFolder | Where-Object {  $_.extension -eq '.ISO' } | Sort LastWriteTime | Select -Last 1).Name
if (-not $isoFile)
{
    Write-Host "Could not find the image file"
    return $false
}

if (-not $isoFolder.EndsWith("\"))
{
    $isoFolder += "\"
}

$isoPath = $isoFolder + $isoFile

if (-not $workspacePath)
{
    Write-Host "There is no workspace path specified. Your current path will be set as workspace."
    $workspacePath = pwd
}

Write-Host "$workspacePath is the workspace path"
Write-Host "The path of the ISO file is $isoPath"


###############################################################################
##Copying ISO to workspace path
###############################################################################
Write-Host "Copying ISO to workspace directory $workspacePath"
Copy-Item -Path $isoPath -Destination $workspacePath -Force
if (-not $?)
{
    Write-Host "Could not copy ISO to the workspace"
    return $false
}

$isoPath = $workspacePath + "\" + $isoFile

if (-not $buildInfo)
{
    $buildInfo = $isoFile.Substring(0,$isoFile.IndexOf("."))
    if (-not $buildInfo)
    {
        Write-Host "Could not get the build number"
        return $false
    }
}

if (-not $computerName)
{
    Write-Host "There is no server specified on which Nano will be deployed!"
    return $false
}

if (-not $computerNameNew)
{
    Write-Host "You didn't specify a name for the Nano server. lis-nano-$buildInfo will be used."
    $computerNameNew = "lis-nano-$buildInfo"
}

if (-not $workspacePath)
{
    Write-Host "There is no drive specified to run the setup"
    return $false
}

if (-not $adminPassword)
{
    Write-Host "There is administrator password specified."
    return $false
}

Write-Host "The new server name will be $computerNameNew"

$userName = "$computerName\Administrator"

$securePassword = ConvertTo-SecureString -string $adminPassword -asplaintext -force

if (-not $securePassword)
{
    Write-Host "Could not set a secure password for $computerNameNew"
    return $false
}

$credentials = New-Object -typename System.Management.Automation.PSCredential -argument $userName, $securePassword

if (-not $credentials)
{
    Write-Host "Could not set up credentials to enter $computerName"
    return $false
}

###############################################################################
##Add the remote server on which Nano will be deployed to the trusted hosts
###############################################################################
Set-Item WSMan:\localhost\Client\TrustedHosts $computerName -Force
if (-not $?)
{
    Write-Host  "Failed to add $computerName to the trusted hosts list"
    return $false
}

Write-Host "Successfully added $computerName to the TrustedHosts"

$session = New-PSSession -credential $credentials -ComputerName $computerName
if (-not $session)
{
    Write-Host  "Could not create Powershell session for $computerName"
    return $false
}


###############################################################################
##Select the default drive. The image with the Nano Server will be coped here
###############################################################################

$defaultVhdPath = Invoke-Command -Session $session -ScriptBlock {
    $defaultVhdPath = Get-VMHost | Select -ExpandProperty VirtualHardDiskPath
    return $defaultVhdPath
}

$defaultVhdPath = $defaultVhdPath.Replace(':','$')
if (-not $defaultVhdPath.EndsWith("\"))
{
    $defaultVhdPath += "\"
}

$defaultDrive = $defaultVhdPath.Substring(0,2)


###############################################################################
##Mount ISO and import Nano Server Image Generator module
###############################################################################

Write-Host "Mounting ISO"

Mount-DiskImage -ImagePath $isoPath
if (-not $?)
{
    Write-Host  "Failed to mount the Windows Server image"
    return $false
}

$driveLetter = Get-DiskImage -ImagePath $isoPath | Get-Volume
$driveLetter = $driveLetter.DriveLetter
$driveLetter = $driveLetter + ":"

Import-Module $driveLetter\NanoServer\NanoServerImageGenerator.psm1
if (-not $?)
{
    Write-Host  "Could not import the NanoServerImageGenerator module"
    return $false
}
Write-Host "Successfully imported NanoServerImageGenerator module"


###############################################################################
##If set, try to join the new server to a domain
###############################################################################

$domainParam = $null

if (&domainName)
{
    Write-Host "Provisioning $computerNameNew in the domain"
    djoin  /provision /domain &domainName /machine $computerNameNew /savefile $workspacePath\odjblob /REUSE
    if (-not $?)
    {
        Write-Host  "Could not provision $computerNameNew to the domain"
        return $false
    }

    $domainParam = "-DomainBlobPath $workspacePath\odjblob"
    Write-Host "Successfully provisioned $computerNameNew in the $domainName domain"
}

$vhdName = "nanoVHD" + $buildInfo +".vhdx"


###############################################################################
##Create the vhdx with the Nano server
###############################################################################

Write-Host "Creating the Nano Server VHD"
New-NanoServerImage -MediaPath $driveLetter -BasePath $workspacePath\Base -TargetPath $workspacePath\NanoServer\$vhdName -AdministratorPassword $securePassword $domainParam -OEMDrivers -Compute -Clustering -EnableRemoteManagementPort
if (-not $?)
{
    Write-Host  "Could not create the new VHD with the Nano server"
    return $false
}
Write-Host "VHD successfully created"


###############################################################################
##Copy the newly created vhdx to the secified existing server
###############################################################################

net use z:
if ($?)
{
    net use z: /delete
    if (-not $?)
    {
        Write-Host  "Could not delete network name z:"
        return $false
    }
}

net use z: \\$computerName\$defaultDrive
if (-not $?)
{
    Write-Host  "Could not set network name z: with remote path: \\$computerName\$defaultDrive"
    return $false
}
Write-Host  "Successfully set network name z: with remote path: \\$computerName\$defaultDrive"

if (!(Test-Path z:\NanoServer\))
{
    Write-Host "Creating folder where the vhd will be placed"
    mkdir z:\NanoServer\
}

Write-Host "Copying $vhdName to $computerName "
Copy-Item -Path $workspacePath\NanoServer\$vhdName z:\NanoServer
if (-not $?)
{
    Write-Host  "Could not copy the newly created Nano Server VHD to the destination server"
    return $false
}


###############################################################################
##Set Nano vhdx as the default boot device
###############################################################################

$defaultLocalDrive = $defaultDrive.Replace('$',':')

Write-Host "Editing bcdedit on the target server"
Invoke-Command -Session $session -ScriptBlock {
    param($buildInfo, $vhdName, $defaultLocalDrive)
    $guidIdentifier = (CMD /C "bcdedit /copy {current} /d 'NanoServer-$buildInfo'") | Out-String
    $guidIdentifier = $guidIdentifier.Substring($guidIdentifier.IndexOf("{"))
    $guidIdentifier = $guidIdentifier.Substring(0,$guidIdentifier.IndexOf("."))
    CMD /C "bcdedit /set $guidIdentifier device vhd=[$defaultLocalDrive]\NanoServer\$vhdName"
    CMD /C "bcdedit /set $guidIdentifier osdevice vhd=[$defaultLocalDrive]\NanoServer\$vhdName"
    CMD /C "bcdedit /set $guidIdentifier path \windows\system32\boot\winload.exe"
    CMD /C "bcdedit /default $guidIdentifier"
    Start-sleep 10
    Restart-Computer -Force
} -ArgumentList $buildInfo, $vhdName, $defaultLocalDrive

Remove-PSSession $session

Write-Host "Restarting $computerName and booting into $computerNameNew. Waiting 10 minutes"

Start-sleep 600


###############################################################################
##Set the newly installed Nano credentials and add it to the trusted hosts
###############################################################################

$userName = "$computerNameNew\Administrator"
$credentials = New-Object -typename System.Management.Automation.PSCredential -argument $userName, $securePassword
if (-not $credentials)
{
    Write-Host "Could not set up credentials to enter $computerNameNew"
    return $false
}

Set-Item WSMan:\localhost\Client\TrustedHosts $computerNameNew -Force
if (-not $?)
{
    Write-Host  "Failed to add $computerNameNew to the trusted hosts list"
    return $false
}

Write-Host "Successfully added $computerName to the TrustedHosts"

$session = New-PSSession -credential $credentials -ComputerName $computerNameNew
if (-not $session)
{
    Write-Host  "Could not create Powershell session for $computerNameNew"
    return $false
}


###############################################################################
##Add users to the administrator list
###############################################################################

if ($users)
{
    Write-Host "Adding users to the newly deployed Nano Server"
    Invoke-Command -Session $session -ScriptBlock {
        param($users)
        CMD /C "for %i in ($users) do net localgroup Administrators Redmond\%i /add"
    } -ArgumentList $users
}

Remove-PSSession $session

Dismount-DiskImage -ImagePath $isoPath
if (-not $?)
{
    Write-Host  "Failed to unmount the Windows Server image"
}

Write-Host "Successfully deployed Nano Server $buildInfo. Server Name is: $computerNameNew"

return $true