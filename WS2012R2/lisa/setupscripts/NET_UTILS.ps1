################################################################################
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
################################################################################

# Network convenience functions

# checks if MAC is valid. Delimiter can be : - or nothing
function isValidMAC([String]$macAddr)
{
	$retVal = $macAddr -match '^([0-9a-fA-F]{2}[:-]{0,1}){5}[0-9a-fA-F]{2}$'
	return $retVal
}

# returns an unused random MAC capable of being assigned to a VM running on $hvServer
# the address will be outside of the dynamic MAC pool
# note that the Manufacturer bytes (first 3 bytes) are also randomly generated => do not rely on MAC to belong to any vendor
function getRandUnusedMAC([String]$hvServer,[Char]$delim)
{
	# first get the dynamic pool range
	$dynMACStart = (Get-VMHost -ComputerName $hvServer).MacAddressMinimum
	$validMac = isValidMAC $dynMACStart
	if (-not $validMac)
	{
		return $false
	}

	$dynMACEnd = (Get-VMHost -ComputerName $hvServer).MacAddressMaximum
	$validMac = isValidMAC $dynMACEnd
	if (-not $validMac)
	{
		return $false
	}

	[uint64]$lowerDyn = "0x$dynMACStart"
	[uint64]$upperDyn = "0x$dynMACEnd"

	if ($lowerDyn -gt $upperDyn)
	{
		return $false
	}

	# leave out the broadcast address
	[uint64]$maxMac = 281474976710655 #FF:FF:FF:FF:FF:FE

	# now random from the address space that has more macs
	[uint64]$belowPool = $lowerDyn - [uint64]1
	[uint64]$abovePool = $maxMac - $upperDyn

	if ($belowPool -gt $abovePool)
	{
		[uint64]$randStart = [uint64]1
		[uint64]$randStop = [uint64]$lowerDyn - [uint64]1
	}
	else
	{
		[uint64]$randStart = $upperDyn + [uint64]1
		[uint64]$randStop = $maxMac
	}

	# before getting the random number, check all VMs for static MACs
	$staticMacs = (get-VM -computerName $hvServer | Get-VMNetworkAdapter | where { $_.DynamicMacAddressEnabled -like "False" }).MacAddress


	do
	{
		# now get random number
		[uint64]$randDecAddr = Get-Random -minimum $randStart -maximum $randStop
		[String]$randAddr = "{0:X12}" -f $randDecAddr

		# Now set the unicast/multicast flag bit.
		[Byte] $firstbyte = "0x" + $randAddr.substring(0,2)
		# Set low-order bit to 0: unicast
		$firstbyte = [Byte] $firstbyte -band [Byte] 254 #254 == 11111110

		$randAddr = ("{0:X}" -f $firstbyte).padleft(2,"0") + $randAddr.substring(2)

	} while ($staticMacs -contains $randAddr) # check that we didn't random an already assigned MAC Address

	# randAddr now contains the new random MAC Address
	# add delim if specified
	if ($delim)
	{
		for ($i = 2 ; $i -le 14 ; $i += 3)
		{
			$randAddr = $randAddr.insert($i,$delim)
		}
	}

	# just to be sure
	$validMac = isValidMAC $randAddr

	if (-not $validMac)
	{
		return $false
	}

	# good MAC
	return $randAddr
}

# checks if IPv4 is in dotted format
function isValidIPv4([String]$ipv4)
{
    $retVal = ($ipv4 -As [IPAddress]) -As [Bool]
    return $retVal
}

# checks ip version
function isValidIP([String]$ipv4)
{
    $retVal = ($ipv4 -As [IPAddress]) -As [Bool]
    if ($retVal)
    {
        $ipVersion = [IpAddress] $ipv4
        $ipVersion = $ipVersion.AddressFamily
    }
    else
    {
        $ipVersion = $false
    }
    return $ipVersion
}

# returns the hex representation of an IP Address in dotted format
function IPtoHex([String]$ipv4)
{
	$valid = isValidIPv4 $ipv4

	if (-not $valid)
	{
		return $false
	}

	[IPAddress]$IP = $ipv4

	[String]$hexIP = "0:X" -f $IP

	return $hexIP

}

# returns the binary representation of an IP Address in dotted format
function IPtoBinary([String]$ipv4)
{
    $valid = isValidIPv4 $ipv4
    if (-not $valid) {
        return $false
    }

    [IPAddress]$IP = $ipv4
    [String]$binIP = [Convert]::ToString($IP.Address, 2)
    return $binIP
}


