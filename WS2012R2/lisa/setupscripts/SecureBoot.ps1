##########################################################################
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
##########################################################################

<#
.Synopsis
    This script tests Secure Boot features.

.Description
    This script will test Secure Boot features on a Generation 2 VM.
    It also test the feature after performing a Live Migration of the VM or 
    after a kernel update.

    
    The .xml entry for this script could look like either of the
    following:

    An actual testparams definition may look like the following

        <testparams>
            <param>updateKernel=True</param>
            <param>Migrate=True</param>
            <param>TC_COVERED=SECBOOT-03</param>
        </testparams>

    A typical XML definition for this test case would look similar
    to the following:
        <test>
            <testName>SecureBootBasic</testName>
            <testScript>setupscripts\SecureBoot.ps1</testScript> 
            <testparams>
                <param>updateKernel=True</param>
                <param>Migrate=True</param>
                <param>TC_COVERED=SECBOOT-01</param>
            </testparams>
            <timeout>18000</timeout>
            <OnError>Continue</OnError>
        </test>
        <test>
            <testName>SecureBootLiveMigration</testName>
            <testScript>setupscripts\SecureBoot.ps1</testScript> 
            <testparams>
                <param>Migrate=True</param>
                <param>TC_COVERED=SECBOOT-03</param>
            </testparams>
            <timeout>18000</timeout>
            <OnError>Continue</OnError>
        </test>
        <test>
            <testName>SecureBootUpdateKernel</testName>
            <testScript>setupscripts\SecureBoot.ps1</testScript> 
            <testparams>
                <param>updateKernel=True</param>
                <param>TC_COVERED=SECBOOT-05</param>
            </testparams>
            <timeout>18000</timeout>
            <OnError>Continue</OnError>
        </test>

.Parameter vmName
    Name of the VM to remove disk from .

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\SecureBoot.ps1 -hvServer localhost -vmName NameOfVm -testParams 'sshKey=path/to/ssh;rootdir=path/to/testdir;ipv4=ipaddress;Migrate=True;UpdateKernel=True'

#>

param(
    [String] $vmName,
    [String] $hvServer,
    [String] $testParams
)

$sshKey 	= $null
$ipv4 		= $null
$TC_COVERED = $null
$migrate 	= $False
$updateKernel = $False

#######################################################################
#
# MigrateVM()
#
#######################################################################
function MigrateVM([String] $vmName)
{

    #
    # Load the cluster commandlet module
    #
    $error.Clear()
    $sts = Import-module FailoverClusters
    if ( $error.Count -gt 0 )
    {
        "Error: Unable to load FailoverClusters module"
        $error
        return $False
    }

    #
    # Have migration networks been configured?
    #
    $migrationNetworks = Get-ClusterNetwork
    if (-not $migrationNetworks)
    {
        "Error: $vmName - There are no Live Migration Networks configured"
        return $False
    }

    #
    # Get the VMs current node
    #
    $vmResource =  Get-ClusterResource | where-object {$_.OwnerGroup.name -eq "$vmName" -and $_.ResourceType.Name -eq "Virtual Machine"}
    if (-not $vmResource)
    {
        "Error: $vmName - Unable to find cluster resource for current node"
        return $False
    }

    $currentNode = $vmResource.OwnerNode.Name
    if (-not $currentNode)
    {
        "Error: $vmName - Unable to set currentNode"
        return $False
    }

    #
    # Get nodes the VM can be migrated to
    #
    $clusterNodes = Get-ClusterNode
    if (-not $clusterNodes -and $clusterNodes -isnot [array])
    {
        "Error: $vmName - There is only one cluster node in the cluster."
        return $False
    }

    #
    # For the initial implementation, just pick a node that does not
    # match the current VMs node
    #
    $destinationNode = $clusterNodes[0].Name.ToLower()
    if ($currentNode -eq $clusterNodes[0].Name.ToLower())
    {
        $destinationNode = $clusterNodes[1].Name.ToLower()
    }

    if (-not $destinationNode)
    {
        "Error: $vmName - Unable to set destination node"
        return $False
    }

    "Info : Migrating VM $vmName from $currentNode to $destinationNode"

    $error.Clear()
    $sts = Move-ClusterVirtualMachineRole -name $vmName -node $destinationNode
    if ($error.Count -gt 0)
    {
        "Error: $vmName - Unable to move the VM"
        $error
        return $False
    }

    #
    # Check if Secure Boot is enabled
    #
    $firmwareSettings = Get-VMFirmware -VMName $vm.Name
    if ($firmwareSettings.SecureBoot -ne "On")
    {
        "Error: Secure boot settings changed"
        return $False
    }

    $error.Clear()
    $sts = Move-ClusterVirtualMachineRole -name $vmName -node $currentNode
    if ($error.Count -gt 0)
    {
        "Error: $vmName - Unable to move the VM"
        $error
        return $False
    }

    return $True
}

