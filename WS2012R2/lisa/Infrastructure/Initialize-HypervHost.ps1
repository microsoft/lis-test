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
    Initialize a Windows Server to allow running LIS test cases using
    the LISA test framework.

.Description 
    Initialize, or provision, a Windows Server so LIS test cases can be
    run using the LISA test framework.  As a minimum, the LISA test
    framework requires the Windows Server be provisioned as follows:
      - The Hyper-V feature is installed.
      - The required Hyper-V vSwitches are created.

    This script is intended to be run interactively.  If this script
    installs a new role or feature, such as the Hyper-V role, the user
    will be prompted to perform a reboot to complete installation of
    the role/feature.  The user should run this script again to complete
    any additional provisioning.

    LIS network test cases use various vSwitches.  If the -vSwitch option
    is specified, this script will attempt to create the vSwitches.  The
    vSwitch names used by the Network test cases are:

        Type        vSwitch Name
        ----------  ------------
        External    External
        Internal    Internal
        Private     Private
        Private     Private2

    For Private and Internal vSwitches the script will create the vSwitches
    if they do not already exist.  For the external switch, the external
    vSwitch will only be created if one, and only one, physical network
    adapter is found that is up and has media connected.  Otherwise, a
    warning message will be displayed informing the user to manually
    create the external vSwitch.

        Note: If there are more than one potential physical network
              adapter to associate with the external vSwitch, it is
              very difficult to determine which physical NIC a user
              might want to use with the external vSwitch.

    In addition to installing roles and features that are required for
    running various LIS test cases, additional behavior is supported
    such as:
      - Installing a Git client.
      - Cloning the lis-test repository from GitHub.
      - Installing the Putty SSH utilities into the lisa\bin directory.
      - Modifying the Hyper-V Virtual Machine path.
      - Modifying the Hyper-V Virtual Hard Disk path.
      - Copying the contents of an external folder into the lisa directory.


.Parameter HyperV
    Install the Hyper-V role.

.Parameter BackupServer
    Install the Windows Server Backup feature.

.Parameter FailoverClustering
    Install the Failover Clustering role.

.Parameter VSwitches
    Attempt to create the Hyper-V vSwitches used by network test cases.

.Parameter NoExternalSwitch
    Do not attempt to create the external switch.

.Parameter NoInternalSwitch
    Do not attempt to create the internal switch.

.Parameter NoPrivateSwitches
    Do not attempt to create any of the private switches.

.Parameter Git
    Install the Git client from GitHub.com.

.Parameter Clone
    Use the Git client to clone the lis-test repository from GitHub.com.

.Parameter Putty
    Install the Putty utilities.

.Parameter ExternalFolderSync
    Absolute path of the external folder to sync with.  Syncing will copy
    the contents of the external folder to the lis-test\WS2012R2\lisa directory.

.Parameter VhdPath
    Modify the Hyper-V VirtualHardDiskPath to the specified directory.

.Parameter VmPath
    Modify the Hyper-V VirtualMachinePath to the specified directory.

.Example
    .\ProvisionHypervHost.ps1
    Install the Hyper-V feature, and create the vSwitches.

.Example
    .\ProvisionHypervHost.ps1 -NoHyperv -NoVSwitches -Git -Clone
    Do not install the Hyper-V feature, do not create the vSwitches,
    install the Git client, and clone the lis-test repository from GitHub.
#>


param ([Switch] $HyperV,
       [Switch] $BackupServer,
       [Switch] $FailoverClustering,
       [Switch] $VSwitches,
       [Switch] $NoExternalSwitch,
       [Switch] $NoInternalSwitch,
       [Switch] $NoPrivateSwitches,
       [Switch] $Git,
       [Switch] $Clone,
       [Switch] $Putty,
       [String] $VhdPath,
       [String] $VmPath,
       [String] $ExternalFolderSync )

# hide cmdlets progress bar
$progressPreference = 'silentlyContinue'

$internalSwitchName = "Internal"
$externalSwitchName = "External"
$privateSwitchName1 = "Private"
$privateSwitchName2 = "Private2"

$GitUrl     = "https://github.com/git-for-windows/git/releases/download/v2.15.0.windows.1/Git-2.15.0-64-bit.exe"

$lisTestUrl = "https://github.com/LIS/lis-test"

$puttyBaseURL = "http://the.earth.li/~sgtatham/putty/latest"