# returns the number of IPv4 Addresses available in network $network
# excludes the Broadcast address
function getAddrCount([String]$netmask)
{
	if ($netmask.IndexOf(".") -ge 0)
	{
		# we need to convert from dotted to cidr prefix
		$netmask = netmaskToCIDR $netmask

		if (-not $netmask)
		{
			return $false
		}
	}

    if ($netmask -gt 31 -or $netmask -lt 1) {
        return $false
    }

    [uint32]$valToShift = [uint32]32 - [uint32]$netmask
	[uint32]$count = [uint32]1 -shl [uint32]$valToShift
	[uint32]$count = [uint32]$count - [uint32]2
	return $count
}

# returns the next n-th IPv4 Address in network $network
# network should be in cidr (xx.xx.xx.xx/yy) notation
function getAddress([String]$IPv4, [String]$netmask, [int]$nth)
{
    $retVal = isValidIPv4 $IPv4
    if (-not $retVal)
    {
        return $false
    }

    $retVal = isValidIPv4 $netmask
    if (-not $retVal)
    {
        return $false
    }

	[IpAddress]$networkID = getNetworkID $IPv4 $netmask
    [IPAddress]$brdcast = getNetworkBroadcast $IPv4 $netmask

    [uint32]$addrCount =  getAddrCount $netmask

    [uint32]$start = byteSum $networkID
    if (-not $start)
    {
        return $false
    }

    if ($addrCount -lt 1)
    {
        return $false
    }

    if ($nth -lt 0)
    {
        if ((-1*$nth) -gt ($addrCount-1))
        {
            return $false
        }

        $nth = $addrCount + $nth + 1
    }
    else
    {
        # start counting from networkID + 1
        $nth += 1
        if ($nth -gt ($addrCount-1)) {
            return $false
        }
    }

    [uint32]$netBits = netmaskToCIDR $netmask

    [uint32]$nth = [uint32]$nth -shl $netBits

    [uint32]$rest = $start + $nth

    [IpAddress] $result = [uint32]$rest

    return $result.IPAddressToString
}

function byteSum([IpAddress]$ip)
{
    [uint32]$sum = [uint32]$ip.GetAddressBytes()[1] -shl 16
    [uint32]$res = 0
    $bytes = $ip.GetAddressBytes()
    [array]::Reverse($bytes)
    for ($i=0; $i -lt 4; $i++)
    {
        [uint32]$sum = [uint32]$bytes[$i] -shl (24 - $i*8)
        [uint32] $res += [uint32]$sum
    }
    return [uint32]$res
}

function isValidCidrFormat([String]$network)
{
	$network = $network.split('/')
	$valid = isValidIPv4 $network[0]

	if (-not $valid) {
		return $false
	}

	$prefix = $network[1]
	if ($prefix -lt 0 -or $prefix -gt 32)
	{
		return $false
	}

	return $true
}

# returns the network broadcast address
function getNetworkBroadcast([String]$IPv4, [String]$netmask)
{
    $networkID = getNetworkID $IPv4 $netmask
    [IpAddress]$tempIP = $networkID
    [IpAddress]$subnetIP = $netmask
    [IpAddress]$hostmask = [uint32](-bnot [uint32]$subnetIP.Address)
    [IpAddress]$broadcast= [uint32]$tempIP.Address -bor [uint32]$hostMask.Address
    return $broadcast.IPAddressToString
}

# checks if network defined by $netIP and $netmask contains IPv4 Address $IPv4ToCheck
# if $IncludeBrdcast is set, then the broadcast is also considered as a valid address inside the network
function containsAddress([String]$netIP,[String]$netmask,[String]$IPv4ToCheck,[Switch]$IncludeBrdcast)
{
    $retVal = isValidIPv4 $netIP
    if (-not $retVal)
    {
        return $false
    }

    $retVal = isValidIPv4 $netmask
    if (-not $retVal)
    {
        return $false
    }

    $retVal = isValidIPv4 $IPv4ToCheck
    if (-not $retVal)
    {
        return $false
    }

    [IpAddress]$brdcast = getNetworkBroadcast $netIP $netmask
    [IPAddress]$IPtoCheck = $IPv4ToCheck
    [IpAddress]$networkIP = $netIP
    [IpAddress]$subnet = $netmask
    if (($IPtoCheck.Address -band $subnet.Address) -eq ($networkIP.Address -band $subnet.Address))
    {
        if ($brdcast.Address -eq $IPtoCheck.Address -and (-not $IncludeBrdcast))
        {
            return $false
        }
        return $true
    }
    return $false
}

