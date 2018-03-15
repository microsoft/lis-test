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
    Verify the KVP read operations work for a large number of entries.

.Description
    Ensure the Data Exchange service is enabled for the VM, add 
    a number of KVP entries, using the KVP client, and read them
    from the host.

    A typical test case definition for this test script would look
    similar to the following:
        <test>
            <testName>KVP_Max_Read</testName>
            <testScript>SetupScripts\Kvp_Max_Read.ps1</testScript>
            <files>tools/KVP/kvp_client64</files>
            <timeout>600</timeout>
            <onError>Continue</onError>
            <noReboot>True</noReboot>
            <testparams>
                <param>rootDir=C:\lisa</param>
                <param>TC_COVERED=KVP-01</param>
                <param>Pool=1</param>
                <param>Entries=150</param>
            </testparams>
        </test>
.Parameter vmName
    Name of the VM to read intrinsic data from.
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
.Parameter testParams
    Test data for this test case.
.Example
    setupScripts\Kvp_Max_Read.ps1 -vmName "myVm" -hvServer "localhost -TestParams "rootDir=c:\lisa;TC_COVERED=KVP-01"
.Link
    None.
#>

param([String] $vmName, [String] $hvServer, [String] $testParams)


function AddKVPEntries([String]$ipv4, [String]$sshKey, [String]$rootDir, [String]$pool, [String]$entries)
{
    $cmdToVM = @"
    #!/bin/bash
    ps aux | grep "[k]vp"
    if [ `$? -ne 0 ]; then
      echo "KVP is disabled" >> /root/KVP.log 2>&1
      exit 1
    fi

    #
    # Verify OS architecture
    #
    uname -a | grep x86_64
    if [ `$? -eq 0 ]; then
        echo "64 bit architecture was detected"
        kvp_client="kvp_client64"
    else
        uname -a | grep i686
        if [ `$? -eq 0 ]; then
            echo "32 bit architecture was detected"
            kvp_client="kvp_client32" 
        else
            echo "Error: Unable to detect OS architecture" >> /root/KVP.log 2>&1
            exit 60
        fi
    fi

    value="value"
    counter=0
    key="test"
    while [ `$counter -le $entries ]; do
        ./`${kvp_client} append $pool "`${key}`${counter}" "`${value}"
        let counter=counter+1
    done

    if [ `$? -ne 0 ]; then
        echo "Failed to append new entries" >> /root/KVP.log 2>&1
        exit 100
    fi

    ps aux | grep "[k]vp"
    if [ `$? -ne 0 ]; then
        echo "KVP daemon failed after append" >> /root/KVP.log 2>&1
        exit 100
    fi

"@
    $filename = "AddKVPEntries.sh"

    # check for file
    if (Test-Path ".\${filename}")
    {
      Remove-Item ".\${filename}"
    }

    Add-Content $filename "$cmdToVM"

    # send file
    $retVal = SendFileToVM $ipv4 $sshKey $filename "/root/${filename}"

    # check the return Value of SendFileToVM
    if (-not $retVal[-1])
    {
      return $false
    }

    # execute command as job
    $retVal = SendCommandToVM $ipv4 $sshKey "cd /root && chmod +x kvp_client* && chmod u+x ${filename} && dos2unix ${filename} && ./${filename}"
    return $retVal
}
#######################################################################
#
# Main script body
#
#######################################################################
#
# Make sure the required arguments were passed
#
if (-not $vmName)
{
    "Error: no VMName was specified"
    return $False
}

if (-not $hvServer)
{
    "Error: No hvServer was specified"
    return $False
}

if (-not $testParams)
{
    "Error: No test parameters specified"
    return $False
}

#
# Parse the test parameters
#
$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {      
    "nonintrinsic" { $intrinsic = $False }
    "rootdir"      { $rootDir   = $fields[1].Trim() }
    "TC_COVERED"   { $tcCovered = $fields[1].Trim() }
    "Pool"         { $pool = $fields[1].Trim() }
    "Entries"      { $entries = $fields[1].Trim() }
    "sshKey"       { $sshKey = $fields[1].Trim() }
    "ipv4"         { $ipv4 = $fields[1].Trim() }
    default  {}       
    }
}

if (-not $rootDir)
{
    "Warn : no rootdir was specified"
}
else
{
    cd $rootDir
}

# Source TCUtils.ps1 for common functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
	. .\setupScripts\TCUtils.ps1
	"Info: Sourced TCUtils.ps1"
}
else {
	"Error: Could not find setupScripts\TCUtils.ps1"
	return $false
}

$logger = [LoggerManager]::GetLoggerManager($vmName, $testParams)
$logger.Summary.info("Covers: ${tcCovered}")

# Supported in RHEL7.5 ( no official release for now, might need update )
$FeatureSupported = GetVMFeatureSupportStatus $ipv4 $sshKey "3.10.0-860"
if ( $FeatureSupported -ne $True ){
    $logger.Summary.info("Kernels older than 3.10.0-514 require LIS-4.x drivers.")
    $checkExternal = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "rpm -qa | grep kmod-microsoft-hyper-v && rpm -qa | grep microsoft-hyper-v"
    if ($? -ne "True") {
        $logger.Summary.info("Error: No LIS-4.x drivers detected. Skipping test.")
        return $Skipped
    }
}

#
# Verify the Data Exchange Service is enabled for this VM
#
$des = Get-VMIntegrationService -vmname $vmName -ComputerName $hvServer
if (-not $des)
{
    $logger.Summary.error("Unable to retrieve Integration Service status from VM '${vmName}'")
    return $False
}

$serviceEnabled = $False
foreach ($svc in $des)
{
    if ($svc.Name -eq "Key-Value Pair Exchange")
    {
        $serviceEnabled = $svc.Enabled
        break
    }
}

if (-not $serviceEnabled)
{
    $logger.Summary.error("The Data Exchange Service is not enabled for VM '${vmName}'")
    return $False
}

$retVal = AddKVPEntries $ipv4 $sshKey $rootDir $pool $entries
if (-not $retVal)
{
    $logger.Summary.error("Failed to add new KVP entries on VM")
    return $False
}

#
# Create a data exchange object and collect KVP data from the VM
#
$Vm = Get-WmiObject -ComputerName $hvServer -Namespace root\virtualization\v2 -Query "Select * From Msvm_ComputerSystem Where ElementName=`'$vmName`'"
if (-not $Vm)
{
    $logger.Summary.error("Unable to the VM '${vmName}' on the local host")
    return $False
}

$Kvp = Get-WmiObject -ComputerName $hvServer -Namespace root\virtualization\v2 -Query "Associators of {$Vm} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent"
if (-not $Kvp)
{
    $logger.Summary.error("Unable to retrieve KVP Exchange object for VM '${vmName}'")
    return $False
}
SendCommandToVM $ipv4 $sshKey "ps aux | grep [k]vp > /root/ps.output"
$retVal = SendCommandToVM $ipv4 $sshKey "ps aux | grep [k]vp"
if (-not $retVal) {
    $logger.Summary.error("KVP daemon crashed durring read process")
    return $False
}

return $True
