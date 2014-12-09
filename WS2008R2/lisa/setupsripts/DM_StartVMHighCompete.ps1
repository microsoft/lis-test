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

param([string] $vmName, [string] $hvServer, [string] $testParams)



#####################################################################
#
# TestPort
#
#####################################################################
function TestPort ([String] $serverName, [Int] $port=22, [Int] $to=3)
{
    $retVal = $False
    $timeout = $to * 1000

    #
    # Try an async connect to the specified machine/port
    #
    $tcpclient = new-Object system.Net.Sockets.TcpClient
    $iar = $tcpclient.BeginConnect($serverName,$port,$null,$null)

    #
    # Wait for the connect to complete. Also set a timeout
    # so we don't wait all day
    #
    $connected = $iar.AsyncWaitHandle.WaitOne($timeout,$false)

    # Check to see if the connection is done
    if($connected)
    {
        #
        # Close our connection
        #
        try
        {
            $sts = $tcpclient.EndConnect($iar)
            $retVal = $true
        }
        catch
        {
            # Nothing we need to do...
            $msg = $_.Exception.Message
        }
    }
    $tcpclient.Close()

    return $retVal
}


#######################################################################
#
# GetIPv4ViaKVP()
#
# Description:
#    Use ICASerial to retrieve the VMs IPv4 address.
#
# Assumptions:
#    The VM has a single NIC.
#    The icaserial.exe tool is located in the bin subdirectory.
#
#######################################################################
function GetIPv4ViaICASerial( [String] $vmName, [String] $server)
{
    $ipv4 = $null

    #
    # Make sure icaserial.exe exists
    #
    if (-not (Test-Path .\bin\icaserial.exe))
    {
        return $null
    }

    #
    # Get the MAC address of the VMs NIC
    #
    $vm = Get-VM -Name $vmName -ComputerName $server
    if (-not $vm)
    {
        return $null
    }

    $macAddr = $vm.NetworkAdapter[0].MacAddress
    if (-not $macAddr)
    {
        return $null
    }

    #
    # Get the Pipe name for COM1
    #
    $pipName = $vm.ComPort1.Path
    if (-not $pipeName)
    {
        return $null
    }

    #
    # Use ICASerial and ask the VM for it's IPv4 address
    #
    # Note: ICASerial is returning an array of strings rather than a single
    #       string.  Use the @() to force the response to be an array.  This
    #       will prevent breaking the following code when ICASerial is fixed.
    #       Remove the @() once ICASerial is fixed.
    #
    $timeout = "5"
    $response = @(bin\icaserial SEND $pipeName $timeout "get ipv4 macaddr=${macAddr}")
    if ($response)
    {
        #
        # The array indexing on $response is because icaserial returning an array
        # To be removed once icaserial is corrected
        #
        $tokens = $response[0].Split(" ")
        if ($tokens.Length -ne 3)
        {
            # "Error: invalid icaserial response: ${response}"
            return $null
        }

        if ($tokens[0] -ne "ipv4")
        {
            # "Error: icaserial response does not match request: ${response}"
            return $null
        }

        if ($tokens[1] -ne "0")
        {
            # "Error: icaserical returned an error: ${response}"
            return $null
        }
            
        $ipv4 = $tokens[2].Trim()
    }

    return $ipv4
}


#######################################################################
#
# GetIPv4ViaKVP()
#
# Description:
#
#
#######################################################################
function GetIPv4ViaKVP( [String] $vm, [String] $server)
{

    $vmObj = Get-WmiObject -Namespace root\virtualization -Query "Select * From Msvm_ComputerSystem Where ElementName=`'$vm`'" -ComputerName $server
    if (-not $vmObj)
    {
        return $null
    }

    $kvp = Get-WmiObject -Namespace root\virtualization -Query "Associators of {$vmObj} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent" -ComputerName $Server
    if (-not $kvp)
    {
        return $null
    }

    $rawData = $Kvp.GuestIntrinsicExchangeItems
    if (-not $rawData)
    {
        return $null
    }

    $name = $null
    $addresses = $null

    foreach ($dataItem in $rawData)
    {
        $found = 0
        $xmlData = [Xml] $dataItem
        foreach ($p in $xmlData.INSTANCE.PROPERTY)
        {
            if ($p.Name -eq "Name" -and $p.Value -eq "NetworkAddressIPv4")
            {
                $found += 1
            }

            if ($p.Name -eq "Data")
            {
                $addresses = $p.Value
                $found += 1
            }

            if ($found -eq 2)
            {
                $addrs = $addresses.Split(";")
                foreach ($addr in $addrs)
                {
                    if ($addr.StartsWith("127."))
                    {
                        Continue
                    }
                    return $addr
                }
            }
        }
    }

    return $null
}


