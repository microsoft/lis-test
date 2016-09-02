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
    Utility functions for test case scripts.

.Description
    Test Case Utility functions.  This is a collection of function
    commonly used by PowerShell test case scripts and setup scripts.
#>

#####################################################################
#
# GetFileFromVM()
#
#####################################################################
function GetFileFromVM([String] $ipv4, [String] $sshKey, [string] $remoteFile, [string] $localFile)
{
    <#
    .Synopsis
        Copy a file from a Linux VM.
    .Description
        Use SSH to copy a file from a Linux VM.
    .Parameter ipv4
        IPv4 address of the Linux VM.
    .Parameter sshKey
        Name of the SSH key to use.  This script assumes the key is located
        in the directory with a relative path of:  .\Ssh
    .Parameter remoteFile
        Name of the file on the Linux VM.
    .Parameter localFile
        Name to give the file when it is copied to the localhost.
    .Example
        GetFileFromVM "192.168.1.101" "rhel5_id_rsa.ppk" "state.txt" "remote_state.txt"
    #>

    $retVal = $False

    if (-not $ipv4)
    {
        Write-Error -Message "IPv4 address is null" -Category InvalidData -ErrorAction SilentlyContinue
        return $False
    }

    if (-not $sshKey)
    {
        Write-Error -Message "SSHKey is null" -Category InvalidData -ErrorAction SilentlyContinue
        return $False
    }

    if (-not $remoteFile)
    {
        Write-Error -Message "remoteFile is null" -Category InvalidData -ErrorAction SilentlyContinue
        return $False
    }

    if (-not $localFile)
    {
        Write-Error -Message "localFile is null" -Category InvalidData -ErrorAction SilentlyContinue
        return $False
    }

    $process = Start-Process bin\pscp -ArgumentList "-i ssh\${sshKey} root@${ipv4}:${remoteFile} ${localFile}" -PassThru -NoNewWindow -Wait -redirectStandardOutput lisaOut.tmp -redirectStandardError lisaErr.tmp
    if ($process.ExitCode -eq 0)
    {
        $retVal = $True
    }
    else
    {
        Write-Error -Message "Unable to get file '${remoteFile}' from ${ipv4}" -Category ConnectionError -ErrorAction SilentlyContinue
        return $False
    }

    del lisaOut.tmp -ErrorAction "SilentlyContinue"
    del lisaErr.tmp -ErrorAction "SilentlyContinue"

    return $retVal
}

#######################################################################
#
# GetIPv4()
#
#######################################################################
function GetIPv4([String] $vmName, [String] $server)
{
    <#
    .Synopsis
        Try to determin a VMs IPv4 address
    .Description
        Use various techniques to determine a VMs IPv4 address
    .Parameter vmName
        Name of the VM
    .Parameter server
        Name of the server hosting the VM
    .Example
        GetIpv4 "myTestVM" "localhost"
    #>

    $errMsg = $null
    $addr = GetIPv4ViaKVP $vmName $server
    if (-not $addr)
    {
        $errMsg += $error[0].Exception.Message
        $addr = GetIPv4ViaICASerial $vmName $server
        if (-not $addr)
        {
            $errMsg += ("`n" + $error[0].Exception.Message)
            $addr = GetIPv4ViaHyperV $vmName $server
            if (-not $addr)
            {
                $errMsg += ("`n" + $error[0].Exception.Message)
                Write-Error -Message ("GetIPv4: Unable to determin IP address for VM ${vmNAme}`n" + $errmsg) -Category ReadError -ErrorAction SilentlyContinue
                return $null
            }
        }
    }

    return $addr
}