#######################################################################
#
# CreateExternalSwitch() 
#
#######################################################################
function CreateExternalSwitch()
{
    #
    # We will only create an external switch if:
    #  - The host only has a single physical NIC, and an external switch
    #    does not already exist.
    #  - The host has multiple physical NICs, but only one is connected,
    #    and an external switch does not already exist.
    # If an external switch does not exist, and we are unable to create
    # the external switch, display a message instructing the user to 
    # manually create the external switch.
    #

    Write-Host "Info: Checking for External vSwitch named '${externalSwitchName}'"
    $externalSwitch = Get-VMSwitch -Name "${externalSwitchName}" -ErrorAction SilentlyContinue
    if ($externalSwitch)
    {
        #
        # A vSwitch named external already exists
        #
        Write-Host -f Yellow "Warning: The external vSwitch '${externalSwitchName}' already exists"
        return
    }

    $adapters = Get-NetAdapter
    $numPotentialNICs = 0
    $potentialNIC = $null

    foreach ($nic in $adapters)
    {
        #
        # Make sure NIC is connected (MediaConnectState = 1)
        # and the NIC is up (InterfaceOperationalStatus = 1)
        # and the physical medium is specified (NdisPhysicalMedium != 0)
        #
        if ($nic.InterfaceOperationalStatus -eq 1 -and $nic.MediaConnectState -eq 1 -and $nic.NdisPhysicalMedium -ne 0)
        {
            $numPotentialNICs += 1
            $potentialNIC = $nic.InterfaceDescription
            Write-Host "Info: Potential NIC for external vSwitch = '${potentialNIC}'"
        }
    }

    if ($numPotentialNICs -eq 0)
    {
        Write-Host -f Yellow "Warning: No potential NICs found to create an External vSwitch"
        Write-Host -f Yellow "         You will need to manually create the external vSwitch"
        exit 1
    }
    elseif ($numPotentialNICs -gt 1)
    {
        Write-Host -f Yellow "Warning: There are more than one physical NICs that could be used"
        Write-Host -f Yellow "         with an external vSwitch.  You will need to manually"
        Write-Host -f Yellow "         create the external vSwitch"
        exit 1
    }

    #
    # Create an External NIC using the one potential physical NIC
    #
    $s = New-VMSwitch -Name "${externalSwitchName}" -NetAdapterInterfaceDescription "${potentialNIC}"
    if (-not $?)
    {
        Throw "Error: Unable to create external vSwitch using NIC '${potentialNIC}'"
    }
    Write-Host "Info: External vSwitch '${externalSwitchName}' was created, using physical NIC"
    Write-Host "      ${potentialNIC}"
}


#######################################################################
#
# CreateInternalSwitch()
#
#######################################################################
function CreateInternalSwitch()
{
    #
    # See if an internal switch named 'Internal' already exists.
    # If not, create it
    #
    Write-Host "Info: Checking for Internal vSwitch named '${internalSwitchName}'"
    $internalSwitch = Get-VMSwitch -Name "${internalSwitchName}" -ErrorAction SilentlyContinue
    if (-not $internalSwitch)
    {
        $s = New-VMSwitch -Name "${internalSwitchName}"  -SwitchType Internal
        if (-not $?)
        {
            Throw "Error: Unable to create Internal switch"
        }
        Write-Host "Info: Internal vSwitch '${internalSwitchName}' was created"
    }
    else
    {
        Write-Host -f Yellow "Warning: The Internal vSwitch '${internalSwitchName}' already exists"
    }
}


#######################################################################
#
# CreatePrivateSwitches()
#
#######################################################################
function CreatePrivateSwitches()
{
    #
    # See if an internal switch named 'Internal' already exists.
    # If not, create it
    #
    Write-Host "Info : Checking for Private vSwitch named '${PrivateSwitchName1}'"
    $privateSwitch = Get-VMSwitch -Name "${privateSwitchName1}" -ErrorAction SilentlyContinue
    if (-not $privateSwitch)
    {
        $s = New-VMSwitch -Name "${privateSwitchName1}"  -SwitchType Private
        if (-not $?)
        {
            Throw "Error: Unable to create Private switch 1"
        }
        Write-Host "Info: Private vSwitch '${privateSwitchName1}' was created"
    }
    else
    {
        Write-Host -f Yellow "Warning: the vSwitch '$privateSwitchName1}' already exists"
    }

    Write-Host "Info : Checking for Private vSwitch named '${PrivateSwitchName2}'"
    $privateSwitch = Get-VMSwitch -Name "${privateSwitchName2}" -ErrorAction SilentlyContinue
    if (-not $privateSwitch)
    {
        $s = New-VMSwitch -Name "${privateSwitchName2}"  -SwitchType Private
        if (-not $?)
        {
            Throw "Error: Unable to create Private switch 2"
        }
        Write-Host "Info: Private vSwitch '${privateSwitchName2}' was created"
    }
    else
    {
        Write-Host -f Yellow "Warning: the vSwitch '${privateSwichName2}' already exists"
    }
}