#######################################################################
#
# GetIPv4FromHyperV()
#
# Description:
#    Look at the IP addresses on each NIC the VM has.  For each
#    address, see if it in IPv4 address and then see if it is
#    reachable via a ping.
#
#######################################################################
function GetIPv4FromHyperV([String] $vmName, [String] $server)
{
    $vm = Get-VM -Name $vmName -ComputerName $server
    if (-not $vm)
    {
        return $null
    }

    $networkAdapters = $vm.NetworkAdapters
    if (-not $networkAdapters)
    {
        return $null
    }

    foreach ($nic in $networkAdapters)
    {
        $ipAddresses = $nic.IPAddresses
        if (-not $ipAddresses)
        {
            Continue
        }

        foreach ($address in $ipAddresses)
        {
            # Ignore address if it is not an IPv4 address
            $addr = [IPAddress] $address
            if ($addr.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork)
            {
                Continue
            }

            # Ignore address if it a loopback address
            if ($address.StartsWith("127."))
            {
                Continue
            }

            # See if it is an address we can access
            $ping = New-Object System.Net.NetworkInformation.Ping
            $sts = $ping.Sent($address)
            if ($sts -and $sts.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
            {
                return $address
            }
        }
    }

    return $null
}


#######################################################################
#
# GetIPv4()
#
# Description:
#    Try the various methods to extract an IPv4 address from a VM.
#
#######################################################################
function GetIPv4([String] $vmName, [String] $server)
{
    $addr = GetIPv4FromKVP $vmName $server
    if (-not $addr)
    {
        $addr = GetIPv4FromICASerial $vmName $server
        if (-not $addr)
        {
            $addr = GetIPv4FromHyperV $vmName $server
            if (-not $addr)
            {
                return $null
            }
        }
    }

    return $addr
}


#######################################################################
#
# WaiForVMToStartKVP()
#
# Description:
#    Use KVP to get a VMs IP address.  Once the address is returned,
#    consider the VM up.
#
#######################################################################
function WaitForVMToStartKVP([String] $vmName, [String] $hvServer, [int] $timeout)
{
    $ipv4 = $null
    $retVal = $False

    $waitTimeOut = $timeout
    while ($waitTimeOut -gt 0)
    {
        $ipv4 = GetIPv4ViaKVP $vmName $hvServer
        if ($ipv4)
        {
            $retVal = $True
            break
        }

        $waitTimeOut -= 10
        Start-Sleep -s 10
    }

    return $retVal
}


#######################################################################
#
# WaiForVMToStartSSH()
#
# Description:
#    Try to connect to the SSH port (port 22) on the VM
#
#######################################################################
function WaitForVMToStartSSH([String] $ipv4, [int] $timeout)
{
    $retVal = $False

    $waitTimeOut = $timeout
    while($waitTimeOut -gt 0)
    {
        $sts = TestPort -Server $ipv4 -to 5
        if ($sts)
        {
            $retVal = $True
            break
        }

        $waitTimeOut -= 15  # Note - Test Port will sleep for 5 seconds
        Start-Sleep -s 10
    }

    return $retVal
}


#######################################################################
#
# StopVMViaSSH()
#
# Description:
#    Use SSH to send an init 0 command to the VM.
#
#######################################################################
function StopVMViaSSH ([String] $vmName, [String] $server="localhost", [string] $sshkey, [int] $timeout)
{
    if (-not $vmName)
    {
        return $False
    }

    if (-not $sshKey)
    {
        return $False
    }

    if (-not $timeout)
    {
        return $False
    }

    $vmipv4 = GetIPv4ViaKVP $vmName $server
    if (-not $vmipv4)
    {
        return $False
    }

    #
    # Tell the VM to stop
    #
    echo y | bin\plink -i ssh\${sshKey} root@${vmipv4} exit
    .\bin\plink.exe -i ssh\${sshKey} root@${vmipv4} "init 0"
    if (-not $?)
    {
        return $False
    }

    #
    # Wait for the VM to go to the Off state or timeout
    #
    $tmo = $timeout
    while ($tmo -gt 0)
    {
        Start-Sleep -s 5
        $tmo -= 5

        $vm = Get-VM -Name $vmName -ComputerName $server
        if (-not $vm)
        {
            return $False
        }

        if ($vm.State -eq [Microsoft.HyperV.PowerShell.VMState]::off)
        {
            return $True
        }
    }

    return $False
}


#######################################################################
#
# RunStressAppTestOnVM()
#
# Description:
#    Start run stressapptest application running on the VM.  
#    - Create a script to run the stress tool.
#    - Copy the script to the VM.
#    - Convert the file to Unix EOL.
#    - Set the execute bit of the file.
#    - Start the ATD.
#    - Submit the file to run via the AT daemon.
#
#######################################################################
function RunStressAppTestOnVM([String] $vmName, [String] $ipv4, [String] $sshKey, [String] $server, [string] $percent, [int] $seconds = 60)
{
    #
    # Handle any prompt for server key
    #
    echo y | bin\plink -i ssh\${sshKey} root@${ipv4} exit

    #
    # Copy the consumeMem.sh script to the VM
    #
    .\bin\pscp -i ssh\${sshKey} remote-scripts\ica\consumeMem.sh root@${ipv4}:
    if (-not $?)
    {
        "Error: Unable to copy consumeMem.sh to the VM"
        return $False
    }

    .\bin\plink -i ssh\${sshKey} root@${ipv4} "dos2unix consumeMem.sh  2> /dev/null"
    if (-not $?)
    {
        "Error: Unable to run dos2unix on startstress.sh"
        return $False
    }

    .\bin\plink -i ssh\${sshKey} root@${ipv4} "chmod 755 consumeMem.sh  2> /dev/null"
    if (-not $?)
    {
        "Error: Unable to chmod 755 consumeMem.sh"
        return $False
    }

    #
    # Create the startstress.sh script and copy it to the VM
    #    consumeMem.sh percentMem timeout
    #
    "~/consumeMem.sh ${percent} ${seconds}" | out-file -encoding ASCII -filepath startstress.sh

    .\bin\pscp -i ssh\${sshKey} .\startstress.sh root@${ipv4}:
    if (-not $?)
    {
        "Error: Unable to copy startstress.sh to the VM"
        return $False
    }
    del startstress.sh -ErrorAction SilentlyContinue

    .\bin\plink -i ssh\${sshKey} root@${ipv4} "dos2unix startstress.sh  2> /dev/null"
    if (-not $?)
    {
        "Error: Unable to run dos2unix on startstress.sh"
        return $False
    }

    .\bin\plink -i ssh\${sshKey} root@${ipv4} "chmod 755 startstress.sh  2> /dev/null"
    if (-not $?)
    {
        "Error: Unable to chmod 755 startstress.sh"
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "/etc/init.d/atd restart 2> /dev/null"
    if (-not $?)
    {
        "Error: Unable to start atd"
        return $False
    }

    #
    # Submit it twice for more of a load
    #
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "at -f startstress.sh now 2> /dev/null"
    if (-not $?)
    {
        "Error: Unable to submit startstress 1 to atd"
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "at -f startstress.sh now 2> /dev/null"
    if (-not $?)
    {
        "Error: Unable to submit startstress 2 to atd"
        return $False
    }

    return $True
}


#######################################################################
#
# Main script body
#
#######################################################################

#StopVMViaSSH $vmName $hvServer $sshKey 300

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

$testParams

$sshKey = $null
$ipv4 = $null
$vm2Name = $null
$vm3Name = $null
$vm2ipv4=$null

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    switch ($fields[0].Trim())
    {
    "vm2Name" { $vm2Name = $fields[1].Trim() }
    "vm3Name" { $vm3Name = $fields[1].Trim() }
    "SshKey"  { $sshKey  = $fields[1].Trim() }
    "ipv4"    { $ipv4    = $fields[1].Trim() }
	"rootdir" { $rootDir = $fields[1].Trim() }
    #"vm2ipv4" { $vm2ipv4 = $fields[1].Trim() }
    default   {}  # unknown param - just ignore it
    }
}

if (-not $vm2Name)
{
    "Error: test parameter vm2Name was not specified"
    return $False
}

if (-not $vm3Name)
{
    "Error: test parameter vm3Name was not specified"
    return $False
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

"sshKey   = ${sshKey}"
"ipv4     = ${ipv4}"
"vm1 Name = ${vmName}"
"vm2 Name = ${vm2Name}"
"vm2 ipv4 = ${vm2ipv4}"
"vm3 Name = ${vm3Name}"

#
# Change the working directory to where we need to be
#
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

cd $rootDir

echo "Verifies DM 2.3.4 Startup High Compete" > ./${vmName}_summary.log

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

#
# Start stress on VM1 before HyperV can balloon memory down
#
$percentMem = 80
$stressTime = 300
"Info: Adding memory stress to ${vm1Name}"
if (-not (RunStressAppTestOnVM $vm1Name $ipv4 $sshKey $hvServer $percentMem $stressTime))
{
    "Error: Unable to start the stress tool on ${vmname}"
    $sts = StopVMViaSSH $vm2Name $hvServer $sshKey 300
    return $False
}

#
# ICA Started VM1, so start VM2
#
Start-VM -Name $vm2Name -ComputerName $hvServer
if (-not $?)
{
    "Error: Unable to start VM ${vm2Name}"
    $error[0].Exception
    return $False
}

$timeout = 120 # seconds
if (-not (WaitForVMToStartKVP $vm2Name $hvServer $timeout))
{
    "Error: VM never started KVP"
    $sts = StopVMViaSSH $vm2Name $hvServer $sshKey 120
}

if (-not $vm2ipv4)
{
    $vm2ipv4 = GetIPv4ViaKVP $vm2Name $hvServer
}

if (-not (WaitForVMToStartSSH $vm2ipv4 $timeout))
{
    "Error: VM ${vm2Name} never started"
    $sts = StopVMViaSSH $vm2Name $hvServer $sshKey 120
    return $False
}

#
# Now start stress on VM2
#
$percentMem = 80
$stressTime = 300
"Info: Adding memory stress to ${vm2Name}"
if (-not (RunStressAppTestOnVM $vm2Name $vm2ipv4 $sshKey $hvServer $percentMem $stressTime))
{
    "Error: Unable to start the stress tool on ${vm2name}"
    $sts = StopVMViaSSH $vm2Name $hvServer $sshKey 300
    return $False
}

#
# Collect memory stats from VM1 and VM2 before starting VM3
#
"Info: Collecting memory metrics from ${vm1Name} and ${vm2Name}"
$vm1 = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm1)
{
    "Error: VM ${vmName} does not exist"
    $sts = StopVMViaSSH $vm2Name $hvServer $sshKey 300
    return $False
}

$vm1BeforeAssigned = $vm1.MemoryAssigned
$vm1BeforeDemand   = $vm1.MemoryDemand

$vm2 = Get-VM -Name $vm2Name -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm2)
{
    "Error: VM ${vm2Name} does not exist"
    $sts = StopVMViaSSH $vm2Name $hvServer $sshKey 300
    return $False
}

$vm2BeforeAssigned = $vm2.MemoryAssigned
$vm2BeforeDemand   = $vm2.MemoryDemand

#
# Wait a few seconds for the demand to settle before starting the third VM
#
Start-Sleep -s 12

#
# Start VM 3
#
"Info : Starting VM ${vm3Name}"
Start-VM -Name $vm3Name -ComputerName $hvServer
if (-not $?)
{
    "Error: Unable to start VM ${vm3Name}"
    $error[0].Exception
    $sts = StopVMViaSSH $vm2Name $hvServer $sshKey 300
    return $False
}

#
# Collect memory stats from VM1 and VM2 after starting VM3
#
"Info : Collecting additional metrics from ${vm1Name} and ${vm2Name}"
$vm1 = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm1)
{
    "Error: VM ${vmName} does not exist"
    $sts = StopVMViaSSH $vm2Name $hvServer $sshKey 300
    Stop-VM -Name $vm3Name -ComputerName $hvServer -force -Turnoff
    return $False
}

