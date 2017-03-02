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
    Install an OS over PXE

.Description
    On CentOS, RHEL and SLES: In the PXE Server VM is mounted an ISO. This will be 
    copied in the http server folder and will be available to a second vm. 
    For Ubuntu: Netboot and installation files will be downloaded from 
    the public repository. 
    
    After that, the client vm is started and automatic pxe install will 
    be initiated.

    The script will pass if it can get a HeartBeat and SQM data from PXE CLIENT
    during the install or after installing the OS (depending on the testcase).  

.Parameter vmName
    Name of the PXE Server VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParam
    Semicolon separated list of test parameters.

.Example
    .\pxe_install.ps1 "testVM" "localhost" "isoFilename=test.iso; VM2NAME= ;generation= 
    distro= ; willInstall= ; VCPU= ; sshkey= ; ipv4= ; rootDir= ; TC_COVERED= "
#>

param ([String] $vmName, [String] $hvServer, [String] $testParams)
$retVal = $False
$isoFilename = $null
$remoteScript = "pxe_install.sh"

#######################################################################
# CheckVM
#######################################################################
function CheckVM()
{
    # Verify Heartbeat
    $vm = Get-VM $vm2Name -ComputerName $hvServer 
    $hb = Get-VMIntegrationService -VMName $vm2Name -ComputerName $hvServer -Name "Heartbeat"
    if ($($hb.Enabled) -eq "True" -And $($vm.Heartbeat) -eq "OkApplicationsUnknown")
    {
        "Heartbeat detected"
    }
    else
    {
        "Test Failed: VM heartbeat not detected!"
        Write-Output "Heartbeat not detected while the Heartbeat service is enabled" | Out-File -Append $summaryLog
        return $False
    }

    # Verify SQM data
    $Vm = Get-WmiObject -Namespace root\virtualization\v2 -ComputerName $hvServer -Query "Select * From Msvm_ComputerSystem Where ElementName=`'$VM2Name`'"
    if (-not $Vm)
    {
        "Error: Unable to the VM '${VM2Name}' on the local host"
        return $False
    }

    $Kvp = Get-WmiObject -Namespace root\virtualization\v2 -ComputerName $hvServer -Query "Associators of {$Vm} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent"
    if (-not $Kvp)
    {
        "Error: Unable to retrieve KVP Exchange object for VM '${vm2Name}'"
        return $False
    }

    if ($Intrinsic)
    {
        "Intrinsic Data"
        $kvpData = $Kvp.GuestIntrinsicExchangeItems
    }
    else
    {
        "Non-Intrinsic Data"
        $kvpData = $Kvp.GuestExchangeItems
    }

    $dict = KvpToDict $kvpData
    #
    # Write out the kvp data so it appears in the log file
    #
    foreach ($key in $dict.Keys)
    {
        $value = $dict[$key]
        Write-Output ("  {0,-27} : {1}" -f $key, $value)
    }

    if ($Intrinsic)
    {
        $osInfo = GWMI Win32_OperatingSystem -ComputerName $hvServer
        if (-not $osInfo)
        {
            "Error: Unable to collect Operating System information"
            return $False
        }
        #
        #Create an array of key names 
        #
        $osSpecificKeyNames = @("OSDistributionName", "OSDistributionData", "OSPlatformId","OSKernelVersion")
        foreach ($key in $osSpecificKeyNames)
        {
            if (-not $dict.ContainsKey($key))
            {
                "Error: The key '${key}' does not exist"
                return $False
                break
            }
        }
    }
    else #Non-Intrinsic
    {
        if ($dict.length -gt 0)
        {
            "Info: $($dict.length) non-intrinsic KVP items found"
        }
        else
        {
            "Error: No non-intrinsic KVP items found"
            return $False
        }
    }   
}
#######################################################################
#
# Main script body
#
#######################################################################
# Check arguments
if (-not $vmName)
{
    "Error: Missing vmName argument"
    return $False
}

