#####################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
#####################################################################

<#
.Synopsis
 Run the Network Bridge test.

 Description:
    Use three VMs to test that one of them can act as a bridge for the other two.
    
    The first VM is started by the LIS framework, while the other two will be managed by this script.
    
    The script expects two NIC parameters in the same format as the NET_{ADD|REMOVE|SWITCH}_NIC_MAC.ps1 scripts, each connecting to a different network switch.
	It checks the first VM for these NICs. If these are not present, the test will fail. It checks the second VM for the first NIC and if not found, it will call 
	the NET_ADD_NIC_MAC.ps1 script directly and add it. It checks the third VM for the second NIC, and if not found, will also call the NET_ADD_NIC_MAC.ps1 script
	and add it. If the NICs were added by this script, it will also clean-up after itself, unless the LEAVE_TRAIL param is set to `YES'.
    
    After all VMs are up, the first VM (with the 2 NICs) will add them to a bridge. Afterwards, the second VM will try to ping the third one.
    
    The following testParams are mandatory:
    
    2x   NIC=NIC type, Network Type, Network Name, MAC Address
        
            NIC Type can be one of the following:
                NetworkAdapter
                LegacyNetworkAdapter
            
            Network Type can be one of the following:
                External
                Internal
                Private
            
            Network Name is the name of a existing network.
            
            Only the Network Name parameter is used by this script, but the others are still necessary, in order to have the same 
            parameters as the NET_ADD_NIC_MAC script.
        
            The following is an example of a testParam for removing a NIC
            
                "NIC=NetworkAdapter,Internal,InternalNet,001600112200"
        
        VM2NAME=name_of_second_VM
            this is the name of the second VM. It will not be managed by the LIS framework, but by this script.
		
		VM3NAME=name_of_third_VM
            this is the name of the third VM. It will not be managed by the LIS framework, but by this script.

    The following testParams are optional:
    
		BRIDGE_IP=xx.xx.xx.xx
			xx.xx.xx.xx is a valid IPv4 Address. If not specified, a default value of 10.10.10.1 will be used.
            This will be assigned to VM1's bridge.
		
        STATIC_IP=xx.xx.xx.xx
            xx.xx.xx.xx is a valid IPv4 Address. If not specified, a default value of 10.10.10.2 will be used.
            This will be assigned to VM2's test NIC.

		STATIC_IP2=xx.xx.xx.xx
			xx.xx.xx.xx is a valid IPv4 Address. If not specified, an IP Address from the same subnet as VM2's STATIC_IP
			will be computed (usually the first address != STATIC_IP in the subnet).
		
        NETMASK=yy.yy.yy.yy
            yy.yy.yy.yy is a valid netmask (the subnet to which the tested netAdapters belong). If not specified, a default value of 255.255.255.0 will be used.
        
        LEAVE_TRAIL=yes/no
            if set to yes and the NET_ADD_NIC_MAC.ps1 script was called from within this script for VM2, then it will not be removed
            at the end of the script. Also temporary bash scripts generated during the test will not be deleted.
        
    All test scripts must return a boolean ($true or $false)
    to indicate if the script completed successfully or not.
    
   .Parameter vmName
    Name of the first VM implicated in vlan trunking test .

    .Parameter hvServer
    Name of the Hyper-V server hosting the VM.

    .Parameter testParams
    Test data for this test case

    .Example
    NET_BRIDGE -vmName sles11sp3x64 -hvServer localhost -testParams "NIC=NetworkAdapter,Private,Private,001600112200;NIC=NetworkAdapter,Private,Private2,001600112201;VM2NAME=second_sles11sp3x64;VM3NAME=third_sles11sp3x64"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

Set-PSDebug -Strict

# connect through ssh to $conIPv4, authenticate with $sshKey, get the interfaces in $macAddr array and add them to the bridge
function ConfigureBridge([String]$conIpv4, [String]$sshKey, [String] $bridgeIP, [String] $bridgeNetmask, [String[]]$macAddrs)
{

	for ($i=0; $i -lt $macAddrs.length; $i++)
	{
		# Add delimiter if needed
		if (-not $macAddrs[$i].Contains(":"))
		{
			for ($j=2; $j -lt 16; $j=$j+2)
			{
				$macAddrs[$i] = $MacAddrs[$i].Insert($j,':')
				$j++
			}
		}
	
	}

	$cmdToVM = @"
#!/bin/bash
				cd /root
                if [ -f Utils.sh ]; then
                    sed -i 's/\r//' Utils.sh
                    . Utils.sh
                else
                    exit 1
                fi

				declare -a __bridge_ifaces
				
				# get interfaces with given MAC
				for MacAddr in $macAddrs ; do
                    echo ConfigureBridge: searching for interface with MAC `$MacAddr >> /root/NET_BRIDGE.log 2>&1
					__sys_interface=`$(grep -il `${MacAddr} /sys/class/net/*/address)
					if [ 0 -ne `$? ]; then
						exit 1
					fi
                    echo ConfigureBridge: found path `$__sys_interface >> /root/NET_BRIDGE.log 2>&1
					__sys_interface=`$(basename "`$(dirname "`$__sys_interface")")
					if [ -z "`$__sys_interface" ]; then
						exit 2
					fi

					echo ConfigureBridge: found interface "`$__sys_interface" >> /root/NET_BRIDGE.log 2>&1
					__bridge_ifaces=("`${__bridge_ifaces[@]}" "`$__sys_interface")
				done
				
				echo ConfigureBridge: adding interfaces `${__bridge_ifaces[@]} to bridge br0 >> /root/NET_BRIDGE.log 2>&1
				SetupBridge $bridgeIP $bridgeNetmask `${__bridge_ifaces[@]} >> /root/NET_BRIDGE.log 2>&1
				__retVal=`$?
				echo ConfigureBridge: SetupBridge returned `$__retVal >> /root/NET_BRIDGE.log 2>&1
				exit `$__retVal
"@
    

	$filename = "ConfigureBridge.sh"
	
	# check for file
	if (Test-Path ".\${filename}")
	{
		Remove-Item ".\${filename}"
	}
	
	Add-Content $filename "$cmdToVM"
	
	# send file
	$retVal = SendFileToVM $conIpv4 $sshKey $filename "/root/${$filename}"
	
	# delete file unless the Leave_trail param was set to yes.
	if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
	{
		Remove-Item ".\${filename}"
	}
	
	# check the return Value of SendFileToVM
	if (-not $retVal)
	{
		return $false
	}
	
	# execute sent file
	$retVal = SendCommandToVM $conIpv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"
	
	return $retVal

}

# function which creates an /etc/sysconfig/network-scripts/ifcfg-ethX file for interface ethX
function CreateInterfaceConfig([String]$conIpv4,[String]$sshKey,[String]$MacAddr,[String]$staticIP,[String]$netmask)
{

	# Add delimiter if needed
	if (-not $MacAddr.Contains(":"))
	{
		for ($i=2; $i -lt 16; $i=$i+2)
		{
			$MacAddr = $MacAddr.Insert($i,':')
			$i++
		}
	}
	
	# create command to be sent to VM. This determines the interface based on the MAC Address and calls CreateVlanConfig (from Utils.sh) to create a new vlan interface
	
	$cmdToVM = @"
#!/bin/bash
		cd /root
		if [ -f Utils.sh ]; then
			sed -i 's/\r//' Utils.sh
			. Utils.sh
		else
			exit 1
		fi
		
		# make sure we have synthetic network adapters present
		GetSynthNetInterfaces
		if [ 0 -ne `$? ]; then
			exit 2
		fi
		
		# get the interface with the given MAC address
		__sys_interface=`$(grep -il ${MacAddr} /sys/class/net/*/address)
		if [ 0 -ne `$? ]; then
			exit 3
		fi
		__sys_interface=`$(basename "`$(dirname "`$__sys_interface")")
		if [ -z "`$__sys_interface" ]; then
			exit 4
		fi
		
		echo CreateIfupConfigFile: interface `$__sys_interface >> /root/NET_BRIDGE.log 2>&1
		CreateIfupConfigFile `$__sys_interface static $staticIP $netmask >> /root/NET_BRIDGE.log 2>&1
		__retVal=`$?
		echo CreateIfupConfigFile: returned `$__retVal >> /root/NET_BRIDGE.log 2>&1
		exit `$__retVal
"@
	
	$filename = "CreateInterfaceConfig.sh"
	
	# check for file
	if (Test-Path ".\${filename}")
	{
		Remove-Item ".\${filename}"
	}
	
	Add-Content $filename "$cmdToVM"
	
	# send file
	$retVal = SendFileToVM $conIpv4 $sshKey $filename "/root/${$filename}"
	
	# delete file unless the Leave_trail param was set to yes.
	if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
	{
		Remove-Item ".\${filename}"
	}
	
	# check the return Value of SendFileToVM
	if (-not $retVal)
	{
		return $false
	}
	
	# execute sent file
	$retVal = SendCommandToVM $conIpv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"
	
	return $retVal
}

# connect through ssh to $conIPv4, authenticate with $sshKey, get the interface with MAC of $macAddr and use it to ping $pingTargetIpv4 with $noPackets
function pingVMs([String]$conIpv4,[String]$pingTargetIpv4,[String]$sshKey,[int]$noPackets,[String]$macAddr)
{

	# check the number of Packets to be sent to the VM
	if ($noPackets -lt 0)
	{
		return $false
	}
	
	# Add delimiter if needed
	if (-not $MacAddr.Contains(":"))
	{
		for ($i=2; $i -lt 16; $i=$i+2)
		{
			$MacAddr = $MacAddr.Insert($i,':')
			$i++
		}
	}
	
	$cmdToVM = @"
#!/bin/bash
				
				# get interface with given MAC
				__sys_interface=`$(grep -il ${MacAddr} /sys/class/net/*/address)
				if [ 0 -ne `$? ]; then
					exit 1
				fi
				__sys_interface=`$(basename "`$(dirname "`$__sys_interface")")
				if [ -z "`$__sys_interface" ]; then
					exit 2
				fi
				
				echo PingVMs: pinging $pingTargetIpv4 using interface `$__sys_interface >> /root/NET_BRIDGE.log 2>&1
				# ping the remote host using an easily distinguishable pattern 0xcafed00d`null`vlan`null`tag`null`
				ping -I `$__sys_interface -c $noPackets -p "cafed00d00766c616e0074616700" $pingTargetIpv4 >> /root/NET_BRIDGE.log 2>&1
				__retVal=`$?
				echo PingVMs: ping returned `$__retVal >> /root/NET_BRIDGE.log 2>&1
				exit `$__retVal
"@

	#"pingVMs: sendig command to vm: $cmdToVM"
	$filename = "PingVMs.sh"
	
	# check for file
	if (Test-Path ".\${filename}")
	{
		Remove-Item ".\${filename}"
	}
	
	Add-Content $filename "$cmdToVM"
	
	# send file
	$retVal = SendFileToVM $conIpv4 $sshKey $filename "/root/${$filename}"
	
	# delete file unless the Leave_trail param was set to yes.
	if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
	{
		Remove-Item ".\${filename}"
	}
	
	# check the return Value of SendFileToVM
	if (-not $retVal)
	{
		return $false
	}
	
	# execute command
	$retVal = SendCommandToVM $conIpv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"
	
	return $retVal
}


#######################################################################
#
# Main script body
#
#######################################################################

#
# Check input arguments
#
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

if ($testParams -eq $null)
{
    "Error: testParams is null"
    return $False
}

# Write out test Params
$testParams

# sshKey used to authenticate ssh connection and send commands
$sshKey = $null

# IP Address of first VM
$ipv4 = $null

# IP Address of second VM
$ipv4VM2 = $null

# IP Address of third VM
$ipv4VM3 = $null

# Name of second VM
$vm2Name = $null

# Name of third VM
$vm3Name = $null

# names of the switches to which to connect NICs. Size should be 2
$netAdapterName = @()

# bridge on VM1 IPv4 Address
$bridgeStaticIP = $null

# VM2 static IPv4 Address
$vm2StaticIP = $null

# VM3 static IPv4 Address
$vm3StaticIP = $null

# VM1 array of Mac Addresses for test interfaces
[String[]]$vm1MacAddress = @()

# Netmask used by all three VMs
$netmask = $null

# boolean to leave a trail
$leaveTrail = $null

#Snapshot name
$snapshotParam = $null


# change working directory to root dir
$testParams -match "RootDir=([^;]+)"
if (-not $?)
{
	"Mandatory param RootDir=Path; not found!"
	return $false
}
$rootDir = $Matches[1]

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

# Source NET_UTILS.ps1 for network functions
if (Test-Path ".\setupScripts\NET_UTILS.ps1")
{
    . .\setupScripts\NET_UTILS.ps1
}
else
{
    "Error: Could not find setupScripts\NET_Utils.ps1"
    return $false
}


# iterator for NIC= parameters. Only 2 are taken into consideration
$netAdapterNameIterator = [int]0

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    switch ($fields[0].Trim())
    {
    "VM2NAME" { $vm2Name = $fields[1].Trim() }
	"VM3Name" { $vm3Name = $fields[1].Trim() }
    "SshKey"  { $sshKey  = $fields[1].Trim() }
    "ipv4"    { $ipv4    = $fields[1].Trim() }
	"BRIDGE_IP" { $bridgeStaticIP = $fields[1].Trim() }
    "STATIC_IP" { $vm2StaticIP = $fields[1].Trim() }
	"STATIC_IP2" { $vm3StaticIP = $fields[1].Trim() }
    "NETMASK" { $netmask = $fields[1].Trim() }
    "LEAVE_TRAIL" { $leaveTrail = $fields[1].Trim() }
    "SnapshotName" { $SnapshotName = $fields[1].Trim() }
    "NIC"
    {
		
        $nicArgs = $fields[1].Split(',')
        if ($nicArgs.Length -lt 4)
        {
            "Error: Incorrect number of arguments for NIC test parameter: $p"
            return $false

        }
        
        
        $nicType = $nicArgs[0].Trim()
        $networkType = $nicArgs[1].Trim()
        $netAdapterName = $netAdapterName + $nicArgs[2].Trim()
        $vm1MacAddress = $vm1MacAddress + $nicArgs[3].Trim()
        $legacy = $false
		#
        # Validate the network adapter type
        #
        if ("NetworkAdapter" -notcontains $nicType)
        {
            "Error: Invalid NIC type: $nicType . Must be 'NetworkAdapter'"
            return $false
        }
		
		#
        # Validate the Network type
        #
        if (@("External", "Internal", "Private") -notcontains $networkType)
        {
            "Error: Invalid netowrk type: $networkType .  Network type must be either: External, Internal, Private"
            return $false
        }

        #
        #
        # Make sure the network exists
        #
        $vmSwitch = Get-VMSwitch -Name $netAdapterName[${netAdapterNameIterator}] -ComputerName $hvServer
        if (-not $vmSwitch)
        {
            "Error: Invalid network name: $networkName . The network does not exist."
            return $false
        }
		
        $retVal = isValidMAC $vm1MacAddress[${netAdapterNameIterator}]

        if (-not $retVal)
        {
            "Invalid Mac Address $vm1MacAddress[${netAdapterNameIterator}]"
            return $false
        }
	
        
        #
        # Get Nic with given MAC Address
        #
        $vm1nic = Get-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer -IsLegacy:$false | where {$_.MacAddress -eq $vm1MacAddress[${netAdapterNameIterator}] }
        $vm1macstring = $vm1MacAddress[${netAdapterNameIterator}]
        if ($vm1nic)
        {
            "$vmName found NIC with MAC $vm1macstring."
        }
        else
        {
            "Error: $vmName - No NIC found with MAC $vm1MacAddress[${netAdapterNameIterator}] ."
			return $false
        }
		
		Set-VMNetworkAdapter $vm1nic -MacAddressSpoofing on
		$netAdapterNameIterator = $netAdapterNameIterator + 1
    }
    default   {}  # unknown param - just ignore it
    }
}

if (-not $vm2Name)
{
    "Error: test parameter vm2Name was not specified"
    return $False
}

if (-not $vm2Name)
{
    "Error: test parameter vm3Name was not specified"
    return $False
}

#set the parameter for the snapshot
$snapshotParam = "SnapshotName = ${SnapshotName}"

.\setupScripts\RevertSnapshot.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $snapshotParam
Start-sleep -s 5
.\setupScripts\RevertSnapshot.ps1 -vmName $vm3Name -hvServer $hvServer -testParams $snapshotParam
Start-sleep -s 5


# make sure vm2 is not the same as vm1
if ("$vm2Name" -like "$vmName" -or "$vm2Name" -like "$vm3Name")
{
	"Error: vm2 must be different from the other two VMs."
	return $false
}

if ("$vm3Name" -like "$vmName")
{
	"Error: vm3 must be different from the test VM"
	return $false
}

if (-not $sshKey)
{
    "Error: test parameter sshKey was not specified"
    return $False
}

if (-not $ipv4)
{
    "Error: test parameter ipv4 was not specified"
    return $False
}

# we need only 2 network Switches
if ($netAdapterName.Count -lt 2)
{
	"Error: two NIC parameters are needed."
	return $false
}

#
# Verify the VMs exists
#
$vm1 = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm1)
{
    "Error: VM ${vmName} does not exist"
    return $False
}

$vm2 = Get-VM -Name $vm2Name -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm2)
{
    "Error: VM ${vm2Name} does not exist"
    return $False
}

$vm3 = Get-VM -Name $vm3Name -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm3)
{
    "Error: VM ${vm3Name} does not exist"
    return $False
}

# hold testParam data for NET_ADD_NIC_MAC script for vm2
$vm2testParam = $null
$vm2MacAddress = $null

# hold testParam data for NET_ADD_NIC_MAC script for vm3
$vm3testParam = $null
$vm3MacAddress = $null

# remember if we added the NIC or it was already there.
$scriptAddedNIC = $false

# Check for a NIC of the given network type on VM2
$vm2nic = $null
$vm2switchName = $netAdapterName[0]
$nic2 = Get-VMNetworkAdapter -VMName $vm2Name -ComputerName $hvServer -IsLegacy:$false | where { $_.SwitchName -like "$vm2switchName" }

if ($nic2) 
{
	# check if we received more than one
	if ($nic2 -is [system.array])
	{
		 "Warning: Multiple NICs found in $vm2Name connected to $networkName . Will use the first one."
		$vm2nic = $nic2[0]
	}
	else
	{
		$vm2nic = $nic2
	}
	
	$vm2MacAddress = $vm2nic | select -ExpandProperty MacAddress
	
    $retVal = isValidMAC $vm2MacAddress

    if (-not $retVal)
    {
        "$vm2name : invalid mac $vm2MacAddress"
    }

	# make sure $vm2nic is in untagged mode to begin with
	Set-VMNetworkAdapterVlan -VMNetworkAdapter $vm2Nic -Untagged
}
else
{
	# we need to add it here
    # try a few times
    for ($i = 0; $i -lt 3; $i++)
    {
        $vm2MacAddress = getRandUnusedMAC $hvServer

        if ($vm2MacAddress)
        {
            break
        }
    }

    $retVal = isValidMAC $vm2MacAddress

    if (-not $retVal)
    {
        "$vm2Name MAC $vm2MacAddress is invalid"
        return $false
    }

    $netname = $netAdapterName[0]
    "Going to create a new $networkType netadapter for $vm2Name, attached to $netname with a static MAC of $vm2MacAddress"
	$vm2testParam = "NIC=NetworkAdapter,$networkType,$netname,$vm2MacAddress"
	
	if ( Test-Path ".\setupScripts\NET_ADD_NIC_MAC.ps1")
	{
		# Make sure VM2 is shutdown
		if (Get-VM -Name $vm2Name |  Where { $_.State -like "Running" })
		{
            "Stopping VM2 $vm2Name"
			Stop-VM $vm2Name -force
			
			if (-not $?)
			{
				"Error: Unable to shut $vm2Name down (in order to add a new network Adapter)"
				return $false
			}
			
			# wait for VM to finish shutting down
			$timeout = 60
			while (Get-VM -Name $vm2Name |  Where { $_.State -notlike "Off" })
			{
				if ($timeout -le 0)
				{
					"Error: Unable to shutdown $vm2Name"
					return $false
				}
				
				start-sleep -s 5
				$timeout = $timeout - 5
			}
			
		}
		
		.\setupScripts\NET_ADD_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
	}
	else
	{
		"Error: Could not find setupScripts\NET_ADD_NIC_MAC.ps1 ."
		return $false
	}
	
	if (-Not $?)
	{
		"Error: Cannot add new NIC to $vm2Name"
		return $false
	}
	
	# get the newly added NIC
	$vm2nic = Get-VMNetworkAdapter -VMName $vm2Name -ComputerName $hvServer -IsLegacy:$false | where { $_.MacAddress -like "$vm2MacAddress" }
	
	if (-not $vm2nic)
	{
		"Error: Could not retrieve the newly added NIC to VM2"
		return $false
	}
	
	$scriptAddedNIC = $true
}

# Check for a NIC of the given network type on VM3
$vm3nic = $null
$vm3switchName = $netAdapterName[1]
$nic3 = Get-VMNetworkAdapter -VMName $vm3Name -ComputerName $hvServer -IsLegacy:$false | where { $_.SwitchName -like "$vm3switchName" }

if ($nic3) 
{
	# check if we received more than one
	if ($nic3 -is [system.array])
	{
		"Warning: Multiple NICs found in $vm3Name connected to $netAdapterName[1]. Will use the first one."
		$vm3nic = $nic3[0]
	}
	else
	{
		$vm3nic = $nic3
	}
	
	$vm3MacAddress = $vm3nic | select -ExpandProperty MacAddress
	
    $retVal = isValidMAC $vm3MacAddress
    if (-not $retVal)
    {
        "$vm3name : invalid mac $vm3MacAddress"
    }

	# make sure $vm3nic is in untagged mode to begin with
	Set-VMNetworkAdapterVlan -VMNetworkAdapter $vm3Nic -Untagged
}
else
{
	# we need to add it here
    # try a few times 
    for ($i = 0; $i -lt 3; $i++)
    {

        $vm3MacAddress = getRandUnusedMAC $hvServer

        if ($vm3MacAddress)
        {
            break
        }
    }

    $retVal = isValidMAC $vm3MacAddress

    if (-not $retVal)
    {
        "$vm3Name MAC $vm3MacAddress is not a valid MAC Address"
        # if this script added the second NIC, then remove it unless the Leave_trail param was set.
        if ($scriptAddedNIC)
        {
            if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
            {
                if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
                {
                    .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                }
                else
                {
                    "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
                }
            }
        }
        return $false
    }

	#construct NET_ADD_NIC_MAC Parameter
    $netname = $netAdapterName[1]
    "Going to create a new $networkType netadapter for $vm3Name, attached to $netname with a static MAC of $vm3MacAddress"
	$vm3testParam = "NIC=NetworkAdapter,$networkType,$netname,$vm3MacAddress"
	
	if ( Test-Path ".\setupScripts\NET_ADD_NIC_MAC.ps1")
	{
		# Make sure VM3 is shutdown
		if (Get-VM -Name $vm3Name |  Where { $_.State -like "Running" })
		{
			Stop-VM $vm3Name -force
			
			if (-not $?)
			{
				"Error: Unable to shut $vm3Name down (in order to add a new network Adapter)"
				return $false
			}
			
			# wait for VM to finish shutting down
			$timeout = 60
			while (Get-VM -Name $vm3Name |  Where { $_.State -notlike "Off" })
			{
				if ($timeout -le 0)
				{
					"Error: Unable to shutdown $vm3Name"
					return $false
				}
				
				start-sleep -s 5
				$timeout = $timeout - 5
			}
			
		}
		.\setupScripts\NET_ADD_NIC_MAC.ps1 -vmName $vm3Name -hvServer $hvServer -testParams $vm3testParam
	}
	else
	{
		"Error: Could not find setupScripts\NET_ADD_NIC_MAC.ps1 ."
        # if this script added the second NIC, then remove it unless the Leave_trail param was set.
        if ($scriptAddedNIC)
        {
            if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
            {
                if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
                {
                    .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                }
                else
                {
                    "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
                }
            }
        }
		return $false
	}
	
	if (-Not $?)
	{
		"Error: Cannot add new NIC to $vm3Name"
        # if this script added the second NIC, then remove it unless the Leave_trail param was set.
        if ($scriptAddedNIC)
        {
            if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
            {
                if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
                {
                    .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                }
                else
                {
                    "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
                }
            }
        }
		return $false
	}
	
	# get the newly added NIC
	$vm3nic = Get-VMNetworkAdapter -VMName $vm3Name -ComputerName $hvServer -IsLegacy:$false | where { $_.MacAddress -like "$vm3MacAddress" }
	
	if (-not $vm3nic)
	{
		"Error: Could not retrieve the newly added NIC to VM3"
        # if this script added the second NIC, then remove it unless the Leave_trail param was set.
        if ($scriptAddedNIC)
        {
            if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
            {
                if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
                {
                    .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                }
                else
                {
                    "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
                }
            }
        }
		return $false
	}
	
	$scriptAddedNIC = $true
}

"Tests Bridge test"

if (-not $netmask)
{
    $netmask = "255.255.255.0"
}

if (-not $bridgeStaticIP)
{
    $bridgeStaticIP = getAddress "10.10.10.10" $netmask 1
}

if (-not $vm2StaticIP)
{
    [int]$nth = 2
    do
    {
        $vm2StaticIP = getAddress $bridgeStaticIP $netmask $nth
        $nth += 1
    } while ($vm2StaticIP -like $bridgeStaticIP)
}
else
{
    # make sure $vm3StaticIP is in the same subnet as $vm2StaticIP
    $retVal = containsAddress $bridgeStaticIP $netmask $vm2StaticIP 
    
    if (-not $retVal)
    {
        "$vm2StaticIP is not in the same subnet as $bridgeStaticIP $netmask"
        # if this script added the second NIC, then remove it unless the Leave_trail param was set.
        if ($scriptAddedNIC)
        {
            if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
            {
                if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
                {
                    .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                    .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm3Name -hvServer $hvServer -testParams $vm3testParam
                }
                else
                {
                    "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
                }
            }
        }

        return $false
    }
}



# compute another ipv4 address for vm3
if (-not $vm3StaticIP)
{
	[int]$nth = 2
    do
    {
        $vm3StaticIP = getAddress $vm2StaticIP $netmask $nth
        $nth += 1
    } while ($vm3StaticIP -like $vm2StaticIP -or $vm3StaticIP -like $bridgeStaticIP)
	
}
else
{
	# make sure $vm3StaticIP is in the same subnet as $vm2StaticIP
	$retVal = containsAddress $vm2StaticIP $netmask $vm3StaticIP 
	
	if (-not $retVal)
	{
		"$vm3StaticIP is not in the same subnet as $vm2StaticIP $netmask"
        # if this script added the second NIC, then remove it unless the Leave_trail param was set.
        if ($scriptAddedNIC)
        {
            if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
            {
                if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
                {
                    .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                    .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm3Name -hvServer $hvServer -testParams $vm3testParam
                }
                else
                {
                    "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
                }
            }
        }

		return $false
	}
}

"sshKey   = ${sshKey}"
"vm1 Name = ${vmName}"
"vm1 ipv4 = ${ipv4}"
$VM1firstMac = $vm1MacAddress[0]
"vm1 first MAC = $VM1firstMac"
$VM1secondMac = $vm1MacAddress[1]
"vm1 second MAC = $VM1secondMac"
"vm1 bridge IP = ${bridgeStaticIP}"
"vm1 bridge netmask = $netmask"

#
# LIS Started VM1, so start VM2
#

if (Get-VM -Name $vm2Name |  Where { $_.State -notlike "Running" })
{
	Start-VM -Name $vm2Name -ComputerName $hvServer
	if (-not $?)
	{
		"Error: Unable to start VM ${vm2Name}"
		$error[0].Exception
        # if this script added the second NIC, then remove it unless the Leave_trail param was set.
        if ($scriptAddedNIC)
        {
            if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
            {
                if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
                {
                    .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                    .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm3Name -hvServer $hvServer -testParams $vm3testParam
                }
                else
                {
                    "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
                }
            }
        }

		return $False
	}
}

$timeout = 60 # seconds
if (-not (WaitForVMToStartKVP $vm2Name $hvServer $timeout))
{
    "Warning: $vm2Name never started KVP"
}

# get vm2 ipv4

$vm2ipv4 = GetIPv4 $vm2Name $hvServer

"vm2 Name = ${vm2Name}"
"vm2 ipv4 = ${vm2ipv4}"
"vm2 MAC = ${vm2MacAddress}"
"vm2 static IP = ${vm2StaticIP}"
	
# wait for ssh to startg
$timeout = 120 #seconds
if (-not (WaitForVMToStartSSH $vm2ipv4 $timeout))
{
    "Error: VM ${vm2Name} never started"

    Stop-VM -VMName $vm2name -force
    # if this script added the second NIC, then remove it unless the Leave_trail param was set.
    if ($scriptAddedNIC)
    {
        if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
        {
            if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
            {
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm3Name -hvServer $hvServer -testParams $vm3testParam
            }
            else
            {
                "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
            }
        }
    }

    return $False
}

# send Utils.sh to VM2
if (-not (Test-Path ".\remote-scripts\ica\Utils.sh"))
{
	"Error: Unable to find remote-scripts\ica\Utils.sh "
    Stop-VM -VMName $vm2name -force
    # if this script added the second NIC, then remove it unless the Leave_trail param was set.
    if ($scriptAddedNIC)
    {
        if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
        {
            if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
            {
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm3Name -hvServer $hvServer -testParams $vm3testParam
            }
            else
            {
                "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
            }
        }
    }

	return $false
}

"Sending .\remote-scripts\ica\Utils.sh to $vm2ipv4 , authenticating with $sshKey"
$retVal = SendFileToVM "$vm2ipv4" "$sshKey" ".\remote-scripts\ica\Utils.sh" "/root/Utils.sh"

if (-not $retVal)
{
	"Failed sending file to VM!"
    Stop-VM -VMName $vm2name -force
    # if this script added the second NIC, then remove it unless the Leave_trail param was set.
    if ($scriptAddedNIC)
    {
        if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
        {
            if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
            {
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm3Name -hvServer $hvServer -testParams $vm3testParam
            }
            else
            {
                "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
            }
        }
    }

	return $False
}

"Successfully sent Utils.sh"

#
# LIS Started VM1, we need to start VM3
#

if (Get-VM -Name $vm3Name |  Where { $_.State -notlike "Running" })
{
	Start-VM -Name $vm3Name -ComputerName $hvServer
	if (-not $?)
	{
		"Error: Unable to start VM ${vm3Name}"
		$error[0].Exception
        Stop-VM -VMName $vm2name -force
        # if this script added the second NIC, then remove it unless the Leave_trail param was set.
        if ($scriptAddedNIC)
        {
            if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
            {
                if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
                {
                    .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                    .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm3Name -hvServer $hvServer -testParams $vm3testParam
                }
                else
                {
                    "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
                }
            }
        }

		return $False
	}
}

$timeout = 60 # seconds
if (-not (WaitForVMToStartKVP $vm3Name $hvServer $timeout))
{
    "Warning: $vm3Name never started KVP"
}

# get vm3 ipv4

$vm3ipv4 = GetIPv4 $vm3Name $hvServer

"vm3 Name = ${vm3Name}"
"vm3 ipv4 = ${vm3ipv4}"
"vm3 MAC = ${vm3MacAddress}"
"vm3 static IP = ${vm3StaticIP}"
	
# wait for ssh to start
$timeout = 120 #seconds
if (-not (WaitForVMToStartSSH $vm3ipv4 $timeout))
{
    "Error: VM ${vm3Name} never started"
    Stop-VM -VMName $vm2name -force
    Stop-VM -vmName $vm3Name -force
    # if this script added the second NIC, then remove it unless the Leave_trail param was set.
    if ($scriptAddedNIC)
    {
        if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
        {
            if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
            {
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm3Name -hvServer $hvServer -testParams $vm3testParam
            }
            else
            {
                "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
            }
        }
    }

    return $False
}

# send Utils.sh to VM3

"Sending .\remote-scripts\ica\Utils.sh to $vm3ipv4 , authenticating with $sshKey"
$retVal = SendFileToVM "$vm3ipv4" "$sshKey" ".\remote-scripts\ica\Utils.sh" "/root/Utils.sh"

if (-not $retVal)
{
	"Failed sending file to VM!"
    Stop-VM -VMName $vm2name -force
    Stop-VM -vmName $vm3Name -force
    # if this script added the second NIC, then remove it unless the Leave_trail param was set.
    if ($scriptAddedNIC)
    {
        if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
        {
            if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
            {
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm3Name -hvServer $hvServer -testParams $vm3testParam
            }
            else
            {
                "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
            }
        }
    }

	return $False
}

"Successfully sent Utils.sh"

"Configuring bridge on $vmName (${ipv4})"
# configure bridge on test-vm
$retVal = ConfigureBridge $ipv4 $sshKey $bridgeStaticIP $netmask $vm1MacAddress
if (-not $retVal)
{
	"Failed to create Bridge on vm $ipv4  with interfaces with MACs $vm1MacAddress, by setting a static IP of $bridgeStaticIP netmask $netmask"
    Stop-VM -VMName $vm2name -force
    Stop-VM -vmName $vm3Name -force
    # if this script added the second NIC, then remove it unless the Leave_trail param was set.
    if ($scriptAddedNIC)
    {
        if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
        {
            if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
            {
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm3Name -hvServer $hvServer -testParams $vm3testParam
            }
            else
            {
                "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
            }
        }
    }

	return $false
}

"Successfully configured bridge"

"Configuring test interface (${vm2MacAddress}) on $vm2Name (${vm2ipv4}) with $vm2StaticIP netmask $netmask"
$retVal = CreateInterfaceConfig $vm2ipv4 $sshKey $vm2MacAddress $vm2StaticIP $netmask
if (-not $retVal)
{
	"Failed to create Interface Config on vm $vm2ipv4 for interface with mac $vm2MacAddress , by setting a static IP of $vm2StaticIP netmask $netmask"
    Stop-VM -VMName $vm2name -force
    Stop-VM -vmName $vm3Name -force
    # if this script added the second NIC, then remove it unless the Leave_trail param was set.
    if ($scriptAddedNIC)
    {
        if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
        {
            if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
            {
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm3Name -hvServer $hvServer -testParams $vm3testParam
            }
            else
            {
                "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
            }
        }
    }

	return $false
}

"Successfully configured"

"Configuring test interface (${vm3MacAddress}) on $vm3Name (${vm3ipv4}) with $vm3StaticIP netmask $netmask"
$retVal = CreateInterfaceConfig $vm3ipv4 $sshKey $vm3MacAddress $vm3StaticIP $netmask
if (-not $retVal)
{
	"Failed to create Interface Config on vm $vm3ipv4 for interface with mac $vm3MacAddress , by setting a static IP of $vm3StaticIP netmask $netmask"
    Stop-VM -VMName $vm2name -force
    Stop-VM -vmName $vm3Name -force
    # if this script added the second NIC, then remove it unless the Leave_trail param was set.
    if ($scriptAddedNIC)
    {
        if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
        {
            if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
            {
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm3Name -hvServer $hvServer -testParams $vm3testParam
            }
            else
            {
                "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
            }
        }
    }

	return $false
}
"Successfully configured"

# Try to ping from vm2 to vm3
"Trying to ping from vm2 with mac $vm2MacAddress to $vm3StaticIP "
# try to ping
$retVal = pingVMs $vm2ipv4 $vm3StaticIP $sshKey 10 $vm2MacAddress

if (-not $retVal)
{
	"Unable to ping $vm3StaticIP from $vm2StaticIP with MAC $vm2MacAddress"
    Stop-VM -VMName $vm2name -force
    Stop-VM -vmName $vm3Name -force
    # if this script added the second NIC, then remove it unless the Leave_trail param was set.
    if ($scriptAddedNIC)
    {
        if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
        {
            if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
            {
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm3Name -hvServer $hvServer -testParams $vm3testParam
            }
            else
            {
                "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
            }
        }
    }

	return $false
}

"Successfully pinged"

"Trying to ping from vm3 with mac $vm2MacAddress to $vm2StaticIP "
$retVal = pingVMs $vm3ipv4 $vm2StaticIP $sshKey 10 $vm3MacAddress

if (-not $retVal)
{
	"Unable to ping $vm2StaticIP from $vm3StaticIP with MAC $vm3MacAddress"
    Stop-VM -VMName $vm2name -force
    Stop-VM -vmName $vm3Name -force
    # if this script added the second NIC, then remove it unless the Leave_trail param was set.
    if ($scriptAddedNIC)
    {
        if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
        {
            if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
            {
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
                .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm3Name -hvServer $hvServer -testParams $vm3testParam
            }
            else
            {
                "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
            }
        }
    }

	return $false
}

"Stopping $vm2Name"
Stop-VM -VMName $vm2name -force
"Stopping $vm3Name"
Stop-VM -vmName $vm3Name -force
# if this script added the second NIC, then remove it unless the Leave_trail param was set.
if ($scriptAddedNIC)
{
    if ([string]::Compare($leaveTrail, "yes", $true) -ne 0)
    {
        if (Test-Path ".\setupScripts\NET_REMOVE_NIC_MAC.ps1")
        {
            .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm2Name -hvServer $hvServer -testParams $vm2testParam
            .\setupScripts\NET_REMOVE_NIC_MAC.ps1 -vmName $vm3Name -hvServer $hvServer -testParams $vm3testParam
        }
        else
        {
            "Warning: Unable to find setupScripts\NET_REMOVE_NIC_MAC.ps1 in order to remove the added NIC"
        }
    }
}


"Test successful!"

return $true