# transforms a quad netmask (e.g. 255.255.255.0) to cidr format (24)
function netmaskToCIDR([String]$netmask)
{
	$valid = isValidIPv4 $netmask
	if (-not $valid)
	{
		return $false
	}

	$binNetmask = IPtoBinary $netmask
	if (-not $binNetMask)
	{
		return $false
	}

	[char[]]$bits = $binNetmask.toCharArray()
	[uint32]$count = 0

	foreach ($bit in $bits)
	{
		if ($bit -eq '1')
		{
			$count++
		}
	}
	return $count
}

function getNetworkID([String]$IP, [String]$netmask)
{
	[IpAddress]$host = $IP
	[IpAddress]$ipnetmask = $netmask
	[uint32]$netid = [uint32]$host.Address -band [uint32]$ipnetmask.Address
	[IPAddress]$networkID = $netid
	return $networkID.IPAddressToString
}

# returns the network in cidr format
function NetworkToCIDR([String]$IPv4, [String] $Netmask)
{
	$valid = isValidIPv4 $IPv4
	if (-not $valid)
	{
		return $false
	}

	$networkID = getNetworkID $IPv4 $Netmask
	$cidrnetmask = netmaskToCIDR $Netmask
	return "$networkID"+"/"+"$cidrnetmask"
}

# CIDR to netmask
function CIDRtoNetmask([int]$cidr) {
    for($i=0; $i -lt 32; $i+=1) {
        if($i -lt $cidr) {
            $ip+="1"
        }else{
            $ip+= "0"
        }
    }
    $mask = ""
    for($byte=0; $byte -lt $ip.Length/8; $byte+=1) {
        $decimal = 0
        for($bit=0;$bit -lt 8; $bit+=1) {
            $poz = $byte * 8 + $bit
            if( $ip[$poz] -eq "1") {
                $decimal += [math]::Pow(2, 8 - $bit -1)
            }
        }
        $mask +=[convert]::ToString($decimal)
        if ( $byte -ne $ip.Length /8 -1) {
             $mask += "."
         }
    }
    return $mask
}

