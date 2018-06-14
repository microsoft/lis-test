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
#
# test result codes
#
New-Variable Passed              -value "Passed"              -option ReadOnly -Force
New-Variable Skipped             -value "Skipped"             -option ReadOnly -Force
New-Variable Aborted             -value "Aborted"             -option ReadOnly -Force
New-Variable Failed              -value "Failed"              -option ReadOnly -Force

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

    $process = Start-Process bin\pscp -ArgumentList "-i ssh\${sshKey} root@${ipv4}:${remoteFile} ${localFile}" `
	 -PassThru -NoNewWindow -Wait -redirectStandardOutput lisaOut_${ipv4}.tmp -redirectStandardError lisaErr_${ipv4}.tmp
    if ($process.ExitCode -eq 0)
    {
        $retVal = $True
    }
    else
    {
        Write-Error -Message "Unable to get file '${remoteFile}' from ${ipv4}" -Category ConnectionError -ErrorAction SilentlyContinue
        return $False
    }

    del lisaOut_${ipv4}.tmp -ErrorAction "SilentlyContinue"
    del lisaErr_${ipv4}.tmp -ErrorAction "SilentlyContinue"

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
        Try to determine a VMs IPv4 address
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
                Write-Error -Message ("GetIPv4: Unable to determine IP address for VM ${vmName}`n" + $errmsg) -Category ReadError -ErrorAction SilentlyContinue
                return $null
            }
        }
    }

    return $addr
}

#######################################################################
#
# Logger
#
#######################################################################
class Logger {
    [String] $LogFile
    [Boolean] $AddTimestamp

    Logger([String] $logFile, [Boolean] $addTimestamp) {
        $this.LogFile = $logFile
        $this.AddTimestamp = $addTimestamp
    }

    [void] info([String] $message) {
        $color = "white"
        $this.logMessage("Info: ${message}", $color)
    }

    [void] error([String] $message) {
        $color = "Red"
        $this.logMessage("Error: ${message}", $color)
    }

    [void] debug([String] $message) {
        $color = "Gray"
        $this.logMessage("Debug: ${message}", $color)
    }

    [void] warning([String] $message) {
        $color = "Yellow"
        $this.logMessage("Warning: ${message}", $color)
    }

    [void] logMessage([String] $message, [String] $color) {
        if ($this.AddTimestamp) {
            $timestamp = $(Get-Date -Format G)
            $message = "${timestamp} - ${message}"
        }
        Write-Host $message -ForegroundColor $color
        $message | Add-Content $this.LogFile
    }
}


#######################################################################
#
# LoggerManager
#
#######################################################################
class LoggerManager {
    [Logger] $Summary
    [Logger] $TestCase

    LoggerManager([Logger] $summaryLogger, [Logger] $testCaseLogger) {
        $this.Summary = $summaryLogger
        $this.TestCase = $testCaseLogger
    }

    [LoggerManager] static GetLoggerManager([String] $vmName, [String] $testParams) {
        $params = $testParams.Split(";")
        $testLogDir = $null
        $testName = $null
        foreach ($p in $params) {
            $fields = $p.Split("=")
            if ($fields[0].Trim() -eq "TestLogDir") {
                $testLogDir = $fields[1].Trim()
            } elseif ($fields[0].Trim() -eq "TestName") {
                $testName = $fields[1].Trim()
            }
        }

        if ((-not $testLogDir) -or (-not $testName)) {
            throw [System.ArgumentException] "TestLogDir or TestName not found."
        }

        $summaryLog = "${vmName}_summary.log"
        Remove-Item $summaryLog -ErrorAction SilentlyContinue
        $testLog = "${testLogDir}\${vmName}_${testName}_ps.log"

        $summaryLogger = [Logger]::new($summaryLog, $False)
        $testLogger = [Logger]::new($testLog, $True)
        return [LoggerManager]::new($summaryLogger, $testLogger)
    }
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
    $process = Start-Process bin\plink -ArgumentList "-i ssh\${sshKey} root@${ipv4} ${command}" `
	 -PassThru -NoNewWindow -Wait -redirectStandardOutput lisaOut_${ipv4}.tmp -redirectStandardError lisaErr_${ipv4}.tmp
    if ($process.ExitCode -eq 0)
    {
        $retVal = $True
    }
    else
    {
         Write-Error -Message "Unable to send command to ${ipv4}. Command = '${command}'" -Category SyntaxError -ErrorAction SilentlyContinue
    }

    del lisaOut_${ipv4}.tmp -ErrorAction "SilentlyContinue"
    del lisaErr_${ipv4}.tmp -ErrorAction "SilentlyContinue"

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

    $process = Start-Process bin\pscp -ArgumentList "-i ssh\${sshKey} ${localFile} root@${ipv4}:${remoteFile}" `
	 -PassThru -NoNewWindow -Wait -redirectStandardOutput lisaOut_${ipv4}.tmp -redirectStandardError lisaErr_${ipv4}.tmp
    if ($process.ExitCode -eq 0)
    {
        $retVal = $True
    }
    else
    {
        Write-Error -Message "Unable to send file '${localFile}' to ${ipv4}" -Category ConnectionError -ErrorAction SilentlyContinue
    }