if (-not $hvServer)
{
    "Error: Missing hvServer argument"
    return $False
}

if (-not $testParams)
{
    "Error: Missing testParams argument"
    return $False
}

#
# Extract the testParams we are concerned with
#
$params = $testParams.Split(';')
foreach ($p in $params)
{
    $fields = $p.Split("=")

    switch ($fields[0].Trim())
    {
    "VM2NAME"      { $vm2Name = $fields[1].Trim() }
    "IsoFilename"  { $IsoFilename = $fields[1].Trim() }
    "generation"   { $generation = $fields[1].Trim() }
    "distro"       { $distro = $fields[1].Trim() }
    "willInstall"  { $willInstall = $fields[1].Trim() }
    "VCPU"         { $vcpu = $fields[1].Trim() }
    "SshKey"       { $sshKey  = $fields[1].Trim() }
    "ipv4"         { $ipv4    = $fields[1].Trim() }
    "RootDir"      { $rootDir  = $fields[1].Trim() }
    "TC_COVERED"   { $TC_COVERED = $fields[1].Trim() }
    default   {}  # unknown param - just ignore it
    }
}

"This script covers test case: ${TC_COVERED}"

#
# Checking the mandatory testParams. New parameters must be validated here.
#
if (-not $isoFilename -and $distro -ne "ubuntu")
{
    "Error: Test parameters is missing the IsoFilename parameter"
    return $False
}

if (Test-Path $rootDir)
{
  Set-Location -Path $rootDir
  if (-not $?)
  {
    "Error: Could not change directory to $rootDir !"
    return $false
  }
  "Changed working directory to $rootDir"
}
else
{
  "Error: RootDir = $rootDir is not a valid path"
  return $false
}

# Source TCUitls.ps1 for getipv4 and other functions
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
# Make sure the DVD drive exists on the VM
#
$dvd = Get-VMDvdDrive $vmName -ComputerName $hvServer -ControllerLocation 1 -ControllerNumber 0
if ($dvd)
{
    Remove-VMDvdDrive $dvd -Confirm:$False
    if($? -ne "True")
    {
        "Error: Cannot remove DVD drive from ${vmName}"
        $error[0].Exception
        return $False
    }
}