#######################################################################
#
# SR-IOV VF config function
#
#######################################################################
function ConfigureVF([String]$conIpv4,[String]$sshKey,[String]$netmask)
{
    # Transform netmask for RHEL/CentOS distro
    $netmaskCIDR = netmaskToCIDR $netmask

    # Send utils.sh on VM
    "Sending .\remote-scripts\ica\utils.sh to $conIpv4, authenticating with $sshKey"
    $retVal = SendFileToVM "$conIpv4" "$sshKey" ".\remote-scripts\ica\utils.sh" "/root/utils.sh"

    # Send SR-IOV_Utils.sh on VM
    "Sending .\remote-scripts\ica\SR-IOV_Utils.sh to $conIpv4 , authenticating with $sshKey"
    $retVal = SendFileToVM "$conIpv4" "$sshKey" ".\remote-scripts\ica\SR-IOV_Utils.sh" "/root/SR-IOV_Utils.sh"

    # create command to be sent to VM. This determines the interface based on the MAC Address.
    $cmdToVM = @"
#!/bin/bash
        cd ~
        # Source utils.sh
        dos2unix utils.sh
        dos2unix SR-IOV_Utils.sh

        # Source SR-IOV_Utils.sh
        . SR-IOV_Utils.sh || {
            echo "ERROR: unable to source SR-IOV_Utils.sh!" >> SRIOV_SendFile.log
            exit 2
        }

        # Install dependencies needed for testing
        InstallDependencies

        __vfCount=`$(ls /sys/class/net/ | grep -v 'eth0\|enP*\|lo' | wc -l) 
        __iterator=1
        __ipIterator=1
        # Set static IPs for each vf available
        while [ `$__iterator -le `$__vfCount ]; do
            # Extract vfIP value from constants.sh
            staticIP=`$(cat constants.sh | grep IP`$__ipIterator | tr = " " | awk '{print `$2}')

            if is_ubuntu ; then
                __file_path="/etc/network/interfaces"
                # Change /etc/network/interfaces 
                echo "auto eth`$__iterator" >> `$__file_path
                echo "iface eth`$__iterator inet static" >> `$__file_path
                echo "address `$staticIP" >> `$__file_path
                echo "netmask `$NETMASK" >> `$__file_path

                ifup eth`$__iterator

            elif is_suse ; then
                __file_path="/etc/sysconfig/network/ifcfg-eth`$__iterator"

                # Replace the BOOTPROTO, IPADDR and NETMASK values found in ifcfg file
                rm -f `$__file_path
                echo "DEVICE=eth`$__iterator" >> `$__file_path
                echo "NAME=eth`$__iterator" >> `$__file_path
                echo "BOOTPROTO=static" >> `$__file_path
                echo "IPADDR=`$staticIP" >> `$__file_path
                echo "NETMASK=`$NETMASK" >> `$__file_path
                echo "STARTMODE=auto" >> `$__file_path

                ifup eth`$__iterator

            elif is_fedora ; then
                __file_path="/etc/sysconfig/network-scripts/ifcfg-eth`$__iterator"

                # Replace the BOOTPROTO, IPADDR and NETMASK values found in ifcfg file
                rm -f `$__file_path
                echo "DEVICE=eth`$__iterator" >> `$__file_path
                echo "NAME=eth`$__iterator" >> `$__file_path
                echo "BOOTPROTO=static" >> `$__file_path
                echo "IPADDR=`$staticIP" >> `$__file_path
                echo "NETMASK=`$NETMASK" >> `$__file_path
                echo "ONBOOT=yes" >> `$__file_path

                ifup eth`$__iterator
            fi
            LogMsg "Network config file path: `$__file_path"

            __ipIterator=`$((`$__ipIterator + 2))
            : `$((__iterator++))
        done

        echo ConfigureVF: returned `$__retVal >> /root/SR-IOV_enable.log 2>&1
        exit `$__retVal
"@

    $filename = "ConfigureVF.sh"

    # check for file
    if (Test-Path ".\${filename}") {
        Remove-Item ".\${filename}"
    }

    Add-Content $filename "$cmdToVM"

    # send file
    $retVal = SendFileToVM $conIpv4 $sshKey $filename "/root/${$filename}"

    # delete file unless the Leave_trail param was set to yes.
    if ([string]::Compare($leaveTrail, "yes", $true) -ne 0) {
        Remove-Item ".\${filename}"
    }

    # check the return Value of SendFileToVM
    if (-not $retVal) {
        return $false
    }

    # execute sent file
    $retVal = SendCommandToVM $conIpv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"
    return $retVal
}

#######################################################################
#
# Function that creates a file on the test VM
#
#######################################################################
function CreateFileOnVM ([String]$conIpv4,[String]$sshKey,[String]$fileSize)
{
    # $fileSize param is in MB - for a 1 GB file, fileSize needs to be 1024
    # create command to be sent to VM. This determines the interface based on the MAC Address.
    $cmdToVM = @"
#!/bin/bash
        cd ~
        # Source utils.sh
        dos2unix utils.sh
        . utils.sh || {
            echo "ERROR: unable to source utils.sh!" >> SRIOV_SendFile.log
            exit 2
        }

        # Source constants file and initialize most common variables
        UtilsInit

        # Get source to create the file to be sent from VM1 to VM2
        if [ "`${ZERO_FILE:-UNDEFINED}" = "UNDEFINED" ]; then
            file_source=/dev/urandom
        else
            file_source=/dev/zero
        fi

        # Create file locally with PID appended
        output_file=large_file
        if [ -d "`$HOME"/"`$output_file" ]; then
            rm -rf "`$HOME"/"`$output_file"
        fi

        if [ -e "`$HOME"/"`$output_file" ]; then
            rm -f "`$HOME"/"`$output_file"
        fi

        dd if=`$file_source of="`$HOME"/"`$output_file" bs=$fileSize count=0 seek=1M
        if [ 0 -ne $? ]; then
            echo "ERROR: Unable to create file `$output_file in `$HOME" >> /root/SR-IOV_CreateFile.log 2>&1
            exit 1
        fi

        exit `$__retVal