$vm1AfterAssigned = $vm1.MemoryAssigned
$vm1AfterDemand   = $vm1.memoryDemand

$vm2 = Get-VM -Name $vm2Name -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm2)
{
    "Error: VM ${vm2Name} does not exist"
    $sts = StopVMViaSSH $vm2Name $hvServer $sshKey 300
    Stop-VM -Name $vm3Name -ComputerName $hvServer -force -Turnoff
    return $False
}

$vm2AfterAssigned = $vm2.MemoryAssigned
$vm2AfterDemand   = $vm2.MemoryDemand

#
# Include VM3 info in the log
#
$vm3 = Get-VM -Name $vm3Name -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm3)
{
    "Error: VM ${vm3Name} does not exist"
    $sts = StopVMViaSSH $vm2Name $hvServer $sshKey 300
    Stop-VM -Name $vm3Name -ComputerName $hvServer -force -Turnoff
    return $False
}

$vm3Assigned = $vm3.MemoryAssigned
$vm3Demand   = $vm3.MemoryDemand

#
# Compute the deltas
#
$vm1AssignedDelta = $vm1AfterAssigned - $vm1BeforeAssigned
$vm2AssignedDelta = $vm2AfterAssigned - $vm2BeforeAssigned

$vm1DemandDelta = $vm1AfterDemand - $vm1BeforeDemand
$vm2DemandDelta = $vm2AfterDemand - $vm2BeforeDemand