#######################################################################
#
# InstallGitClient()
#
#######################################################################
function InstallGitClient()
{
    $GitNotInstalled = $False

    try
    {
       git
    }
    catch
    {
       $GitNotInstalled = $True 
    }

    if ($GitNotInstalled)
    {
        Invoke-WebRequest "${GitUrl}" -OutFile ".\git-installer.exe"
        if (-not $?)
        {
            Throw "Error: Unable to download the git client"
        }

        Start-Process -FilePath ".\git-installer.exe" -ArgumentList "/VERYSILENT" -Wait -NoNewWindow
        if (-not $?)
        {
            Throw "Error: Unable to install the git client"
        }

        del ".\git-installer.exe" -ErrorAction SilentlyContinue

        #
        # Verify Git was installed in the default directory
        #
        $systemDrive = $env:SystemDrive
        $gitPath = "${systemDrive}\Program Files\Git\cmd"
        if (-not (Test-Path "${gitPath}\git.exe"))
        {
            Throw "Error: Git was not installed into the default location of '${gitPath}'"
        }

        #
        # Add the Git directory to the path for this PowerShell session
        #
        $env:Path += ";${gitPath}"

        #
        # Permanently add the Git directory to the path (for future PowerShell sessions)
        #
        [Environment]::SetEnvironmentVariable("Path", $env:Path + ";${gitPath}", [System.EnvironmentVariableTarget]::Machine)
        if (-not $?)
        {
            Throw "Error: Unable to add git path to the Path environment variable"
        }
    }
    else
    {
        Write-Host "Info : A Git client is already installed"
    }
}


#######################################################################
#
# CloneLisTest()
#
#######################################################################
function CloneLisTest()
{
    #
    # Verify we have a Git client installed and in the path
    #
    try
    {
       git > $null
    }
    catch
    {
       Throw "Error: Unable to clone the LIS Test repository - No Git client installed"
    }

    if ( (Test-Path .\lis-test))
    {
        Throw "Error: Unable to clone lis-test. The directory ${PWD}\lis-test already exists"
    }

    git clone "${lisTestUrl}" 2> out-null

    #
    # Verify the lis-test directory was created
    #
    if (-not (Test-Path ".\lis-test"))
    {
        Throw "Error: git clone did not create the lis-test directory in the current directory"
    }
}


#######################################################################
#
# InstallPutty()
#
#######################################################################
function InstallPutty()
{
    #
    # Verify the lisa directory exists.
    # Create the bin subdirectory if it does not exist
    #
    if (-not (Test-Path ".\lis-test\WS2012R2\lisa"))
    {
        Throw "Error: The directory '.\lis-test\WS2012R2\lisa' does not exist"
    }

    if (-not (Test-Path ".\lis-test\WS2012R2\lisa\Bin"))
    {
        Write-Host "Info : The directory lisa\Bin does not exist"
        Write-Host "Info : Creating '.\lis-test\WS2012R2\lisa\bin'"
        $newDir = mkdir ".\lis-test\WS2012R2\lisa\bin"
        if (-not $?)
        {
            Throw "Error: Unable to create the lisa\Bin directory"
        }
    }

    $puttyUtils = @("putty.exe", "pscp.exe", "plink.exe", "puttygen.exe")
    foreach ($util in $puttyUtils)
    {
        Write-Host "Info : downloading ${util}"
        $url = "${puttyBaseUrl}/w32/${util}"
        Invoke-WebRequest "${url}" -OutFile ".\lis-test\WS2012R2\lisa\Bin\${util}"
        if (-not $?)
        {
            Throw "Error: unable do download Putty utility '${util}'"
        }
    }

    #
    # Download the sha256sums file.
    #
    $url = "${puttyBaseUrl}/sha256sums"
    Invoke-WebRequest "${url}" -OutFile ".\lis-test\WS2012R2\lisa\Bin\sha256sums.txt"
    if (-not $?)
    {
        Throw "Error: Unable to download the sha256sums file"
    }

    #
    # Read the sha256sums file and build a dictionary of the sums
    #
    $sumContent = Get-Content ".\lis-test\WS2012R2\lisa\Bin\sha256sums.txt"
    if (-not $?)
    {
        Throw "Error: Unable to read the sha256sums.txt file"
    }

    $sums = @{}
    foreach ($line in $sumContent)
    {
        $fields = $line.Split(" ")
        $sums[ $fields[2].Trim() ] = $fields[0].Trim()
    }

    #
    # Check the sha256sum of each downloaded Putty utility
    #
    foreach ($util in $puttyUtils)
    {
        Write-Host "Info : Verifying sha256sum for ${util}"

        $filesum = Get-FileHash -Algorithm SHA256 -Path ".\lis-test\WS2012R2\lisa\Bin\${util}"
        if ($filesum.Hash -ne $sums[ "w32/${util}" ])
        {
            Throw "Error: sha256sum mismatch for ${util}"
        }
    }
}