    del lisaOut_${ipv4}.tmp -ErrorAction "SilentlyContinue"
    del lisaErr_${ipv4}.tmp -ErrorAction "SilentlyContinue"

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
# GetIPv4AndWaitForSSHStart()
#
#######################################################################
function GetIPv4AndWaitForSSHStart([String] $vmName, [String] $hvServer, [String] $sshKey, [int] $stepTimeout)
{
    <#
    .Synopsis
        Get ipv4 from kvp, wait for VM kvp and ssh start, return ipv4
    .Description
        Wait for KVP start and
        Get ipv4 via kvp
        Wait for ssh start, test ssh.
        Returns [String]ipv4 address if succeeded or $False if failed
    .Parameter vmName
        Name of the VM to test.
    .Parameter server
        Server hosting the VM.
    .Parameter sshKey
        sshKey for ssh connection to VM
    .Parameter stepTimeout
        Timeout for each waiting step (kvp & ssh)
    .Example
        $new_ip = GetIPv4AndWaitForSSHStart $vmName $hvServer $sshKey 360
        if ($new_ip) {$ipv4 = $new_ip}
        else {...}
    #>

    # Wait for KVP to start and able to get ipv4 addr
    if (-not (WaitForVMToStartKVP $vmName $hvServer $stepTimeout)) {
        Write-Error "GetIPv4AndWaitForSSHStart: Unable to get ipv4 from VM ${vmName} via KVP within timeout period ($timeout)" -Category OperationTimeout -ErrorAction SilentlyContinue
        return $False
    }

    # Get new ipv4 in case an new ip is allocated to vm after reboot
    $new_ip = GetIPv4 $vmName $hvServer
    if (-not ($new_ip)){
        Write-Error "GetIPv4AndWaitForSSHStart: Unable to get ipv4 from VM ${vmName} via KVP" -Category OperationTimeout -ErrorAction SilentlyContinue
        return $False
    }

    # Wait for port 22 open
    if (-not (WaitForVMToStartSSH $new_ip $stepTimeout)) {
        Write-Error "GetIPv4AndWaitForSSHStart: Failed to connect $new_ip port 22 within timeout period ($timeout)" -Category OperationTimeout -ErrorAction SilentlyContinue
        return $False
    }

    # Cache fingerprint, Check ssh is functional after reboot
    echo y | bin\plink.exe -i ssh\$sshKey root@$new_ip 'exit 0'
    $TestConnection = bin\plink.exe -i ssh\$sshKey root@$new_ip "echo Connected"
    if ($TestConnection -ne "Connected"){
        Write-Error "GetIPv4AndWaitForSSHStart: SSH is not working correctly after boot up" -Category OperationTimeout -ErrorAction SilentlyContinue
        return $False
    }

    return $new_ip
}

#######################################################################
#
# WaiForVMToStop()
#
#######################################################################
function  WaitForVMToStop ([string] $vmName, [string] $hvServer, [int] $timeout)
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
    $TestSkipped   = "TestSkipped"
    $timeout       = 6000
    $params        = $scriptParam