function UpdateKernel([String]$conIpv4,[String]$sshKey)
{
	$cmdToVM = @"
	
		#!/bin/bash
		
		LinuxRelease()
		{
			DISTRO=`grep -ihs "buntu\|Suse\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux" /etc/{issue,*release,*version}`

			case `$DISTRO in
				*buntu*)
					echo "UBUNTU";;
				Fedora*)
					echo "FEDORA";;
				CentOS*)
					echo "CENTOS";;
				*SUSE*)
					echo "SLES";;
				Red*Hat*)
					echo "RHEL";;
				Debian*)
					echo "DEBIAN";;
				*)
					LogMsg "Unknown Distro"
					UpdateTestState "TestAborted"
					UpdateSummary "Unknown Distro, test aborted"
					exit 1
					;; 
			esac
		}
		
		`$retVal=1
		case `$(LinuxRelease) in
			"SLES")
				zypper --non-interactive install fcoe-utils
				zypper --non-interactive install kernel-default*
				`$retVal=$?
			"UBUNTU")
				
			"RHEL")
				yum -y update kernel
				`$retVal=$?
			*)
				
		esac
		
		exit `$retVal
"@

	$filename="UpdateKernel.sh"
	
	# check for file
	if (Test-Path ".\${filename}")
	{
		Remove-Item ".\${filename}"
	}
	
	Add-Content $filename "$cmdToVM"
	
	# send file
	$retVal = SendFileToVM $conIpv4 $sshKey $filename "/root/${$filename}"
	Remove-Item ".\${filename}"
		
	# check the return Value of SendFileToVM
	if (-not $retVal)
	{
		return $false
	}
	
	# execute command
	$retVal = SendCommandToVM $conIpv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"
	
	return $retVal
}

##########################################################################
#
# Main script body
#
##########################################################################

if (-not $vmName)
{
    "Error: no VMName specified"
    return $False
}

if (-not $hvServer)
{
    "Error: no hvServer specified"
    return $False
}

if (-not $testParams)
{
    "Error: no testParams specified"
    return $False
}

#
# Parse the test parameters
#