#######################################################################
#
# GetIPv4ViaHyperV()
#
#######################################################################
function GetIPv4ViaHyperV([String] $vmName, [String] $server)
{
    <#
    .Synopsis
        Use the Hyper-V cmdlets to determine a VMs IPv4 address
    .Description
        Use the Hyhper-V cmdlets to examine a VMs NIC.  Return
        the first IPv4 address that is not a loopback address.
    .Parameter vmName
        Name of the VM
    .Parameter server
        Name of the server hosting the VM
    .Example
        GetIpv4ViaHyperV "myTestVM" "localhost"
    #>

    $vm = Get-VM -Name $vmName -ComputerName $server -ErrorAction SilentlyContinue
    if (-not $vm)
    {
        Write-Error -Message "GetIPv4ViaHyperV: Unable to create VM object for VM ${vmName}" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }

    $networkAdapters = $vm.NetworkAdapters
    if (-not $networkAdapters)
    {
        Write-Error -Message "GetIPv4ViaHyperV: No network adapters found on VM ${vmName}" -Category ObjectNotFound -ErrorAction SilentlyContinue
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
            $sts = $ping.Send($address)
            if ($sts -and $sts.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
            {
                return $address
            }
        }
    }

    Write-Error -Message "GetIPv4ViaHyperV: No IPv4 address found on any NICs for VM ${vmName}" -Category ObjectNotFound -ErrorAction SilentlyContinue
    return $null
}