    "./${remoteScript} ${params} > ${remoteScript}.log" | out-file -encoding ASCII -filepath runtest.sh

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
                         $retValue = $Aborted
                         break
                    }
                    if ($contents -eq $TestFailed)
                    {
                        Write-Output "Info : State file contains TestFailed message."
                        break
                    }
                    if ($contents -eq $TestSkipped)
                    {
                        $retValue = $Skipped
                        Write-Output "Info : State file contains TestSkipped message."
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

#######################################################################
#
# Check for application on VM
#
#######################################################################
function checkApp([string]$appName, [string]$customIP)
{
    IF([string]::IsNullOrWhiteSpace($customIP)) {
        $targetIP = $ipv4
    }
    else {
        $targetIP = $customIP
    }
    echo y | .\bin\plink -i ssh\${sshKey} root@${targetIP} "command -v ${appName} > /dev/null 2>&1"
    if (-not $?) {
        return $False
    }
    return $True
}

#######################################################################
#
# install application on VM
#
#######################################################################

function installApp([string]$appName, [string]$customIP, [string]$appGitURL, [string]$appGitTag)
{
    # check whether app is already installed
    $retVal = checkApp $appName $customIP
    if ($retVal)
    {
        return $True
    }
    if ($appGitURL -eq $null)
    {
        Write-Output "ERROR: $appGitURL is not set" -ErrorAction SilentlyContinue | Out-File -Append $summaryLog
        return $False
    }
    # app is not installed, install it
    .\bin\plink -i ssh\${sshKey} root@${customIP} "cd /root; git clone $appGitURL $appName > /dev/null 2>&1"

    if ($appGitTag)
    {
        .\bin\plink -i ssh\${sshKey} root@${customIP} "cd  /root/$appName; git checkout tags/$appGitTag > /dev/null 2>&1"
    }
    .\bin\plink -i ssh\${sshKey} root@${customIP} "cd /root/$appName; ./configure > /dev/null 2>&1; make > /dev/null 2>&1; make install > /dev/null 2>&1"

    $retVal = checkApp $appName $customIP
    return $retVal
}

########################################################################
#
# ConvertStringToDecimal()
#
########################################################################
function ConvertStringToDecimal([string] $str)
{
    $uint64Size = $null

    #
    # Make sure we received a string to convert
    #
    if (-not $str)
    {
        Write-Error -Message "ConvertStringToDecimal() - input string is null" -Category InvalidArgument -ErrorAction SilentlyContinue
        return $null
    }

    if ($str.EndsWith("MB"))
    {
        $num = $str.Replace("MB","")
        $uint64Size = ([Convert]::ToDecimal($num)) * 1MB
    }
    elseif ($str.EndsWith("GB"))
    {
        $num = $str.Replace("GB","")
        $uint64Size = ([Convert]::ToDecimal($num)) * 1GB
    }
    elseif ($str.EndsWith("TB"))
    {
        $num = $str.Replace("TB","")
        $uint64Size = ([Convert]::ToDecimal($num)) * 1TB
    }
    else
    {
        Write-Error -Message "Invalid newSize parameter: ${str}" -Category InvalidArgument -ErrorAction SilentlyContinue
        return $null
    }

    return $uint64Size
}

#######################################################################
#
# Check boot.msg in Linux VM for Recovering journal
#
#######################################################################
function CheckRecoveringJ()
{
    $retValue = $False
    $filename = ".\boot.msg"
    $text = "recovering journal"

    echo y | .\bin\pscp -i ssh\${sshKey}  root@${ipv4}:/var/log/boot.* ./boot.msg

    if (-not $?) {
		Write-Output "ERROR: Unable to copy boot.msg from the VM"
		return $False
    }

    $file = Get-Content $filename
    if (-not $file) {
        Write-Error -Message "Error: Unable to read file" -Category InvalidArgument -ErrorAction SilentlyContinue
        return $null
    }

     foreach ($line in $file) {
        if ($line -match $text) {
            $retValue = $True
            Write-Output "$line"
        }
    }

    del $filename
    return $retValue
}


#######################################################################
# Create a file on the VM.
#######################################################################
function CreateFile([string] $fileName)
{
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "touch ${fileName}"
    if (-not $?) {
        Write-Output "ERROR: Unable to create file" | Out-File -Append $summaryLog
        return $False
    }

    return  $True
}

#######################################################################
#
# Delete a file on the VM
#
#######################################################################
function DeleteFile()
{
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "rm -rf /root/1"
    if (-not $?)
    {
        Write-Error -Message "ERROR: Unable to delete test file!" -ErrorAction SilentlyContinue
        return $False
    }

    return  $True
}

#######################################################################
#
# Checks if test file is present or not
#
#######################################################################
function CheckFile([string] $fileName)
{
    $retVal = $true
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "stat ${fileName} 2>/dev/null" | out-null
    if (-not $?) {
        $retVal = $false
    }

    return  $retVal
}

#######################################################################
#
# KvpToDict
#
#######################################################################
function KvpToDict($rawData)
{
    <#
    .Synopsis
        Convert the KVP data to a PowerShell dictionary.

    .Description
        Convert the KVP xml data into a PowerShell dictionary.
        All keys are added to the dictionary, even if their
        values are null.

    .Parameter rawData
        The raw xml KVP data.

    .Example
        KvpToDict $myKvpData
    #>

    $dict = @{}

    foreach ($dataItem in $rawData)
    {
        $key = ""
        $value = ""
        $xmlData = [Xml] $dataItem

        foreach ($p in $xmlData.INSTANCE.PROPERTY)
        {
            if ($p.Name -eq "Name")
            {
                $key = $p.Value
            }

            if ($p.Name -eq "Data")
            {
                $value = $p.Value
            }
        }
        $dict[$key] = $value
    }

    return $dict
}


#######################################################################
# To Get Parent VHD from VM.
#######################################################################
function GetParentVHD($vmName, $hvServer)
{
    $ParentVHD = $null

    $VmInfo = Get-VM -Name $vmName -ComputerName $hvServer
    if (-not $VmInfo) {
       Write-Error -Message "Error: Unable to collect VM settings for ${vmName}" -ErrorAction SilentlyContinue
       return $False
    }

    $vmGen = GetVMGeneration $vmName $hvServer
    if ( $vmGen -eq 1  ) {
        $Disks = $VmInfo.HardDrives
        foreach ($VHD in $Disks) {
            if ( ($VHD.ControllerLocation -eq 0 ) -and ($VHD.ControllerType -eq "IDE"  )) {
                $Path = Get-VHD $VHD.Path -ComputerName $hvServer
                if ([string]::IsNullOrEmpty($Path.ParentPath)) {
                    $ParentVHD = $VHD.Path
                }
                else {
                    $ParentVHD =  $Path.ParentPath
                }

                Write-Host "Parent VHD Found: $ParentVHD "
            }
        }
    }
    if ( $vmGen -eq 2 ) {
        $Disks = $VmInfo.HardDrives
        foreach ($VHD in $Disks) {
            if ( ($VHD.ControllerLocation -eq 0 ) -and ($VHD.ControllerType -eq "SCSI"  )) {
                $Path = Get-VHD $VHD.Path -ComputerName $hvServer
                if ([string]::IsNullOrEmpty($Path.ParentPath)) {
                    $ParentVHD = $VHD.Path
                }
                else {
                    $ParentVHD =  $Path.ParentPath
                }

                Write-Host "Parent VHD Found: $ParentVHD "
            }
        }
    }

    if ( -not ($ParentVHD.EndsWith(".vhd") -xor $ParentVHD.EndsWith(".vhdx") )) {
        Write-Error -Message " Parent VHD is Not correct please check VHD, Parent VHD is: $ParentVHD " -ErrorAction SilentlyContinue
        return $False
    }

    return $ParentVHD
}


function CreateChildVHD($ParentVHD, $defaultpath, $hvServer)
{
    $ChildVHD  = $null
    $hostInfo = Get-VMHost -ComputerName $hvServer
    if (-not $hostInfo) {
        Write-Error -Message "Error: Unable to collect Hyper-V settings for $hvServer" -ErrorAction SilentlyContinue
        return $False
    }

    # Create Child VHD
    if ($ParentVHD.EndsWith("x") ) {
        $ChildVHD = $defaultpath + ".vhdx"
    }
    else {
        $ChildVHD = $defaultpath + ".vhd"
    }

    if ( Test-Path $ChildVHD ) {
        Write-Host "Deleting existing VHD $ChildVHD"
        del $ChildVHD
    }

    # Copy Child VHD
    Copy-Item $ParentVHD $ChildVHD
    if (-not $?) {
        Write-Error -Message "Error: Unable to create child VHD"  -ErrorAction SilentlyContinue
        return $False
    }

    return $ChildVHD
}

# Convert a string to int64 for use with the Set-VMMemory cmdlet
function ConvertToMemSize([String] $memString, [String]$hvServer)
{
    $memSize = [Int64] 0

    if ($memString.EndsWith("MB"))
    {
        $num = $memString.Replace("MB","")
        $memSize = ([Convert]::ToInt64($num)) * 1MB
    }
    elseif ($memString.EndsWith("GB"))
    {
        $num = $memString.Replace("GB","")
        $memSize = ([Convert]::ToInt64($num)) * 1GB
    }
    elseif( $memString.EndsWith("%"))
    {
        $osInfo = Get-WMIObject Win32_OperatingSystem -ComputerName $hvServer
        if (-not $osInfo)
        {
            "Error: Unable to retrieve Win32_OperatingSystem object for server ${hvServer}"
            return $False
        }

        $hostMemCapacity = $osInfo.FreePhysicalMemory * 1KB
        $memPercent = [Convert]::ToDouble("0." + $memString.Replace("%",""))
        $num = [Int64] ($memPercent * $hostMemCapacity)

        # Align on a 4k boundry
        $memSize = [Int64](([Int64] ($num / 2MB)) * 2MB)
    }
    # we received the number of bytes
    else
    {
        $memSize = ([Convert]::ToInt64($memString))
    }

    return $memSize
}

#####################################################################
#
# GetVMGeneration()
#
#####################################################################
function GetVMGeneration([String] $vmName, [String] $hvServer)
{
    <#
    .Synopsis
        Get VM generation type
    .Description
        Get VM generation type from host, generation 1 or generation 2
    .Parameter vmName
        Name of the VM
    .Parameter hvServer
        Name of the server hosting the VM
    .Example
        GetVMGeneration $vmName $hvServer
    #>
    $vmInfo = Get-VM -Name $vmName -ComputerName $hvServer

    # Hyper-V Server 2012 (no R2) only supports generation 1 VM
    if (!$vmInfo.Generation)
    {
        $vmGeneration = 1
    }
    else
    {
        $vmGeneration = $vmInfo.Generation
    }
    return $vmGeneration
}

#######################################################################
#
# GetNumaSupportStatus()
#
#######################################################################
function GetNumaSupportStatus([string] $kernel)
{
    <#
    .Synopsis
        Try to determine whether guest supports NUMA
    .Description
        Get whether NUMA is supported or not based on kernel verison.
        Generally, from RHEL 6.6 with kernel version 2.6.32-504,
        NUMA is supported well.
    .Parameter kernel
        $kernel version gets from "uname -r"
    .Example
        GetNumaSupportStatus 2.6.32-696.el6.x86_64
    #>

    if ( $kernel.Contains("i686") -or $kernel.Contains("i386")) {
        return $false
    }

    if ( $kernel.StartsWith("2.6")) {
        $numaSupport = "2.6.32.504"
        $kernelSupport = $numaSupport.split(".")
        $kernelCurrent = $kernel.replace("-",".").split(".")

        for ($i=0; $i -le 3; $i++) {
            if ($kernelCurrent[$i] -lt $kernelSupport[$i] ) {
                return $false
            }
        }
    }

    # We skip the check if kernel is not 2.6
    # Anything newer will have support for it
    return $true
}



#####################################################################
#
# GetHostBuildNumber
#
#####################################################################
function GetHostBuildNumber([String] $hvServer)
{
    <#
    .Synopsis
        Get host BuildNumber.

    .Description
        Get host BuildNumber.
        14393: 2016 host
        9600: 2012R2 host
        9200: 2012 host
        0: error

    .Parameter hvServer
        Name of the server hosting the VM

    .ReturnValue
        Host BuildNumber.

    .Example
        GetHostBuildNumber
    #>

    [System.Int32]$buildNR = (Get-WmiObject -class Win32_OperatingSystem -ComputerName $hvServer).BuildNumber

    if ( $buildNR -gt 0 )
    {
        return $buildNR
    }
    else
    {
        Write-Error -Message "Get host build number failed" -ErrorAction SilentlyContinue
        return 0
    }
}


#####################################################################
#
# AskVmForTime()
#
#####################################################################
function AskVmForTime([String] $sshKey, [String] $ipv4, [string] $command)
{
    <#
    .Synopsis
        Send a time command to a VM
    .Description
        Use SSH to request the data/time on a Linux VM.
    .Parameter sshKey
        SSH key for the VM
    .Parameter ipv4
        IPv4 address of the VM
    .Parameter command
        Linux date command to send to the VM
    .Output
        The date/time string returned from the Linux VM.
    .Example
        AskVmForTime "lisa_id_rsa.ppk" "192.168.1.101" 'date "+%m/%d/%Y%t%T%p "'
    #>

    $retVal = $null

    $sshKeyPath = Resolve-Path $sshKey

    #
    # Note: We did not use SendCommandToVM since it does not return
    #       the output of the command.
    #
    $dt = .\bin\plink -i ${sshKeyPath} root@${ipv4} $command
    if ($?)
    {
        $retVal = $dt
    }
    else
    {
        LogMsg 0 "Error: $vmName unable to send command to VM. Command = '$command'"
    }

    return $retVal
}


#####################################################################
#
# GetUnixVMTime()
#
#####################################################################
function GetUnixVMTime([String] $sshKey, [String] $ipv4)
{
    <#
    .Synopsis
        Return a Linux VM current time as a string.
    .Description
        Return a Linxu VM current time as a string
    .Parameter sshKey
        SSH key used to connect to the Linux VM
    .Parameter ivp4
        IP address of the target Linux VM
    .Example
        GetUnixVMTime "lisa_id_rsa.ppk" "192.168.6.101"
    #>

    if (-not $sshKey)
    {
        return $null
    }

    if (-not $ipv4)
    {
        return $null
    }

    #
    # now=`date "+%m/%d/%Y/%T"
    # returns 04/27/2012/16:10:30PM
    #
    $unixTimeStr = $null
    $command = 'date "+%m/%d/%Y/%T" -u'

    $unixTimeStr = AskVMForTime ${sshKey} $ipv4 $command
    if (-not $unixTimeStr -and $unixTimeStr.Length -lt 10)
    {
        return $null
    }

    return $unixTimeStr
}


#####################################################################
#
#   GetTimeSync()
#
#####################################################################
function GetTimeSync([String] $sshKey, [String] $ipv4)
{
    if (-not $sshKey)
    {
        return $null
    }

    if (-not $ipv4)
    {
        return $null
    }
    #
    # Get a time string from the VM, then convert the Unix time string into a .NET DateTime object
    #
    $unixTimeStr = GetUnixVMTime -sshKey "ssh\${sshKey}" -ipv4 $ipv4
    if (-not $unixTimeStr)
    {
       "Error: Unable to get date/time string from VM"
        return $False
    }

    $pattern = 'MM/dd/yyyy/HH:mm:ss'
    $unixTime = [DateTime]::ParseExact($unixTimeStr, $pattern, $null)

    #
    # Get our time
    #
    $windowsTime = [DateTime]::Now.ToUniversalTime()

    #
    # Compute the timespan, then convert it to the absolute value of the total difference in seconds
    #
    $diffInSeconds = $null
    $timeSpan = $windowsTime - $unixTime
    if (-not $timeSpan)
    {
        "Error: Unable to compute timespan"
        return $False
    }
    else
    {
        $diffInSeconds = [Math]::Abs($timeSpan.TotalSeconds)
    }

    #
    # Display the data
    #
    "Windows time: $($windowsTime.ToString())"
    "Unix time: $($unixTime.ToString())"
    "Difference: $diffInSeconds"

     Write-Output "Time difference = ${diffInSeconds}" | Tee-Object -Append -file $summaryLog
     return $diffInSeconds
}

#####################################################################
#
#   ConfigTimeSync()
#
#####################################################################
function ConfigTimeSync([String] $sshKey, [String] $ipv4)
{
    #
    # Copying required scripts
    #
    $retVal = SendFileToVM $ipv4 $sshKey ".\remote-scripts\ica\utils.sh" "/root/utils.sh"
    $retVal = SendFileToVM $ipv4 $sshKey ".\remote-scripts\ica\Core_Config_TimeSync.sh" "/root/config_timesync.sh"

    # check the return Value of SendFileToVM
    if ($? -ne "True")
    {
        Write-Output "Error: Failed to send config file to VM."
        $retVal = $False
    }

    $retVal = SendCommandToVM $ipv4 $sshKey "cd /root && dos2unix config_timesync.sh && chmod u+x config_timesync.sh && ./config_timesync.sh"
    if ($? -ne "True")
    {
        Write-Output "Error: Failed to configure time sync. Check logs for details."
        $retVal = $False
    }

    return $retVal
}

function CheckVMState([String] $vmName, [String] $hvServer)
{
    $vm = Get-Vm -VMName $vmName -ComputerName $hvServer
    $vmStatus = $vm.state

    return $vmStatus
}

############################################################################
#
# CreateController
#
# Description
#     Create a SCSI controller if one with the ControllerID does not
#     already exist.
#
############################################################################
function CreateController([string] $vmName, [string] $server, [string] $controllerID)
{
    #
    # Initially, we will limit this to 4 SCSI controllers...
    #
    if ($ControllerID -lt 0 -or $controllerID -gt 3)
    {
        write-output "    Error: Bad SCSI controller ID: $controllerID"
        return $False
    }

    #
    # Check if the controller already exists.
    #
    $scsiCtrl = Get-VMScsiController -VMName $vmName -ComputerName $server
    if ($scsiCtrl.Length -1 -ge $controllerID)
    {
        "Info : SCSI controller already exists"
    }
    else
    {
        $error.Clear()
        Add-VMScsiController -VMName $vmName -ComputerName $server
        if ($error.Count -gt 0)
        {
            "    Error: Add-VMScsiController failed to add 'SCSI Controller $ControllerID'"
            $error[0].Exception
            return $False
        }
        "Info : Controller successfully added"
    }
    return $True
}


function SetIntegrationService([string] $vmName, [string] $hvServer, [string] $serviceName, [boolean] $serviceStatus)
{
    <#
    .Synopsis
        Set the Integration Service status.
    .Description
        Set the Integration Service status based on service name and expected service status.
    .Parameter vmName
        Name of the VM
    .Parameter hvServer
        Name of the server hosting the VM
    .Parameter serviceName
        Service name, e.g. VSS, Guest Service Interface
    .Parameter serviceStatus
        Expected servcie status, $true is enabled, $false is disabled
    .Example
        SetIntegrationService $vmName $hvServer $serviceName $true
    #>
    if (@("Guest Service Interface", "Time Synchronization", "Heartbeat", "Key-Value Pair Exchange", "Shutdown","VSS") -notcontains $serviceName)
    {
        "Error: Unknown service type: $serviceName"
        return $false
    }

    "Info: Set the Integrated Services $serviceName as $serviceStatus"
    if ($serviceStatus -eq $false)
    {
        Disable-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name $serviceName
    }
    else
    {
        Enable-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name $serviceName
    }

    $status = Get-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name $serviceName
    if ($status.Enabled -ne $serviceStatus)
    {
        "Error: The $serviceName service could not be set as $serviceStatus"
        return $False
    }
    return $True
}

function GetSelinuxAVCLog([String] $ipv4, [String] $sshKey)
{
    <#
    .Synopsis
        Check selinux audit.log in Linux VM for avc denied log.
    .Description
        Check audit.log in Linux VM for avc denied log.
        If get avc denied log for hyperv daemons, return $true, else return $false.
    .Parameter ipv4
        IPv4 address of the Linux VM.
    .Parameter sshKey
        SSH key used to connect to the Linux VM
    .Example
        GetSelinuxAVCLog $ipv4 $sshKey
    #>
    $filename = ".\audit.log"
    $text_hv = "hyperv"
    $text_avc = "type=avc"
    echo y | .\bin\pscp -i ssh\${sshKey}  root@${ipv4}:/var/log/audit.log $filename

    if (-not $?) {
        Write-Output "ERROR: Unable to copy audit.log from the VM"
        return $False
    }

    $file = Get-Content $filename
    if (-not $file) {
        Write-Error -Message "Error: Unable to read file" -Category InvalidArgument -ErrorAction SilentlyContinue
        return $null
    }

     foreach ($line in $file) {
        if ($line -match $text_hv -and $line -match $text_avc){
            write-output "Warning: get the avc denied log: $line"
            return $True
        }
    }
    del $filename
    return $False
}

function GetVMFeatureSupportStatus([String] $ipv4, [String] $sshKey, [String]$supportKernel)
{
    <#
    .Synopsis
        Check if VM supports one feature or not.
    .Description
        Check if VM supports one feature or not based on comparison of curent kernel version with feature
        supported kernel version. If the current version is lower than feature supported version, return false, otherwise return true.
    .Parameter ipv4
        IPv4 address of the Linux VM.
    .Parameter sshKey
        SSH key used to connect to the Linux VM.
    .Parameter supportkernel
        The kernel version number starts to support this feature, e.g. supportkernel = "3.10.0.383"
    .Example
        GetVMFeatureSupportStatus $ipv4 $sshKey $supportkernel
    #>
    echo y | bin\plink.exe -i ssh\${sshKey} root@${ipv4} 'exit 0'
    $currentKernel = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "uname -r"
    if( $? -eq $false){
        Write-Output "Warning: Could not get kernel version".
    }
    $sKernel = $supportKernel.split(".-")
    $cKernel = $currentKernel.split(".-")

    for ($i=0; $i -le 3; $i++) {
        if ($cKernel[$i] -lt $sKernel[$i] ) {
            $cmpResult = $false
            break;
        }
        if ($cKernel[$i] -gt $sKernel[$i] ) {
            $cmpResult = $true
            break
        }
        if ($i -eq 3) { $cmpResult = $True }
    }
    return $cmpResult
}

# Function for starting dependency VMs used by test scripts
function StartDependencyVM([String] $dep_vmName, [String] $server, [int]$tries)
{
    if (Get-VM -Name $dep_vmName -ComputerName $server |  Where { $_.State -notlike "Running" })
    {
        [int]$i = 0
        # Try to start dependency VM
        for ($i=0; $i -lt $tries; $i++)
        {
            Start-VM -Name $dep_vmName -ComputerName $server -ErrorAction SilentlyContinue
            if (-not $?)
            {
                "Warning: Unable to start VM $dep_vmName on attempt $i"
            }
            else
            {
                $i = 0
                break
            }

            Start-Sleep -s 30
        }

        if ($i -ge $tries)
        {
            "Error: Unable to start VM $dep_vmName after $tries attempts" | Tee-Object -Append -file $summaryLog
            return $false
        }
    }

    # just to make sure vm2 started
    if (Get-VM -Name $dep_vmName -ComputerName $server |  Where { $_.State -notlike "Running" })
    {
        "Error: $dep_vmName never started."
        return $false
    }
}

# Function that will check for Call Traces on VM after 2 minutes
# This function assumes that check_traces.sh is already on the VM
function CheckCallTracesWithDelay ([String]$sshKey, [String]$ipv4)
{
    .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "dos2unix -q check_traces.sh && echo 'sleep 5 && bash ~/check_traces.sh ~/check_traces.log &' > runtest.sh"
    .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "bash runtest.sh > check_traces.log 2>&1"
    Start-Sleep -s 120
    $ErrorActionPreference = 'silentlycontinue'
    $sts = .\bin\plink.exe -i ssh\$sshKey root@${ipv4} "cat ~/check_traces.log | grep ERROR"
    if ($sts.Contains("ERROR")) {
        return $false 
    }
    if ($sts -eq $NULL) {
        return $true
    }
}

# ScriptBlock used for Dynamic Memory test cases
$DM_scriptBlock = {
  # function for starting stresstestapp
  function ConsumeMemory([String]$conIpv4, [String]$sshKey, [String]$rootDir, [int]$timeoutStress, [int64]$memMB, [int]$duration, [int64]$chunk)
  {

  # because function is called as job, setup rootDir and source TCUtils again
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
    "Sourced TCUtils.ps1"
  }
  else
  {
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
  }

      $cmdToVM = @"
#!/bin/bash
        if [ ! -e /proc/meminfo ]; then
          echo ConsumeMemory: no meminfo found. Make sure /proc is mounted >> /root/HotAdd.log 2>&1
          exit 100
        fi

        rm ~/HotAddErrors.log -f
        dos2unix check_traces.sh
        chmod +x check_traces.sh
        ./check_traces.sh ~/HotAddErrors.log &

        __totalMem=`$(cat /proc/meminfo | grep -i MemTotal | awk '{ print `$2 }')
        __totalMem=`$((__totalMem/1024))
        echo ConsumeMemory: Total Memory found `$__totalMem MB >> /root/HotAdd.log 2>&1
        declare -i __chunks
        declare -i __threads
        declare -i duration
        declare -i timeout
        if [ $chunk -le 0 ]; then
            __chunks=128
        else
            __chunks=512
        fi
        __threads=`$(($memMB/__chunks))
        if [ $timeoutStress -eq 0 ]; then
            timeout=10000000
            duration=`$((10*__threads))
        elif [ $timeoutStress -eq 1 ]; then
            timeout=5000000
            duration=`$((5*__threads))
        elif [ $timeoutStress -eq 2 ]; then
            timeout=1000000
            duration=`$__threads
        else
            timeout=1
            duration=30
            __threads=4
            __chunks=2048
        fi

        if [ $duration -ne 0 ]; then
            duration=$duration
        fi
        echo "Stress-ng info: `$__threads threads :: `$__chunks MB chunk size :: `$((`$timeout/1000000)) seconds between chunks :: `$duration seconds total stress time" >> /root/HotAdd.log 2>&1
        stress-ng -m `$__threads --vm-bytes `${__chunks}M -t `$duration --backoff `$timeout
        echo "Waiting for jobs to finish" >> /root/HotAdd.log 2>&1
        wait
        exit 0
"@

    #"pingVMs: sendig command to vm: $cmdToVM"
    $filename = "ConsumeMem.sh"

    # check for file
    if (Test-Path ".\${filename}")
    {
      Remove-Item ".\${filename}"
    }

    Add-Content $filename "$cmdToVM"

    # send file
    $retVal = SendFileToVM $conIpv4 $sshKey $filename "/root/${$filename}"

    # check the return Value of SendFileToVM
    if (-not $retVal[-1])
    {
      return $false
    }

    # execute command as job
    $retVal = SendCommandToVM $conIpv4 $sshKey "cd /root && chmod u+x ${filename} && sed -i 's/\r//g' ${filename} && ./${filename}"

    return $retVal
  }
}