"@

    $filename = "CreateFile.sh"

    # check for file
    if (Test-Path ".\${filename}") {
        Remove-Item ".\${filename}"
    }

    Add-Content $filename "$cmdToVM"

    # send file
    $retVal = SendFileToVM $conIpv4 $sshKey $filename "/root/${$filename}"

    # delete file unless the Leave_trail param was set to yes.
    if ([string]::Compare($leaveTrail, "yes", $true) -ne 0) {
        Remove-Item ".\${filename}"
    }

    # check the return Value of SendFileToVM
    if (-not $retVal) {
        return $false
    }

    # execute sent file
    $retVal = SendCommandToVM $conIpv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"
    return $retVal
}

#######################################################################
#
#   Function which creates an /etc/sysconfig/network-scripts/ifcfg-ethX 
# file for interface ethX
#
#######################################################################
function CreateInterfaceConfig([String]$conIpv4,[String]$sshKey, [String]$bootproto, [String]$MacAddr,[String]$staticIP,[String]$netmask)
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

    # create command to be sent to VM. This determines the interface based on the MAC Address.

    $cmdToVM = @"
#!/bin/bash
        cd /root
        dos2unix utils.sh
        if [ -f utils.sh ]; then
            sed -i 's/\r//' utils.sh
            . utils.sh
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
        echo CreateIfupConfigFile: interface `$__sys_interface >> /root/summary.log 2>&1
        CreateIfupConfigFile `$__sys_interface $bootproto $staticIP $netmask >> /root/summary.log 2>&1
        __retVal=`$?
        echo CreateIfupConfigFile: returned `$__retVal >> /root/summary.log 2>&1
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

#######################################################################
#
# Function that sends a file
#
#######################################################################
function SRIOV_SendFile ([String]$conIpv4, [String]$sshKey, [String]$MinimumPacketSize)
{
    # $fileSize param is in MB - for a 1 GB file, fileSize needs to be 1024
    # create command to be sent to VM. This determines the interface based on the MAC Address.
    $cmdToVM = @"
#!/bin/bash

        # Convert eol
        dos2unix utils.sh

        # Source utils.sh
        . utils.sh || {
            echo "ERROR: unable to source utils.sh!" >> SRIOV_SendFile.log
            exit 2
        }

        # Source constants file and initialize most common variables
        UtilsInit

        cd /root

        #
        # Count the VFs; By doing this, we can re-use the code with multiple VFss
        #
        __vfCount=`$(find /sys/devices -name net -a -ipath '*vmbus*' | grep pci | wc -l)

        #
        # Run file copy tests for each VF
        #
        __retVal=0
        output_file=large_file
        __iterator=1
        __ipIterator1=1
        __ipIterator2=2
        while [ `$__iterator -le `$__vfCount ]; do
            # Extract vfIP value from constants.sh
            staticIP1=`$(cat constants.sh | grep IP`$__ipIterator1 | tr = " " | awk '{print `$2}')
            staticIP2=`$(cat constants.sh | grep IP`$__ipIterator2 | tr = " " | awk '{print `$2}')

            # Send the file from VM1 to VM2
            scp -i "`$HOME"/.ssh/"`$sshKey" -o BindAddress=`$staticIP1 -o StrictHostKeyChecking=no "`$output_file" "`$REMOTE_USER"@"`$staticIP2":/tmp/"`$output_file"
            if [ 0 -ne `$? ]; then
                echo "ERROR: Unable to send the file from VM1 to VM2 using eth`$__iterator" >> SRIOV_SendFile.log
                __retVal=1
                exit 10
            else
                echo "Successfully sent `$output_file to `$staticIP2" >> SRIOV_SendFile.log
            fi

            # Verify both VFs on VM1 and VM2 to see if file was sent between them
            #txValue=`$(ifconfig eth`$__iterator | grep "TX packets" | sed 's/:/ /' |  awk '{print `$3}')
            txValue=$(cat /sys/class/net/eth$__iterator/statistics/tx_packets)
            echo "TX Value: $txValue" >> SRIOV_SendFile.log
            if [ $txValue -lt $MinimumPacketSize ]; then
                echo "ERROR: TX packets insufficient" >> SRIOV_SendFile.log
                `$__retVal=1
                exit 10
            fi

            vfName=`$(ssh -i "`$HOME"/.ssh/"`$sshKey" -o StrictHostKeyChecking=no "`$REMOTE_USER"@"`$VF_IP2" ls /sys/class/net | grep -v 'eth0\|eth1\|lo')
            #rxValue=`$(ssh -i "`$HOME"/.ssh/"`$sshKey" -o StrictHostKeyChecking=no "`$REMOTE_USER"@"`$VF_IP2" ifconfig `$vfName | grep "RX packets" | sed 's/:/ /' | awk '{print `$3}')
            rxValue=`$(ssh -i "`$HOME"/.ssh/"`$sshKey" -o StrictHostKeyChecking=no "`$REMOTE_USER"@"`$VF_IP2" cat /sys/class/net/eth$__iterator/statistics/rx_packets)
            echo "RX Value: $rxValue" >> SRIOV_SendFile.log
            if [ $rxValue -lt $MinimumPacketSize ]; then
                echo "ERROR: RX packets insufficient" >> SRIOV_SendFile.log
                `$__retVal=1
                exit 10
            fi

            # Verify that the data was sent over the VF
            # extract VF name
            vfInterface=`$(ls /sys/class/net/ | grep -v 'eth0\|eth1\|lo')

            #txValueVF=`$(ifconfig `$vfInterface | grep "TX packets" | sed 's/:/ /' | awk '{print `$3}')
            txValueVF=$(cat /sys/class/net/$vfInterface/statistics/tx_packets)
            echo "Virtual Function TX Value: $txValueVF" >> SRIOV_SendFile.log
            if [ $txValueVF -lt 6000 ]; then
                echo "ERROR: Virtual Function TX packets insufficient. Make sure VF is up & running" >> SRIOV_SendFile.log
                `$__retVal=1
                exit 10
            fi


            # Remove file from VM2
            ssh -i "`$HOME"/.ssh/"`$sshKey" -o StrictHostKeyChecking=no "`$REMOTE_USER"@"`$staticIP2" rm -f /tmp/"`$output_file"

            echo "Successfully sent file from VM1 to VM2 through eth`${__iterator}" >> SRIOV_SendFile.log
            __ipIterator1=`$((`$__ipIterator1 + 2))
            __ipIterator2=`$((`$__ipIterator2 + 2))
            : `$((__iterator++))
        done

        exit `$__retVal
