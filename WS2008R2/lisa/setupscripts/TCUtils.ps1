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
    Description:
        Test Case Utility functions.  This is a collection of function
        commonly used by PowerShell test case scripts and setup scripts.

    Functions
        GetFileFromVM(ipv4, sshkey, remoteFilename, localFilename)
        GetIPv4(vmName, server)
        GetIPv4ViaHyperV(vmName, server)
        GetIPv4ViaICASerial(vmName, server)
        GetIPv4ViaKVP(VMName, server)
        GetRemoteFileInfo(filename, server )

        SendCommandToVM(ipv4, sshkey, command)
        SendFileToVM(ipv4, sshkey, localFilename, remoteFilename)
        StopVMViaSSH(vmName, server, timeout, sshKey)

        TestPort(ipv4addr, portNumber, timeout)

        WaitForVMToReportDemand(vmName, server, timeout)
        WaitForVMToStartKVP(vmName, server, timeout)
        WaitForVMToStartSSH(ipv4, timeout)

.Parameter vmName
    Name of the VM to test.
    
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
    
.Parameter testParams
    Test data for this test case
    
.Example

#>

#####################################################################
#
# GetFileFromVM()
#
#####################################################################
function GetFileFromVM([String] $ipv4, [String] $sshKey, [string] $remoteFile, [string] $localFile)
{
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
# Description:
#    Try the various methods to extract an IPv4 address from a VM.
#
#######################################################################
function GetIPv4([String] $vmName, [String] $server)
{
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
# Description:
#    Look at the IP addresses on each NIC the VM has.  For each
#    address, see if it in IPv4 address and then see if it is
#    reachable via a ping.
#
#######################################################################
function GetIPv4ViaHyperV([String] $vmName, [String] $server)
{
    $vm = Get-VM -Name $vmName -Server $server -ErrorAction SilentlyContinue
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
            $sts = $ping.Sent($address)
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
        Write-Error -Message "GetIPv4ViaICASerial: File .\bin\icaserial.exe not found" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }

    #
    # Get the MAC address of the VMs NIC
    #
    # if (-not $vm)
    # {
    #     Write-Error -Message "GetIPv4ViaICASerial: Unable to get VM ${vmName}" -Category ObjectNotFound -ErrorAction SilentlyContinue
    #     return $null
    # }
    $vmnic = Get-VMNIC -VM $vmName -Server $server -ErrorAction SilentlyContinue
    $macAddr = $vmnic[0].Address
    if (-not $macAddr)
    {
        Write-Error -Message "GetIPv4ViaICASerial: Unable to determine MAC address of first NIC" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }

    #
    # Get the Pipe name for COM1
    #
    $vm = Get-VM -Name $vmName -Server $server -ErrorAction SilentlyContinue
    $port = Get-VMSerialPort -VM $vmName -server $server -PortNumber 2
    $pipeName = $port.Connection
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
# Description:
#    Read the intrinsic data from the VM, then parse out the
#    VMs IPv4 address.
#
#    Note: If the VM has more than one IPv4 address, the first
#          non loopback address is returned.
#
#######################################################################
function GetIPv4ViaKVP( [String] $vmName, [String] $server)
{

    $vmObj = Get-WmiObject -Namespace root\virtualization -Query "Select * From Msvm_ComputerSystem Where ElementName=`'$vmName`'" -ComputerName $server
    if (-not $vmObj)
    {
        Write-Error -Message "GetIPv4ViaKVP: Unable to create Msvm_ComputerSystem object" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }

    $kvp = Get-WmiObject -Namespace root\virtualization -Query "Associators of {$vmObj} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent" -ComputerName $server
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
# Description:
#    Use SSH to send an init 0 command to the VM.
#
#######################################################################
function StopVMViaSSH ([String] $vmName, [String] $server="localhost", [int] $timeout, [string] $sshkey)
{
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

        $vm = Get-VM -Name $vmName -Server $server
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
# Description:
#    Try to connect to the SSH port (port 22) on the VM
#
#######################################################################
function WaitForVMToReportDemand([String] $vmName, [String] $server, [int] $timeout)
{
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
# Description:
#    Use KVP to get a VMs IP address.  Once the address is returned,
#    consider the VM up.
#
#######################################################################
function WaitForVMToStartKVP([String] $vmName, [String] $server, [int] $timeout)
{
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
# Description:
#    Try to connect to the SSH port (port 22) on the VM
#
#######################################################################
function WaitForVMToStartSSH([String] $ipv4addr, [int] $timeout)
{
    $retVal = $False

    $waitTimeOut = $timeout
    while($waitTimeOut -gt 0)
    {
        $sts = TestPort $ipv4addr 22 $timeout
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