$params = $testParams.TrimEnd(";").Split(";")
foreach ($param in $params)
{
    $fields = $param.Split("=")
    $value = $fields[1].Trim()

    switch ($fields[0].Trim())
    {
        "SSHKey"    { $sshKey  = $fields[1].Trim() }
        "ipv4"      { $ipv4    = $fields[1].Trim() }
        "rootDIR"   { $rootDir = $fields[1].Trim() }
        "TC_COVERED"{ $TC_COVERED = $fields[1].Trim() }
        "Migrate"   { $migrate = [System.Convert]::ToBoolean($fields[1].Trim()) }
		"updateKernel"   { $updateKernel = [System.Convert]::ToBoolean($fields[1].Trim()) }
        default     {}  # unknown param - just ignore it
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

# Source the TCUtils.ps1 file
. .\setupscripts\TCUtils.ps1

Write-Output "Covers: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Debug - display the test parameters so they are captured in the log file
#
Write-Output "TestParams : '${testParams}'"

$summaryLog  = "${vmName}_summary.log"
Del $summaryLog -ErrorAction SilentlyContinue


$error.Clear()
$vm = Get-VM -Name $vmName
if ($error.Count -gt 0)
{
    "Error: Unable to get `"${vmName}`" vm"
    $error[0].Exception
    return $False
}

#
# Check heartbeat
#
$heartbeat = Get-VMIntegrationService -VMName $vm.Name -Name "HeartBeat"
if ($heartbeat.Enabled)
{
    Write-Output "$vmName heartbeat detected"
}
else
{
    Write-Error "$vmName heartbeat not detected"
    return $False
}

#
# Test network conectivity
#
$pingObject = New-Object System.Net.NetworkInformation.Ping
if (-not $pingObject)
{
    "Error: Unable to create a ping object"
}

$pingReply = $pingObject.Send($ipv4)
if ($pingReply.Status -ne "Success")
{
    "Error: Cannot ping $vmName . Status = $($pingReply.Status)"
    return $False
}
Write-Output "Ping reply - $($pingReply.Status)"

#
# Test if SSH port is open
#
$portTest = TestPort $ipv4
if (-not $portTest)
{
    "Error: SSH port not available"
    return $False
}
Write-Output "SSH port opened - $portTest"

if ($migrate)
{
    MigrateVM $vm.Name

    #
    # Check if Secure boot settings are in place after migration
    #
    $firmwareSettings = Get-VMFirmware -VMName $vm.Name
    if ($firmwareSettings.SecureBoot -ne "On")
    {
        "Error: Secure boot settings changed"
        return $False
    }

    #
    # Test network connectivity after migration ends
    #
    $pingObject = New-Object System.Net.NetworkInformation.Ping
    if (-not $pingObject)
    {
        "Error: Unable to create a ping object"
    }

    $pingReply = $pingObject.Send($ipv4)
    if ($pingReply.Status -ne "Success")
    {
        "Error: Cannot ping $vmName . Status = $($pingReply.Status)"
        return $False
    }
    Write-Output "Ping reply after migration - $($pingReply.Status)"

}

if ($updateKernel)
{	
	$updateResult = UpdateKernel $ipv4 $sshKey
	
	if (-not $updateResult)
	{
		"Error: UpdateKernel failed"
		return $updateResult
	}
	
	$vm | Stop-VM
	if (-not $?)
	{
	   Write-Output "Error: Unable to Shut Down VM" 
	   return $False
	}
	
	$timeout = 180
	$sts = WaitForVMToStop $vm.Name $hvServer $timeout
	if (-not $sts)
	{
	   Write-output "Error: WaitForVMToStop fail" 
	   return $False
	}
	
	$error.Clear()
	Start-VM -Name $vm.Name -ComputerName $hvServer -ErrorAction SilentlyContinue
	if ($error.Count -gt 0)
	{
		"Error: unable to start the VM"
		$error
		return $False
	}
	
	$sleepPeriod = 60 #seconds
	Start-Sleep -s $sleepPeriod

	#
	# Check heartbeat
	#
	$heartbeat = Get-VMIntegrationService -VMName $vm.Name -Name "HeartBeat"
	if ($heartbeat.Enabled)
	{
		Write-Output "$vmName heartbeat detected"
	}
	else
	{
		Write-Error "$vmName heartbeat not detected"
		return $False
	}

	#
	# Test network connectivity
	#
	$pingObject = New-Object System.Net.NetworkInformation.Ping
	if (-not $pingObject)
	{
		"Error: Unable to create a ping object"
	}

	$pingReply = $pingObject.Send($ipv4)
	if ($pingReply.Status -ne "Success")
	{
		"Error: Cannot ping $vmName . Status = $($pingReply.Status)"
		return $False
	}
	Write-Output "Ping reply - $($pingReply.Status)"

	#
	# Test if SSH port is open
	#
	$portTest = TestPort $ipv4
	if (-not $portTest)
	{
		"Error: SSH port not available"
		return $False
	}
	Write-Output "SSH port opened - $portTest"
}
 
return $True
