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

 