#######################################################################
#
# GetIPv4ViaICASerial()
#
#######################################################################
function GetIPv4ViaICASerial( [String] $vmName, [String] $server)
{
    <#
    .Synopsis
        Use the ICASerial utility to read an IP address from the VM.
    .Description
        Use icaserial.exe to send a command to the VM via a COM port.
        This requires the VM was provisioned with the icaserial daemon
        which listens on COM2.
    .Parameter vmName
        Name of the VM
    .Parameter server
        Name of the server hosting the VM
    .Example
        GetIpv4ViaICASerial "myTestVM" "localhost"
    #>

    $ipv4 = $null

    #
    # Make sure icaserial.exe exists
    #
    if (-not (Test-Path .\bin\icaserial.exe))
    {
        Write-Error -Message "GetIPv4ViaICASerial: File .\bin\icaserial.exe not found" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }

    #
    # Get the MAC address of the VMs NIC
    #
    $vm = Get-VM -Name $vmName -ComputerName $server -ErrorAction SilentlyContinue
    if (-not $vm)
    {
        Write-Error -Message "GetIPv4ViaICASerial: Unable to get VM ${vmName}" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }

    $macAddr = $vm.NetworkAdapters[0].MacAddress
    if (-not $macAddr)
    {
        Write-Error -Message "GetIPv4ViaICASerial: Unable to determine MAC address of first NIC" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }

    #
    # Get the Pipe name for COM1
    #
    $pipeName = $vm.ComPort2.Path
    if (-not $pipeName)
    {
        Write-Error -Message "GetIPv4ViaICASerial: VM ${vmName} does not have a pipe associated with COM1" -Category ObjectNotFound -ErrorAction SilentlyContinue
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
            Write-Error -Message "GetIPv4ViaICASerial: Invalid ICAserial response: ${response}" -Category ReadError -ErrorAction SilentlyContinue
            return $null
        }

        if ($tokens[0] -ne "ipv4")
        {
            Write-Error -Message "GetIPv4ViaICASerial: ICAserial response does not match request: ${response}" -Category ObjectNotFound -ErrorAction SilentlyContinue
            return $null
        }

        if ($tokens[1] -ne "0")
        {
            Write-Error -Message "GetIPv4ViaICASerial: ICAserical returned an error: ${response}" -Category ReadError -ErrorAction SilentlyContinue
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
#######################################################################
function GetIPv4ViaKVP( [String] $vmName, [String] $server)
{
    <#
    .Synopsis
        Try to determine a VMs IPv4 address with KVP Intrinsic data.
    .Description
        Try to determine a VMs IPv4 address with KVP Intrinsic data.
    .Parameter vmName
        Name of the VM
    .Parameter server
        Name of the server hosting the VM
    .Example
        GetIpv4ViaKVP "myTestVM" "localhost"
    #>

    $vmObj = Get-WmiObject -Namespace root\virtualization\v2 -Query "Select * From Msvm_ComputerSystem Where ElementName=`'$vmName`'" -ComputerName $server
    if (-not $vmObj)
    {
        Write-Error -Message "GetIPv4ViaKVP: Unable to create Msvm_ComputerSystem object" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }

    $kvp = Get-WmiObject -Namespace root\virtualization\v2 -Query "Associators of {$vmObj} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent" -ComputerName $server
    if (-not $kvp)
    {
        Write-Error -Message "GetIPv4ViaKVP: Unable to create KVP exchange component" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }

    $rawData = $Kvp.GuestIntrinsicExchangeItems
    if (-not $rawData)
    {
        Write-Error -Message "GetIPv4ViaKVP: No KVP Intrinsic data returned" -Category ReadError -ErrorAction SilentlyContinue
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

    Write-Error -Message "GetIPv4ViaKVP: No IPv4 address found for VM ${vmName}" -Category ObjectNotFound -ErrorAction SilentlyContinue
    return $null
}

#######################################################################
#
# GenerateIpv4()
#
#######################################################################
function GenerateIpv4($tempipv4, $oldipv4)
{
    <#
    .Synopsis
        Generates an unused IP address based on an old IP address.
    .Description
        Generates an unused IP address based on an old IP address.
    .Parameter tempipv4
        The ipv4 address on which the new ipv4 will be based and generated in the same subnet
    .Example
        GenerateIpv4 $testIPv4Address $oldipv4
    #>
    [int]$i= $null
    [int]$check = $null
    if ($oldipv4 -eq $null){
        [int]$octet = 102
    }
    else {
        $oldIpPart = $oldipv4.Split(".")
        [int]$octet  = $oldIpPart[3]
    }

    $ipPart = $tempipv4.Split(".")
    $newAddress = ($ipPart[0]+"."+$ipPart[1]+"."+$ipPart[2])

    while ($check -ne 1 -and $octet -lt 255){
        $octet = 1 + $octet
        if (!(Test-Connection "$newAddress.$octet" -Count 1 -Quiet))
        {
            $splitip = $newAddress + "." + $octet
            $check = 1
        }
    }

    return $splitip.ToString()
}

#######################################################################
#
# GetKVPEntry()
#
#######################################################################
function GetKVPEntry( [String] $vmName, [String] $server, [String] $kvpEntryName)
{
    <#
    .Synopsis
        Try to determine a VMs KVP entry with KVP Intrinsic data.
    .Description
        Try to determine a VMs KVP entry with KVP Intrinsic data.
    .Parameter vmName
        Name of the VM
    .Parameter server
        Name of the server hosting the VM
    .Parameter kvpEntryName
        Name of the KVP entry, for example: FullyQualifiedDomainName, IntegrationServicesVersion, NetworkAddressIPv4, NetworkAddressIPv6
    .Example
        GetKVPEntry "myTestVM" "localhost" "FullyQualifiedDomainName"
    #>

    $vmObj = Get-WmiObject -Namespace root\virtualization\v2 -Query "Select * From Msvm_ComputerSystem Where ElementName=`'$vmName`'" -ComputerName $server
    if (-not $vmObj)
    {
        Write-Error -Message "GetKVPEntry: Unable to create Msvm_ComputerSystem object" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }

    $kvp = Get-WmiObject -Namespace root\virtualization\v2 -Query "Associators of {$vmObj} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent" -ComputerName $server
    if (-not $kvp)
    {
        Write-Error -Message "GetKVPEntry: Unable to create KVP exchange component" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }

    $rawData = $Kvp.GuestIntrinsicExchangeItems
    if (-not $rawData)
    {
        Write-Error -Message "GetKVPEntry: No KVP Intrinsic data returned" -Category ReadError -ErrorAction SilentlyContinue
        return $null
    }

    $kvpValue = $null

    foreach ($dataItem in $rawData)
    {
        $found = 0
        $xmlData = [Xml] $dataItem
        foreach ($p in $xmlData.INSTANCE.PROPERTY)
        {
            if ($p.Name -eq "Name" -and $p.Value -eq $kvpEntryName)
            {
                $found += 1
            }

            if ($p.Name -eq "Data")
            {
                $kvpValue = $p.Value
                $found += 1
            }

            if ($found -eq 2)
            {
                return $kvpValue
            }
        }
    }

    Write-Error -Message "GetKVPEntry: No such KVP entry found for VM ${vmName}" -Category ObjectNotFound -ErrorAction SilentlyContinue
    return $null
}

#######################################################################
#
# GetRemoteFileInfo()
#
# Description:
#     Use WMI to retrieve file information for a file residing on the
#     Hyper-V server.
#
# Return:
#     A FileInfo structure if the file exists, null otherwise.
#
#######################################################################
function GetRemoteFileInfo([String] $filename, [String] $server )
{
    <#
    .Synopsis
        Create a FileInfo object of a file on a remote host.
    .Description
        Use WMI to create a FileInfo object of a file on a
        remote host.
    .Parameter filename
        Path to the file on the remote host.
    .Parameter server
        Name of the server to ask.
    .Example
        GetRemoteFileInfo "C:\Hyper-V\VHDs\myDataDisk.vhd" "someRemoteHost"
    #>

    $fileInfo = $null

    if (-not $filename)
    {
        return $null
    }

    if (-not $server)
    {
        return $null
    }

    $remoteFilename = $filename.Replace("\", "\\")
    $fileInfo = Get-WmiObject -query "SELECT * FROM CIM_DataFile WHERE Name='${remoteFilename}'" -computer $server -ErrorAction SilentlyContinue

    return $fileInfo
}

#####################################################################
#
# SendCommandToVM()
#
#####################################################################
function SendCommandToVM([String] $ipv4, [String] $sshKey, [string] $command)
{
    <#
    .Synopsis
        Send a command to a Linux VM using SSH.
    .Description
        Send a command to a Linux VM using SSH.
    .Parameter ipv4
        IPv4 address of the VM to send the command to.
    .Parameter sshKey
        Name of the SSH key file to use.  Note this function assumes the
        ssh key a directory with a relative path of .\Ssh
    .Parameter command
        Command string to run on the Linux VM.
    .Example
        SendCommandToVM "192.168.1.101" "lisa_id_rsa.ppk" "echo 'It worked' > ~/test.txt"
    #>

    $retVal = $False

    if (-not $ipv4)
    {
        Write-Error -Message "ipv4 is null" -Category InvalidData -ErrorAction SilentlyContinue
        return $False
    }

    if (-not $sshKey)
    {
        Write-Error -Message "sshKey is null" -Category InvalidData -ErrorAction SilentlyContinue
        return $False
    }

    if (-not $command)
    {
        Write-Error -Message "command is null" -Category InvalidData -ErrorAction SilentlyContinue
        return $False
    }

    # get around plink questions
    echo y | bin\plink.exe -i ssh\${sshKey} root@${ipv4} 'exit 0'
    $process = Start-Process bin\plink -ArgumentList "-i ssh\${sshKey} root@${ipv4} ${command}" -PassThru -NoNewWindow -Wait -redirectStandardOutput lisaOut.tmp -redirectStandardError lisaErr.tmp
    if ($process.ExitCode -eq 0)
    {
        $retVal = $True
    }
    else
    {
         Write-Error -Message "Unable to send command to ${ipv4}. Command = '${command}'" -Category SyntaxError -ErrorAction SilentlyContinue
    }

    del lisaOut.tmp -ErrorAction "SilentlyContinue"
    del lisaErr.tmp -ErrorAction "SilentlyContinue"

    return $retVal
}

#####################################################################
#
# SendFileToVM()
#
#####################################################################
function SendFileToVM([String] $ipv4, [String] $sshkey, [string] $localFile, [string] $remoteFile, [Switch] $ChangeEOL)
{
    <#
    .Synopsis
        Use SSH to copy a file to a Linux VM.
    .Description
        Use SSH to copy a file to a Linux VM.
    .Parameter ipv4
        IPv4 address of the VM the file is to be copied to.
    .Parameter sshKey
        Name of the SSH key file to use.  Note this function assumes the
        ssh key a directory with a relative path of .\Ssh
    .Parameter localFile
        Path to the file on the local system.
    .Parameter remoteFile
        Name to call the file on the remote system.
    .Example
        SendFileToVM "192.168.1.101" "lisa_id_rsa.ppk" "C:\test\test.dat" "test.dat"
    #>

    if (-not $ipv4)
    {
        Write-Error -Message "ipv4 is null" -Category InvalidData -ErrorAction SilentlyContinue
        return $False
    }

    if (-not $sshKey)
    {
        Write-Error -Message "sshkey is null" -Category InvalidData -ErrorAction SilentlyContinue
        return $False
    }

    if (-not $localFile)
    {
        Write-Error -Message "localFile is null" -Category InvalidData -ErrorAction SilentlyContinue
        return $False
    }

    if (-not $remoteFile)
    {
        Write-Error -Message "remoteFile is null" -Category InvalidData -ErrorAction SilentlyContinue
        return $False
    }

    $recurse = ""
    if (test-path -path $localFile -PathType Container )
    {
        $recurse = "-r"
    }

    # get around plink questions
    echo y | bin\plink.exe -i ssh\${sshKey} root@${ipv4} "exit 0"

    $process = Start-Process bin\pscp -ArgumentList "-i ssh\${sshKey} ${localFile} root@${ipv4}:${remoteFile}" -PassThru -NoNewWindow -Wait -redirectStandardOutput lisaOut.tmp -redirectStandardError lisaErr.tmp
    if ($process.ExitCode -eq 0)
    {
        $retVal = $True
    }
    else
    {
        Write-Error -Message "Unable to send file '${localFile}' to ${ipv4}" -Category ConnectionError -ErrorAction SilentlyContinue
    }

    del lisaOut.tmp -ErrorAction "SilentlyContinue"
    del lisaErr.tmp -ErrorAction "SilentlyContinue"

    if ($ChangeEOL)
    {
        .bin\plink -i ssh\${sshKey} root@${ipv4} "dos2unix $remoteFile"
    }

    return $retVal
}

#######################################################################
#
# StopVMViaSSH()
#
#######################################################################
function StopVMViaSSH ([String] $vmName, [String] $server="localhost", [int] $timeout, [string] $sshkey)
{
    <#
    .Synopsis
        Use SSH to send an 'init 0' command to a Linux VM.
    .Description
        Use SSH to send an 'init 0' command to a Linux VM.
    .Parameter vmName
        Name of the Linux VM.
    .Parameter server
        Name of the server hosting the VM.
    .Parameter timeout
        Timeout in seconds to wait for the VM to enter a Hyper-V Off state
    .Parameter sshKey
        Name of the SSH key file to use.  Note this function assumes the
        ssh key a directory with a relative path of .\Ssh
    .Example
        StopVmViaSSH "testVM" "localhost" "300" "lisa_id_rsa.ppk"
    #>
	[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.HyperV.PowerShell")
    if (-not $vmName)
    {
        Write-Error -Message "StopVMViaSSH: VM name is null" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $False
    }

    if (-not $sshKey)
    {
        Write-Error -Message "StopVMViaSSH: SSHKey is null" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $False
    }

    if (-not $timeout)
    {
        Write-Error -Message "StopVMViaSSH: timeout is null" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $False
    }

    $vmipv4 = GetIPv4ViaKVP $vmName $server
    if (-not $vmipv4)
    {
        Write-Error -Message "StopVMViaSSH: Unable to determine VM IPv4 address" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $False
    }

    #
    # Tell the VM to stop
    #
    echo y | bin\plink -i ssh\${sshKey} root@${vmipv4} exit
    .\bin\plink.exe -i ssh\${sshKey} root@${vmipv4} "init 0"
    if (-not $?)
    {
        Write-Error -Message "StopVMViaSSH: Unable to send command via SSH" -Category ObjectNotFound -ErrorAction SilentlyContinue
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

    Write-Error -Message "StopVMViaSSH: VM did not stop within timeout period" -Category OperationTimeout -ErrorAction SilentlyContinue
    return $False
}

#####################################################################
#
# TestPort
#
#####################################################################
function TestPort ([String] $ipv4addr, [Int] $portNumber=22, [Int] $timeout=5)
{
    <#
    .Synopsis
        Test if a remote host is listening on a specific port.
    .Description
        Test if a remote host is listening on a spceific TCP port.
        Wait only timeout seconds.
    .Parameter ipv4addr
        IPv4 address of the system to check.
    .Parameter portNumber
        Port number to try.  Default is the SSH port.
    .Parameter timeout
        Timeout in seconds.  Default is 5 seconds.
    .Example
        TestPort "192.168.1.101" 22 10
    #>

    $retVal = $False
    $to = $timeout * 1000

    #
    # Try an async connect to the specified machine/port
    #
    $tcpclient = new-Object system.Net.Sockets.TcpClient
    $iar = $tcpclient.BeginConnect($ipv4addr,$portNumber,$null,$null)

    #
    # Wait for the connect to complete. Also set a timeout
    # so we don't wait all day
    #
    $connected = $iar.AsyncWaitHandle.WaitOne($to,$false)

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
# WaiForVMToReportDemand()
#
#######################################################################
function WaitForVMToReportDemand([String] $vmName, [String] $server, [int] $timeout)
{
    <#
    .Synopsis
        Wait for a VM to start reporting memory demand.
    .Description
        Wait for a VM to start reporting memory demand.
        This requires the VM be configured with Dynamic
        memory enabled.
    .Parameter vmName
        Name of the VM.
    .Parameter server
        Name of the server hosting the VM.
    .Parameter timeout
        Timeout in seconds to wait for memroy to be reported.
    .Example
        WaitForVMToReportDemand "testVM" "localhost" 300
    #>

    $retVal = $False

    $waitTimeOut = $timeout
    while($waitTimeOut -gt 0)
    {
        $vm = Get-VM -Name $vmName -ComputerName $server
        if (-not $vm)
        {
            Write-Error -Message "WaitForVMToReportDemand: Unable to find VM ${vmNAme}" -Category ObjectNotFound -ErrorAction SilentlyContinue
            return $false
        }

        if ($vm.MemoryDemand -and $vm.MemoryDemand -gt 0)
        {
            return $True
        }

        $waitTimeOut -= 5  # Note - Test Port will sleep for 5 seconds
        Start-Sleep -s 5
    }

    Write-Error -Message "WaitForVMToReportDemand: VM ${vmName} did not report demand within timeout period ($timeout)" -Category OperationTimeout -ErrorAction SilentlyContinue
    return $retVal
}

#######################################################################
#
# WaiForVMToStartKVP()
#
#######################################################################
function WaitForVMToStartKVP([String] $vmName, [String] $server, [int] $timeout)
{
    <#
    .Synopsis
        Wait for the Linux VM to start the KVP daemon.
    .Description
        Wait for a Linux VM with the LIS components installed
        to start the KVP daemon.
    .Parameter vmName
        Name of the VM to test.
    .Parameter server
        Server hosting the VM.
    .Parameter timeout
        Timeout in seconds to wait.
    .Example
        WaitForVMToStartKVP "testVM" "localhost"  300
    #>

    $ipv4 = $null
    $retVal = $False

    $waitTimeOut = $timeout
    while ($waitTimeOut -gt 0)
    {
        $ipv4 = GetIPv4ViaKVP $vmName $server
        if ($ipv4)
        {
            return $True
        }

        $waitTimeOut -= 10
        Start-Sleep -s 10
    }

    Write-Error -Message "WaitForVMToStartKVP: VM ${vmName} did not start KVP within timeout period ($timeout)" -Category OperationTimeout -ErrorAction SilentlyContinue
    return $retVal
}

#######################################################################
#
# WaiForVMToStartSSH()
#
#######################################################################
function WaitForVMToStartSSH([String] $ipv4addr, [int] $timeout)
{
    <#
    .Synopsis
        Wait for a Linux VM to start SSH
    .Description
        Wait for a Linux VM to start SSH.  This is done
        by testing if the target machine is lisetning on
        port 22.
    .Parameter ipv4addr
        IPv4 address of the system to test.
    .Parameter timeout
        Timeout in second to wait
    .Example
        WaitForVMToStartSSH "192.168.1.101" 300
    #>

    $retVal = $False

    $waitTimeOut = $timeout
    while($waitTimeOut -gt 0)
    {
        $sts = TestPort -ipv4addr $ipv4addr -timeout 5
        if ($sts)
        {
            return $True
        }

        $waitTimeOut -= 15  # Note - Test Port will sleep for 5 seconds
        Start-Sleep -s 10
    }

    if (-not $retVal)
    {
        Write-Error -Message "WaitForVMToStartSSH: VM ${vmName} did not start SSH within timeout period ($timeout)" -Category OperationTimeout -ErrorAction SilentlyContinue
    }

    return $retVal
}

#######################################################################
#
# WaiForVMToStop()
#
#######################################################################
function  WaitForVMToStop ([string] $vmName ,[string]  $hvServer, [int] $timeout)
{
    <#
    .Synopsis
        Wait for a VM to enter the Hyper-V Off state.
    .Description
        Wait for a VM to enter the Hyper-V Off state
    .Parameter vmName
        Name of the VM that is stopping.
    .Parameter hvSesrver
        Name of the server hosting the VM.
    .Parameter timeout
        Timeout in seconds to wait.
    .Example
        WaitForVMToStop "testVM" "localhost" 300
    a#>
	[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.HyperV.PowerShell")
    $tmo = $timeout
    while ($tmo -gt 0)
    {
        Start-Sleep -s 1
        $tmo -= 5

        $vm = Get-VM -Name $vmName -ComputerName $hvServer
        if (-not $vm)
        {
            return $False
        }

        if ($vm.State -eq [Microsoft.HyperV.PowerShell.VMState]::off)
        {
            return $True
        }
    }

    Write-Error -Message "StopVM: VM did not stop within timeout period" -Category OperationTimeout -ErrorAction SilentlyContinue
    return $False
}

#######################################################################
#
# Runs a remote script on the VM and returns the log.
#
#######################################################################
function RunRemoteScript($remoteScript)
{
    $retValue = $False
    $stateFile     = "state.txt"
    $TestCompleted = "TestCompleted"
    $TestAborted   = "TestAborted"
    $TestFailed   = "TestFailed"
    $TestRunning   = "TestRunning"
    $timeout       = 6000

    "./${remoteScript} > ${remoteScript}.log" | out-file -encoding ASCII -filepath runtest.sh

    .\bin\pscp -i ssh\${sshKey} .\runtest.sh root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy runtest.sh to the VM"
       return $False
    }

     .\bin\pscp -i ssh\${sshKey} .\remote-scripts\ica\${remoteScript} root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy ${remoteScript} to the VM"
       return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix ${remoteScript} 2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to run dos2unix on ${remoteScript}"
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to run dos2unix on runtest.sh"
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x ${remoteScript}   2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to chmod +x ${remoteScript}"
        return $False
    }
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to chmod +x runtest.sh " -
        return $False
    }

    # Run the script on the vm
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "./runtest.sh"

    # Return the state file
    while ($timeout -ne 0 )
    {
    .\bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${stateFile} . #| out-null
    $sts = $?
    if ($sts)
    {
        if (test-path $stateFile)
        {
            $contents = Get-Content -Path $stateFile
            if ($null -ne $contents)
            {
                    if ($contents -eq $TestCompleted)
                    {
                        Write-Output "Info : state file contains Testcompleted."
                        $retValue = $True
                        break
                    }

                    if ($contents -eq $TestAborted)
                    {
                         Write-Output "Info : State file contains TestAborted message."
                         break
                    }
                    if ($contents -eq $TestFailed)
                    {
                        Write-Output "Info : State file contains TestFailed message."
                        break
                    }
                    $timeout--

                    if ($timeout -eq 0)
                    {
                        Write-Output "Error : Timed out on Test Running , Exiting test execution."
                        break
                    }

            }
            else
            {
                Write-Output "Warn : state file is empty"
                break
            }

        }
        else
        {
             Write-Host "Warn : ssh reported success, but state file was not copied"
             break
        }
    }
    else
    {
         Write-Output "Error : pscp exit status = $sts"
         Write-Output "Error : unable to pull state.txt from VM."
         break
    }
    }

    # Get the logs
    $remoteScriptLog = $remoteScript+".log"

    bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${remoteScriptLog} .
    $sts = $?
    if ($sts)
    {
        if (test-path $remoteScriptLog)
        {
            $contents = Get-Content -Path $remoteScriptLog
            if ($null -ne $contents)
            {
                    if ($null -ne ${TestLogDir})
                    {
                        move "${remoteScriptLog}" "${TestLogDir}\${remoteScriptLog}"
                    }

                    else
                    {
                        Write-Output "INFO: $remoteScriptLog is copied in ${rootDir}"
                    }

            }
            else
            {
                Write-Output "Warn: $remoteScriptLog is empty"
            }
        }
        else
        {
             Write-Output "Warn: ssh reported success, but $remoteScriptLog file was not copied"
        }
    }

    # Cleanup
    del state.txt -ErrorAction "SilentlyContinue"
    del runtest.sh -ErrorAction "SilentlyContinue"

    return $retValue
}

#######################################################################
#
# Checks kernel version on VM
#
#######################################################################
function check_kernel
{
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "uname -r"
    if (-not $?) {
        Write-Output "ERROR: Unable check kernel version" -ErrorAction SilentlyContinue
        return $False
    }
}