#
# Make sure the .iso file exists on the HyperV server
#
if (-not ([System.IO.Path]::IsPathRooted($isoFilename)))
{
    $obj = Get-WmiObject -ComputerName $hvServer -Namespace "root\virtualization\v2" -Class "MsVM_VirtualSystemManagementServiceSettingData"
        
    $defaultVhdPath = $obj.DefaultVirtualHardDiskPath
    
    if (-not $defaultVhdPath)
    {
        "Error: Unable to determine VhdDefaultPath on HyperV server ${hvServer}"
        $error[0].Exception
        return $False
    }
   
    if (-not $defaultVhdPath.EndsWith("\"))
    {
        $defaultVhdPath += "\"
    }
  
    $isoFilename = $defaultVhdPath + $isoFilename
   
}   

$isoFileInfo = GetRemoteFileInfo $isoFilename $hvServer
if (-not $isoFileInfo -and $distro -ne "ubuntu")
{
    "Error: The .iso file $isoFilename does not exist on HyperV server ${hvServer}"
    return $False
}

#
# Insert the .iso file into the VMs DVD drive
#
if ($isoFilename -and $distro -ne "ubuntu"){
    Set-VMDvdDrive -VMName $vmName -Path $isoFilename -ControllerNumber 1 -ControllerLocation 0 -ComputerName $hvServer -Confirm:$False
}
if ($? -ne "True")
{
    "Error: Unable to mount"
    $error[0].Exception
    return $False
}

#
# Run pxe_install.sh on VM1: This will copy the contents of iso file and setup the tftp server
#
$sts = RunRemoteScript $remoteScript
if (-not $sts[-1])
{
    Write-Output "ERROR executing $remoteScript on VM. Exiting test case!" >> $summaryLog
    Write-Output "ERROR: Running $remoteScript script failed on VM!"
    Write-Output "Here are the remote logs:`n`n###################"
    $logfilename = ".\$remoteScript.log"
    Get-Content $logfilename
    Write-Output "###################`n"
    return $False
}
Write-Output "$remoteScript execution on VM: Success"
Write-Output "Here are the remote logs:`n`n###################"
$logfilename = ".\$remoteScript.log"
Get-Content $logfilename
Write-Output "###################`n"
Write-Output "$remoteScript execution on VM: Success"

#
# Upload the necessary configuration files if needed
#
if ($willInstall -eq "yes"){
    $configFileName = $null
    if ($generation -eq 1){
        if ($distro -eq "ubuntu"){
            $configFileName = "ubuntu.seed"
        }
        if ($distro -eq "rhel" -Or $distro -eq "centos"){
            $configFileName = "ks.cfg"
        }
        if ($distro -eq "sles"){
            $configFileName = "autoinstGen1.xml"
        }
    }

    if ($generation -eq 2){
        if ($distro -eq "ubuntu"){
            $configFileName = "ubuntuGen2.seed"
        }
        if ($distro -eq "rhel" -Or $distro -eq "centos"){
            $configFileName = "ks.cfg"
        }
        if ($distro -eq "sles"){
            $configFileName = "autoinstGen2.xml"           
        }
    }

    echo y | .\bin\pscp -i ssh\${sshKey} .\Infrastructure\PXE\${configFileName} root@${ipv4}:"/var/www/PXE/"
}



# Run the routing script - this will redirect traffic from the private nic to External
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix routingScript.sh  2> /dev/null"
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod 775 routingScript.sh  2> /dev/null"
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "./routingScript.sh 2> /dev/null"

#
# Start VM2 & check it
#

# Make sure startup order is good
if ($generation -eq 1){
    Get-VM -Name $vm2Name -ComputerName $hvServer | Set-VMBios -StartupOrder @("IDE","LegacyNetworkAdapter","CD","Floppy") 
}

# First, make a snapshot for later use
# This is necessary for running all PXE suite at once
$snapshotInfo = Get-VMSnapshot -VMName $vm2Name -ComputerName $hvServer
if (-not $snapshotInfo.Name){
    Checkpoint-VM -Name $vm2Name -ComputerName $hvServer -SnapshotName "cleanVM"    
}
else {
    Restore-VMSnapshot -VMName $vm2Name -ComputerName $hvServer -Name "cleanVM" -Confirm:$false   
}

# Change vcpu number to the given value
if ($vcpu){
    $cpu = Set-VM -Name $vm2Name -ComputerName $hvServer -ProcessorCount $vcpu

    if ($? -eq "True")
    {
        Write-output "CPU count updated to $vcpu"
        $retVal = $true
    }
    else
    {
        return $retVal
        write-host "Error: Unable to update CPU count"
    }
}

Start-VM -Name $vm2Name -ComputerName $hvServer
Start-Sleep -s 140
$isInstalled = $False


if ($willInstall -eq "no"){
    # Check vm for Heartbeat & SQM data.
    CheckVM
}
else {
    # Wait for OS to install: Check every 5 seconds
    # We check the uptime - if it decreases it means vm has rebooted
    while ($isInstalled -eq $False){
        Start-Sleep -s 5
        $vm = Get-VM -Name $vm2Name -ComputerName $hvServer

        if ($vm.Uptime.Minutes -lt 2){
            $isInstalled = $True
            Stop-VM -Name $vm2Name -ComputerName $hvServer -Force -TurnOff
        }
    }

    Start-VM -Name $vm2Name -ComputerName $hvServer 
    Start-Sleep -s 80

    # Check vm for Heartbeat & SQM data.
    CheckVM 
    Write-output "OS was successfully installed"
}  

# Stop PXE Client after everything was checked
Stop-VM -Name $vm2Name -ComputerName $hvServer -Force -TurnOff  
return $True