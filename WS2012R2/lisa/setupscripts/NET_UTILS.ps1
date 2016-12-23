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
		[String]$randAddr = "{0:X}" -f $randDecAddr

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

	if (-not $valid)
	{
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

    if ($netmask -gt 31 -or $netmask -lt 1)
    {
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
        if ($nth -gt ($addrCount-1))
        {
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

	if (-not $valid)
	{
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
function CIDRtoNetmask([int]$cidr){

    for($i=0; $i -lt 32; $i+=1){
        if($i -lt $cidr){
            $ip+="1"
        }else{
            $ip+= "0"
        }
    }
    $mask = ""
    for($byte=0; $byte -lt $ip.Length/8; $byte+=1){
        $decimal = 0
        for($bit=0;$bit -lt 8; $bit+=1){
            $poz = $byte * 8 + $bit
            if( $ip[$poz] -eq "1"){
                $decimal += [math]::Pow(2, 8 - $bit -1)
            }
        }
        $mask +=[convert]::ToString($decimal)
        if ( $byte -ne $ip.Length /8 -1){
             $mask += "."
         }
    }
    return $mask
}

#######################################################################
#
# SR-IOV NIC bonding function on test VM
#
#######################################################################
function ConfigureBond([String]$conIpv4,[String]$sshKey,[String]$netmask)
{
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

        # Make sure we have synthetic network adapters present
        GetSynthNetInterfaces
        if [ 0 -ne `$? ]; then
            exit 2
        fi

        #
        # Run bondvf.sh script and configure interfaces properly
        #
        # Run bonding script from default location - CAN BE CHANGED IN THE FUTURE
        if is_ubuntu ; then
            bash /usr/src/linux-headers-*/tools/hv/bondvf.sh

            # Verify if bond0 was created
            __bondCount=`$(cat /etc/network/interfaces | grep "auto bond" | wc -l)
            if [ 0 -eq `$__bondCount ]; then
                exit 2
            fi

        elif is_suse ; then
            bash /usr/src/linux-*/tools/hv/bondvf.sh

            # Verify if bond0 was created
            __bondCount=`$(ls -d /etc/sysconfig/network/ifcfg-bond* | wc -l)
            if [ 0 -eq `$__bondCount ]; then
                exit 2
            fi

        elif is_fedora ; then
            ./bondvf.sh

            # Verify if bond0 was created
            __bondCount=`$(ls -d /etc/sysconfig/network-scripts/ifcfg-bond* | wc -l)
            if [ 0 -eq `$__bondCount ]; then
                exit 2
            fi
        fi

        __iterator=0
        __ipIterator=1
        # Set static IPs for each bond created
        while [ `$__iterator -lt `$__bondCount ]; do
            # Extract bondIP value from constants.sh
            staticIP=`$(cat constants.sh | grep IP`$__ipIterator | tr = " " | awk '{print `$2}')

            if is_ubuntu ; then
                __file_path="/etc/network/interfaces"
                # Change /etc/network/interfaces 
                sed -i "s/bond`$__iterator inet dhcp/bond`$__iterator inet static/g"` `$__file_path
                sed -i "/bond`$__iterator inet static/a address `$staticIP" `$__file_path
                sed -i "/address `$staticIP/a netmask `$NETMASK" `$__file_path

            elif is_suse ; then
                __file_path="/etc/sysconfig/network/ifcfg-bond`$__iterator"
                # Replace the BOOTPROTO, IPADDR and NETMASK values found in ifcfg file 
                sed -i "/\b\(BOOTPROTO\|IPADDR\|\NETMASK\)\b/d" `$__file_path
                cat <<-EOF >> `$__file_path
                BOOTPROTO=static
                IPADDR=`$staticIP
                NETMASK=`$NETMASK
EOF

            elif is_fedora ; then
                __file_path="/etc/sysconfig/network-scripts/ifcfg-bond`$__iterator"
                # Replace the BOOTPROTO, IPADDR and NETMASK values found in ifcfg file 
                sed -i "/\b\(BOOTPROTO\|IPADDR\|\NETMASK\)\b/d" `$__file_path
                cat <<-EOF >> `$__file_path
                BOOTPROTO=static
                IPADDR=`$staticIP
                NETMASK=`$NETMASK
EOF
            fi
            LogMsg "Network config file path: `$__file_path"

            __ipIterator=`$((`$__ipIterator + 2))
            : `$((__iterator++))
        done

        # Get everything up & running
        if is_ubuntu ; then
            service networking restart

        elif is_suse ; then
            service network restart

        elif is_fedora ; then
            service network restart
        fi     

        echo CreateBond: returned `$__retVal >> /root/SR-IOV_enable.log 2>&1
        exit `$__retVal
"@

    $filename = "CreateBond.sh"

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
# Function that sends a file through the bond interface/interfaces
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
        # Count the bonds; By doing this, we can re-use the code with multiple bonds
        #
        if is_ubuntu ; then
            __bondCount=`$(cat /etc/network/interfaces | grep "auto bond" | wc -l)
            if [ 0 -eq `$__bondCount ]; then
                exit 2
            fi

        elif is_suse ; then
            __bondCount=`$(ls -d /etc/sysconfig/network/ifcfg-bond* | wc -l)
            if [ 0 -eq `$__bondCount ]; then
                exit 2
            fi

        elif is_fedora ; then
            __bondCount=`$(ls -d /etc/sysconfig/network-scripts/ifcfg-bond* | wc -l)
            if [ 0 -eq `$__bondCount ]; then
                exit 2
            fi
        fi

        #
        # Run file copy tests for each bond interface 
        #
        output_file=large_file
        __iterator=0
        __ipIterator1=1
        __ipIterator2=2
        while [ `$__iterator -lt `$__bondCount ]; do
            # Extract bondIP value from constants.sh
            staticIP1=`$(cat constants.sh | grep IP`$__ipIterator1 | tr = " " | awk '{print `$2}')
            staticIP2=`$(cat constants.sh | grep IP`$__ipIterator2 | tr = " " | awk '{print `$2}')

            # Send the file from VM1 to VM2 via bond0
            scp -i "`$HOME"/.ssh/"`$sshKey" -o BindAddress=`$staticIP1 -o StrictHostKeyChecking=no "`$output_file" "`$REMOTE_USER"@"`$staticIP2":/tmp/"`$output_file"
            if [ 0 -ne `$? ]; then
                echo "ERROR: Unable to send the file from VM1 to VM2 using bond`$__iterator" >> SRIOV_SendFile.log
                exit 10
            else
                echo "Successfully sent `$output_file to `$staticIP2" >> SRIOV_SendFile.log
            fi

            # Verify both bond0 on VM1 and VM2 to see if file was sent between them
            txValue=`$(ifconfig bond`$__iterator | grep "TX packets" | sed 's/:/ /' |  awk '{print `$3}')
            echo "TX Value: `$txValue" >> SRIOV_SendFile.log
            if [ `$txValue -lt $MinimumPacketSize ]; then
                echo "ERROR: TX packets insufficient" >> SRIOV_SendFile.log
                exit 10
            fi

            rxValue=`$(ssh -i "`$HOME"/.ssh/"`$sshKey" -o StrictHostKeyChecking=no "`$REMOTE_USER"@"`$BOND_IP2" ifconfig bond`$__iterator | grep "RX packets" | sed 's/:/ /' | awk '{print `$3}')
            echo "RX Value: `$rxValue" >> SRIOV_SendFile.log
            if [ `$rxValue -lt $MinimumPacketSize ]; then
                echo "ERROR: RX packets insufficient" >> SRIOV_SendFile.log
                exit 10
            fi

            # Verify that the data was sent over the VF
            # extract VF name that is bonded
            if is_ubuntu ; then
                vfInterface=`$(grep bond-primary /etc/network/interfaces | awk '{print `$2}')

            elif is_suse ; then
                vfInterface=`$(grep BONDING_SLAVE_0 /etc/sysconfig/network/ifcfg-bond`${__iterator} | sed 's/=/ /' | awk '{print `$2}')

            elif is_fedora ; then
                vfInterface=`$(grep primary /etc/sysconfig/network-scripts/ifcfg-bond`${__iterator} | awk '{print substr(`$3,9,12)}')
            fi

            txValueVF=`$(ifconfig `$vfInterface | grep "TX packets" | sed 's/:/ /' | awk '{print `$3}')
            echo "Virtual Function TX Value: `$txValueVF" >> SRIOV_SendFile.log
            if [ `$txValueVF -lt 7000 ]; then
                echo "ERROR: Virtual Function TX packets insufficient. Make sure VF is up & running" >> SRIOV_SendFile.log
                exit 10
            fi


            # Remove file from VM2
            ssh -i "`$HOME"/.ssh/"`$sshKey" -o StrictHostKeyChecking=no "`$REMOTE_USER"@"`$staticIP2" rm -f /tmp/"`$output_file"

            echo "Successfully sent file from VM1 to VM2 through bond`${__iterator}" >> SRIOV_SendFile.log
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

function RestartVF ([String]$conIpv4, [String]$sshKey)
{
    # Create command to be sent to VM. This determines the interface based on the MAC Address.
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
        # Count the bonds; By doing this, we can re-use the code with multiple bonds
        #
        if is_ubuntu ; then
            # Verify if bond0 was created
            __bondCount=`$(cat /etc/network/interfaces | grep "auto bond" | wc -l)
            if [ 0 -eq `$__bondCount ]; then
                exit 2
            fi


        elif is_suse ; then
            # Verify if bond0 was created
            __bondCount=`$(ls -d /etc/sysconfig/network/ifcfg-bond* | wc -l)
            if [ 0 -eq `$__bondCount ]; then
                exit 2
            fi

        elif is_fedora ; then
            # Verify if bond0 was created
            __bondCount=`$(ls -d /etc/sysconfig/network-scripts/ifcfg-bond* | wc -l)
            if [ 0 -eq `$__bondCount ]; then
                exit 2
            fi
        fi

        #
        # Restart Virtual Function(s)
        #
        __iterator=0
        while [ `$__iterator -lt `$__bondCount ]; do
            # extract VF name that is bonded
            if is_ubuntu ; then
                vfInterface=`$(grep bond-primary /etc/network/interfaces | awk '{print `$2}')

            elif is_suse ; then
                vfInterface=`$(grep BONDING_SLAVE_1 /etc/sysconfig/network/ifcfg-bond`${__iterator} | sed 's/=/ /' | awk '{print `$2}')

            elif is_fedora ; then
                vfInterface=`$(grep primary /etc/sysconfig/network-scripts/ifcfg-bond`${__iterator} | awk '{print substr(`$3,9,12)}')
            fi

            ifdown `$vfInterface && ifup `$vfInterface

            : `$((__iterator++))
        done

        exit `$__retVal
"@

    $filename = "RestartVF.sh"

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

function iPerfInstall ([String]$conIpv4, [String]$sshKey)
{
    # Create command to be sent to VM. This determines the interface based on the MAC Address.
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
        # Install iPerf for every distro
        #
        if is_ubuntu ; then
            # Disable firewall 
            ufw disable

            # Download and install dependencies first
            apt-get install wget -y
            wget https://iperf.fr/download/ubuntu/libiperf0_3.1.3-1_amd64.deb
            if [ `$? -ne 0 ]; then
                echo "ERROR: unable to download libiperf" >> SRIOV_iPerfInstall.log
                exit 2
            fi

            dpkg -i libiperf*
            if [ `$? -ne 0 ]; then
                echo "ERROR: unable to install iPerf 3" >> SRIOV_iPerfInstall.log
                exit 2
            fi

            # Download and install iPerf 3
            wget https://iperf.fr/download/ubuntu/iperf3_3.1.3-1_amd64.deb
            if [ `$? -ne 0 ]; then
                echo "ERROR: unable to download iPerf 3" >> SRIOV_iPerfInstall.log
                exit 2
            fi

            # Install iPerf 3
            dpkg -i iperf3*
            if [ `$? -ne 0 ]; then
                echo "ERROR: unable to install iPerf 3" >> SRIOV_iPerfInstall.log
                exit 2
            fi

        elif is_suse ; then
            # Disable firewall
            service rcSuSEfirewall2 stop

            # Download and install dependencies first
            zypper in wget -y
            wget http://widehat.opensuse.org/repositories/network:/utilities/openSUSE_Factory/x86_64/libiperf0-3.1.3-50.3.x86_64.rpm
            if [ `$? -ne 0 ]; then
                echo "ERROR: unable to download libiperf" >> SRIOV_iPerfInstall.log
                exit 2
            fi

            rpm -i libiperf*
            if [ `$? -ne 0 ]; then
                echo "ERROR: unable to install iPerf 3" >> SRIOV_iPerfInstall.log
                # Check will fail if the package already exists, removing the exit condition
		# exit 2
            fi

            # Download and install iPerf 3
            wget http://download.opensuse.org/repositories/network:/utilities/openSUSE_13.2/x86_64/iperf-3.1.3-50.1.x86_64.rpm
            if [ `$? -ne 0 ]; then
                echo "ERROR: unable to download iPerf 3" >> SRIOV_iPerfInstall.log
                exit 2
            fi

            # Install iPerf 3
            rpm -i iperf*
            if [ `$? -ne 0 ]; then
                echo "ERROR: unable to install iPerf 3" >> SRIOV_iPerfInstall.log
                # Check will fail if the package already exists, removing the exit condition
		# exit 2
            fi

        elif is_fedora ; then
            # Disable firewall
            service firewalld stop

            # Download iPerf 3
            yum install wget -y
            wget https://iperf.fr/download/fedora/iperf3-3.1.3-1.fc24.x86_64.rpm
            if [ `$? -ne 0 ]; then
                echo "ERROR: unable to download iPerf 3" >> SRIOV_iPerfInstall.log
                exit 2
            fi

            # Install iPerf 3
            rpm -i iperf3*
            if [ `$? -ne 0 ]; then
                echo "ERROR: unable to install iPerf 3" >> SRIOV_iPerfInstall.log
                # Check will fail if the package already exists, removing the exit condition
		# exit 2
            fi
        fi

        __retvVal=`$(iperf3 -v)
        if [ `$? -ne 0 ]; then
            echo "ERROR: unable to start iPerf 3" >> SRIOV_iPerfInstall.log
            exit 2
        fi

        exit `$__retVal
"@

    $filename = "iPerfInstall.sh"

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
    $retVal = SendCommandToVM $conIpv4 $sshKey "cd /root && dos2unix iPerfInstall.sh && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"

    return $retVal   
}

#######################################################################
#
# SR-IOV configure VM and bond
#
#######################################################################
function ConfigureVMandBond([String]$vmName,[String]$hvServer,[String]$sshKey,[String]$bondIP,[String]$netmask)
{
    # Source TCUitls.ps1 for getipv4 and other functions
    if (Test-Path ".\setupScripts\TCUtils.ps1") {
        . .\setupScripts\TCUtils.ps1
    }
    else {
        "ERROR: Could not find setupScripts\TCUtils.ps1"
        return $false
    }

    # Verify VM2 exists
    $vm = Get-VM -Name $vmName -ComputerName $hvServer -ERRORAction SilentlyContinue
    if (-not $vm)
    {
        "ERROR: VM ${vmName} does not exist"
        return $False
    }

    # Make sure VM2 is shutdown
    if (Get-VM -Name $vmName -ComputerName $hvServer |  Where { $_.State -like "Running" }) {
        Stop-VM $vmName  -ComputerName $hvServer -force

        if (-not $?)
        {
            "ERROR: Failed to shut $vm2Name down (in order to add a new network Adapter)"
            return $false
        }

        # wait for VM to finish shutting down
        $timeout = 60
        while (Get-VM -Name $vmName -ComputerName $hvServer |  Where { $_.State -notlike "Off" })
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
    Add-VMNetworkAdapter -vmName $vmName -SwitchName SRIOV -IsLegacy:$false -ComputerName $hvServer
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
    if (Get-VM -Name $vmName -ComputerName $hvServer |  Where { $_.State -notlike "Running" }) {
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

    # Install iPerf on the VM
    $retVal = iPerfInstall $ipv4 $sshKey $netmask
    if (-not $retVal)
    {
        "ERROR: Failed to install iPerf3 on vm $vmName (IP: ${ipv4}, Host: ${hvServer})"
        return $false
    }

    # Create command to be sent to VM
    $cmdToVM = @"
#!/bin/bash
        cd ~
        chmod 775 utils.sh
        # Source utils.sh
        source utils.sh

        #
        # Run bondvf.sh script and configure interfaces properly
        #
        # Run bonding script from default location - CAN BE CHANGED IN THE FUTURE
        if is_ubuntu ; then
            bash /usr/src/linux-headers-*/tools/hv/bondvf.sh

            # Verify if bond0 was created
            __bondCount=`$(cat /etc/network/interfaces | grep "auto bond" | wc -l)
            if [ 0 -eq `$__bondCount ]; then
                exit 2
            fi

            __file_path="/etc/network/interfaces"
            # Change /etc/network/interfaces 
            sed -i "s/bond0 inet dhcp/bond0 inet static/g"` `$__file_path
            sed -i "/bond0 inet static/a address $bondIP" `$__file_path
            sed -i "/address $bondIP/a netmask $netmask" `$__file_path

        elif is_suse ; then
            bash /usr/src/linux-*/tools/hv/bondvf.sh

            # Verify if bond0 was created
            __bondCount=`$(ls -d /etc/sysconfig/network/ifcfg-bond* | wc -l)
            if [ 0 -eq `$__bondCount ]; then
                exit 2
            fi

            __file_path="/etc/sysconfig/network/ifcfg-bond0"
            # Replace the BOOTPROTO, IPADDR and NETMASK values found in ifcfg file 
            sed -i "/\b\(BOOTPROTO\|IPADDR\|\NETMASK\)\b/d" `$__file_path
            cat <<-EOF >> `$__file_path
            BOOTPROTO=static
            IPADDR=$bondIP
            NETMASK=$netmask
EOF

        elif is_fedora ; then
            bash bondvf.sh

            # Verify if bond0 was created
            __bondCount=`$(ls -d /etc/sysconfig/network-scripts/ifcfg-bond* | wc -l)
            if [ 0 -eq `$__bondCount ]; then
                exit 2
            fi

            __file_path="/etc/sysconfig/network-scripts/ifcfg-bond0"
            # Replace the BOOTPROTO, IPADDR and NETMASK values found in ifcfg file 
            sed -i "/\b\(BOOTPROTO\|IPADDR\|\NETMASK\)\b/d" `$__file_path
            cat <<-EOF >> `$__file_path
            BOOTPROTO=static
            IPADDR=$bondIP
            NETMASK=$netmask
EOF
        fi

        echo "Network config file path: `$__file_path" >> ConfigureVMandBond.log

        # Get everything up & running
        if is_ubuntu ; then
            service networking restart

        elif is_suse ; then
            service network restart

        elif is_fedora ; then
            service network restart
        fi

        __retVal=0
        echo CreateBond: returned `$__retVal >> ConfigureVMandBond.log 2>&1
        exit `$__retVal
"@

    $filename = "CreateBond.sh"

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