"@

    $filename = "SendFile.sh"

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

#######################################################################
#
# SR-IOV configure VM and VF
#
#######################################################################
function ConfigureVMandVF([String]$vmName,[String]$hvServer,[String]$sshKey,[String]$vfIP,[String]$netmask,[String]$Switch_Name)
{
    # Source TCUitls.ps1 for getipv4 and other functions
    if (Test-Path ".\setupScripts\TCUtils.ps1") {
        . .\setupScripts\TCUtils.ps1
    }
    else {
        "ERROR: Could not find setupScripts\TCUtils.ps1"
        return $false
    }

    # Transform netmask for RHEL/CentOS distro
    $netmaskCIDR = netmaskToCIDR $netmask

    # Verify VM2 exists
    $vm = Get-VM -Name $vmName -ComputerName $hvServer -ERRORAction SilentlyContinue
    if (-not $vm)
    {
        "ERROR: VM ${vmName} does not exist"
        return $False
    }

    # Make sure VM2 is shutdown
    if (Get-VM -Name $vmName -ComputerName $hvServer | Where-Object { $_.State -like "Running" }) {
        Stop-VM $vmName  -ComputerName $hvServer -force
        if (-not $?) {
            "ERROR: Failed to shut $vm2Name down (in order to add a new network Adapter)"
            return $false
        }

        # wait for VM to finish shutting down
        $timeout = 60
        while (Get-VM -Name $vmName -ComputerName $hvServer | Where-Object{ $_.State -notlike "Off" })
        {
            if ($timeout -le 0) {
                "ERROR: Failed to shutdown $vmName"
                return $false
            }

            start-sleep -s 5
            $timeout = $timeout - 5
        }

    }

    # Revert VM2
    $snapshotParam = "SnapshotName = ICABase"
    .\setupScripts\RevertSnapshot.ps1 -vmName $vmName -hvServer $hvServer -testParams $snapshotParam
    Start-sleep -s 5

    # Add SR-IOV NIC adapter
    Add-VMNetworkAdapter -vmName $vmName -SwitchName $Switch_Name -IsLegacy:$false -ComputerName $hvServer
    if ($? -ne "True") {
        "Error: Add-VmNic to $vmName failed"
        $retVal = $False
    }
    else {
        $retVal = $True
    }

    # Enable SR-IOV
    Set-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer -IovWeight 1
    if ($? -eq "True") {
        $retVal = $True
    }
    else {
        "ERROR: Failed to enable SR-IOV on $vmName!"
    }

    # Start VM
    if (Get-VM -Name $vmName -ComputerName $hvServer | Where-Object{ $_.State -notlike "Running" }) {
        Start-VM -Name $vmName -ComputerName $hvServer
        if (-not $?) {
            "ERROR: Failed to start VM ${vmName}"
            $ERROR[0].Exception
            return $False
        }
    }

    $timeout = 200 # seconds
    if (-not (WaitForVMToStartKVP $vmName $hvServer $timeout)) {
        "Warning: $vmName never started KVP"
    }

    # Get IP from VM2
    $ipv4 = GetIPv4 $vmName $hvServer
    "$vm2Name IPADDRESS: $ipv4"

    # Send utils.sh on VM
    "Sending .\remote-scripts\ica\utils.sh to $ipv4 , authenticating with $sshKey"
    $retVal = SendFileToVM "$ipv4" "$sshKey" ".\remote-scripts\ica\utils.sh" "/root/utils.sh"

    # Send SR-IOV_Utils.sh on VM
    "Sending .\remote-scripts\ica\SR-IOV_Utils.sh to $ipv4 , authenticating with $sshKey"
    $retVal = SendFileToVM "$ipv4" "$sshKey" ".\remote-scripts\ica\SR-IOV_Utils.sh" "/root/SR-IOV_Utils.sh"

    # Create command to be sent to VM
    $cmdToVM = @"
#!/bin/bash
        cd ~
        touch constants.sh
        
        # Source utils.sh
        dos2unix utils.sh
        dos2unix SR-IOV_Utils.sh

        # Source SR-IOV_Utils.sh
        . SR-IOV_Utils.sh || {
            echo "ERROR: unable to source SR-IOV_Utils.sh!" >> SRIOV_SendFile.log
            exit 2
        }

        # Install dependencies needed for testing
        InstallDependencies

        __vfCount=`$(ls /sys/class/net/ | grep -v 'eth0\|eth1\|lo' | wc -l) 

        if is_ubuntu ; then

            __file_path="/etc/network/interfaces"
            # Change /etc/network/interfaces 

            echo "auto eth1" >> `$__file_path
            echo "iface eth1 inet static" >> `$__file_path
            echo "address $vfIP" >> `$__file_path
            echo "netmask $netmask" >> `$__file_path

            ifup eth1

        elif is_suse ; then
            __file_path="/etc/sysconfig/network/ifcfg-eth1"

            # Replace the BOOTPROTO, IPADDR and NETMASK values found in ifcfg file
            rm -f `$__file_path
            echo "DEVICE=eth1" >> `$__file_path
            echo "NAME=eth1" >> `$__file_path
            echo "BOOTPROTO=static" >> `$__file_path
            echo "IPADDR=$vfIP" >> `$__file_path
            echo "NETMASK=$netmask" >> `$__file_path
            echo "STARTMODE=auto" >> `$__file_path

            ifup eth1

        elif is_fedora ; then
            __file_path="/etc/sysconfig/network-scripts/ifcfg-eth1"

            # Replace the BOOTPROTO, IPADDR and NETMASK values found in ifcfg file
            rm -f `$__file_path
            echo "DEVICE=eth1" >> `$__file_path
            echo "NAME=eth1" >> `$__file_path
            echo "BOOTPROTO=static" >> `$__file_path
            echo "IPADDR=$vfIP" >> `$__file_path
            echo "NETMASK=$netmask" >> `$__file_path
            echo "ONBOOT=yes" >> `$__file_path

            ifup eth1
        fi

        echo "Network config file path: `$__file_path" >> ConfigureVMandVF.log

        __retVal=0
        echo ConfigureVF: returned `$__retVal >> ConfigureVMandVF.log 2>&1
        exit `$__retVal
"@

    $filename = "ConfigureVF.sh"

    # check for file
    if (Test-Path ".\${filename}") {
        Remove-Item ".\${filename}"
    }

    Add-Content $filename "$cmdToVM"

    # send file
    $retVal = SendFileToVM $ipv4 $sshKey $filename "/root/${$filename}"

    # delete file unless the Leave_trail param was set to yes.
    if ([string]::Compare($leaveTrail, "yes", $true) -ne 0) {
        Remove-Item ".\${filename}"
    }

    # check the return Value of SendFileToVM
    if (-not $retVal) {
        return $false
    }

    # execute sent file
    $retVal = SendCommandToVM $ipv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"
    return $retVal
}