#######################################################################
#
# InstallRolesAndFeatures()
#
#######################################################################
function InstallRolesAndFeatures()
{
    $featuresToInstall = @()

    if ($HyperV)
    {
        $hypervFeature = Get-WindowsFeature -Name "Hyper-V"
        if (-not $hypervFeature.Installed)
        {
            $featuresToInstall += "Hyper-V"
        }
        else
        {
            Write-Host -f Yellow "Warning: The 'Hyper-V' role is already installed"
        }
    }

    if ($BackupServer)
    {
        $backupFeature = Get-WindowsFeature -Name "Windows-Server-Backup"
        if (-not $backupFeature.Installed)
        {
            $featuresToInstall += "Windows-Server-Backup"
        }
        else
        {
            Write-Host -f Yellow "Warning: The 'Windows Server Backup' feature is already installed"
        }
    }

    if ($FailoverClustering)
    {
        $clusterFeature = Get-WindowsFeature -Name "Failover-Clustering"
        if (-not $clusterFeature.Installed)
        {
            $featuresToInstall += "Failover-Clustering"
        }
        else
        {
            Write-Host -f Yellow "Warning: The 'Failover Clustering' feature is already installed"
        }
    }

    if ($featuresToInstall.Length -gt 0)
    {
        Write-Host "Info : Installing the folowing feature: '$featuresToInstall'"

        $feature = Install-WindowsFeature -Name $featuresToInstall -IncludeAllSubfeature -IncludeManagementTools
        if (-not $feature.Success)
        {
            Throw "Error: Unable to install the following roles: ${toBeInstall}"
        }

        Write-Host -f Yellow "Info: You need to reboot the server to complete installation of the Role/Feature"
        exit 0
    }
}


#######################################################################
#
# SyncExternalFolder()
#
#######################################################################
function SyncExternalFolder()
{
    if (-not (Test-Path "${ExternalFolderSync}"))
    {
        Throw "Error: The External Folder '${externalFolderSync}' does not exist"
    }

    if (-not ("${externalFolderSync}".EndsWith("\")) -or -not ("${externalFolderSync}".EndsWith("/")) )
    {
        $externalFolderSync += "\"
    }
    $externalFolderSync += "*"

    Write-Host "Info : Syncing ${externalFolderSync} to .\lis-test\WS2012R2\lisa\"

    Copy-Item -Recurse "${externalFolderSync}" ".\lis-test\WS2012R2\lisa\"
    if (-not $?)
    {
        Throw "Error: Unable to sync the lisa folder with '${ExternalFolderSync}'"
    }
}


#######################################################################
#
#
#
#######################################################################
function SetHypervVhdPath()
{
    if (-not (Test-Path "${VhdPath}"))
    {
        Throw "Error: Unable to set VhdPath.  The directory '${VhdPath}' does not exist"
    }

    $sts = Set-VMHost -VirtualHardDiskPath "${VhdPath}"
    if (-not $?)
    {
        Throw "Error: Unable to set VhdPath: $($error[0].Exception.Message)"
    }
}


#######################################################################
#
#
#
#######################################################################
function SetHypervVmPath()
{
    if (-not (Test-Path "${VmPath}"))
    {
        Throw "Error: Unable to set VmPath.  The directory '${VmPath}' does not exist"
    }

    $sts = Set-VMHost -VirtualMachinePath "${VmPath}"
    if (-not $?)
    {
        Throw "Error: Unable to set VmPath: $($error[0].Exception.Message)"
    }
}


#######################################################################
#
# Main script body
#
#######################################################################

try
{
    #
    # Install any roles and features
    #
    InstallRolesAndFeatures

    #
    # Create vSwitches
    #
    if ($vSwitches)
    {
        CreateInternalSwitch
        CreatePrivateSwitches
        CreateExternalSwitch
    }

    #
    # Install a Git client
    #
    if ($Git)
    {
        InstallGitClient
    }

    #
    # Clone the LIS Test repository
    #
    if ($Clone)
    {
        CloneLisTest
    }

    #
    # Install the putty utilities
    #
    if ($Putty)
    {
        InstallPutty
    }

    #
    # Modify the Hyper-V VirtualHardDiskPath
    #
    if ($VhdPath)
    {
        SetHypervVhdPath
    }

    #
    # Modify the Hyper-V VirtualMachinePath
    #
    if ($VmPath)
    {
        SetHypervVmPath
    }

    #
    # Copy the ExternalFolderSync content into the directory
    # lis-test\WS2012R2\lisa
    #
    if ($ExternalFolderSync)
    {
        SyncExternalFolder
    }
}
catch
{
    $msg = $_.Exception.Message
    Write-Host -f Red "Error: Unable to provision the host"
    Write-Host -f Red "${msg}"
    exit 1
}

exit 0