#
# Put the deltas in the log file
#
"Deltas"
"  VM1 Assigned delta: ${vm1AssignedDelta}"
"  VM2 Assigned delta: ${vm2AssignedDelta}"
"  VM1 Demand        : ${vm1DemandDelta}"
"  VM2 Demand        : ${vm2DemandDelta}"
"  VM3 Assigned      : ${vm3Assigned}"
"  VM3 Demand        : ${vm3Demand}"


if ($vm1AssignedDelta -eq 0 -and $vm2AssignedDelta -eq 0)
{
    "Error: Assigned memory did not change for either VM"
    $sts = StopVMViaSSH $vm2Name $hvServer $sshKey 300
    Stop-VM -Name $vm3Name -ComputerName $hvServer -force -Turnoff
    return $False
}

#
# Wait for VM3 to finish booting all the way up
#
$timeout = 300 # seconds
if (-not (WaitForVMToStartKVP $vm3Name $hvServer $timeout))
{
    "Error: VM ${vm3Name} never started"
    $sts = StopVMViaSSH $vm2Name $hvServer $sshKey 300
    Stop-VM -Name $vm3Name -ComputerName $hvServer
    return $False
}

#
# see if each VM is usable
#
bin\plink.exe -i ssh\${sshKey} root@${ipv4} "lsmod | grep -q hv_balloon"
if (-not $?)
{
    "Error: Unable to issue command on VM ${vmName}"
    $sts = StopVMViaSSH $vm2Name $hvServer $sshKey 300
    Stop-VM -Name $vm3Name -ComputerName $hvServer
    return $False
}

bin\plink.exe -i ssh\${sshKey} root@${vm2ipv4} "lsmod | grep -q hv_balloon"
if (-not $?)
{
    "Error: Unable to issue command on VM ${vm2Name}"
    $sts = StopVMViaSSH $vm2Name $hvServer $sshKey 300
    Stop-VM -Name $vm3Name -ComputerName $hvServer
    return $False
}

#
# VM3 may not be a Linux VM, so try talking to the VM via KVP
#
$vm3ipv4 = GetIPv4ViaKVP $vm3Name $hvServer
if (-not $vm3ipv4)
{
    "Error: Unable to determine IPv4 address for VM ${vm3Name}"
    $sts = StopVMViaSSH $vm2Name $hvServer $sshKey 300
    Stop-VM -Name $vm3Name -ComputerName $hvServer
    return $False
}

#
# Stop VM 2 and 3 since ICA does not know to
#
# This assumes VM3 is Windows
#
$sts = StopVMViaSSH $vm2Name $hvServer $sshKey 300
Stop-VM -Name $vm3Name -ComputerName $hvServer

#
# If we got here, all the checks passed
#
"Info : Test Passed"

return $True
