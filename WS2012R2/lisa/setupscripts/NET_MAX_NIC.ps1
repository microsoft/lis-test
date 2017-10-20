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
Wrap test scripts for max NIC cases.

.Description
This test script will run the MaxSyntheticNIC, MaxLegacyNIC, and MaxNIC
test cases.

The logic of the script is:
Process the test parameters.
Ensure required test parameters were provided.
Run the NET_MAX_NIC.sh on the VM.  The script does the following
Check if all added NICs are visible
Bring up and test connection for each interface
Test connection again when all interfaces are up
Compare the IP values from KVP with the ones extracted manually from the VM

A sample LISA test case definition would look similar to the following:

<test>
<testName>MaxNIC</name>
<setupScript>
<file>setupscripts\RevertSnapshot.ps1</file>
<file>setupscripts\NET_Add_Max_NIC.ps1</file>
</setupScript>
<testParams>
<param>TC_COVERED=NET-22</param>
<param>TEST_TYPE=synthetic, legacy</param>
<param>NETWORK_TYPE=external</param>
</testParams>
<testScript>setupscripts\NET_MAX_NIC.ps1</testScript>
<files>remote-scripts/ica/NET_MAX_NIC.sh,remote-scripts/ica/utils.sh</files>
<timeout>800</timeout>
</test>
#>
param( [String] $vmName, [String] $hvServer, [String] $testParams )
Set-PSDebug -Strict

function GetIPv4List( [String] $vmName, [String] $server)
{
    <#
    .Synopsis
    Get an array with IPv4 addresses from KVP
    .Description
    Get an array with IPv4 addresses from KVP
    .Parameter vmName
    Name of the VM
    .Parameter server
    Name of the server hosting the VM
    .Example
    GetIpv4List"myTestVM" "localhost"
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
    $addresses_list = @()
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
                    $addresses_list += $addr
                }
            }
        }
    }

    return $addresses_list

}


########################################################################
#
# Main script body
#
########################################################################

#
# Make sure all command line arguments were provided
#
if (-not $vmName)
{
    "Error: vmName argument is null"
    return $False
}

if (-not $hvServer)
{
    "Error: hvServer argument is null"
    return $False
}

if (-not $testParams)
{
    "Error: testParams argument is null"
    return $False
}

"Info : Parsing test parameters"
$params = $testParams.Split(";")
foreach($p in $params)
{
    $tokens = $p.Trim().Split("=")
    if ($tokens.Length -ne 2)
    {
        continue   # Just ignore the parameter
    }

    $val = $tokens[1].Trim()

    switch($tokens[0].Trim().ToLower())
    {
        "ipv4"          { $ipv4        = $val }
        "sshkey"        { $sshKey      = $val }
        "rootdir"       { $rootDir     = $val }
        "TC_COVERED"    { $tcCovered   = $val }
        "TestLogDir"    { $testLogDir  = $val }
        "LEGACY_NICS"   { $legacyNICs  = $val }

        default         { continue }
    }
}

#
# Change the working directory to where we should be
#
if (-not $rootDir)
{
    "Error: The roodDir parameter was not provided by LISA"
    return $False
}

if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

"Info : Changing directory to '${rootDir}'"
cd $rootDir

if (Test-Path ".\setupScripts\TCUtils.ps1")
{
    . .\setupScripts\TCUtils.ps1
}
else
{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $False
}
#
# Make sure the required testParams were found
#
"Info : Verify required test parameters were provided"
if (-not $sshKey)
{
    "Error: testParams is missing the sshKey parameter"
    return $False
}

if (-not (Test-Path ssh\${sshKey}))
{
    "Error: The SSH key 'ssh\${sshKey}' does not exist"
    return $False
}

if (-not $ipv4)
{
    "Error: The ipv4 parameter was not provided by LISA"
    return $False
}


$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers: ${tcCovered}" | Tee-Object -Append -file $summaryLog

#skip for generation 2
$vmGeneration = GetVMGeneration $vmName $hvServer
if ($legacyNICs -ge 1 -and $vmGeneration -eq 2 )
{
     $msg = "Warning: Generation 2 VM does not support LegacyNetworkAdapter, skip test"
     Write-Output $msg | Tee-Object -Append -file $summaryLog
     return $Skipped
}

# Check for tulip driver. If it's not preset test will be skipped
if ($legacyNICs -ge 1)
{
    $sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "cat /boot/config-`$(uname -r) | grep 'CONFIG_NET_TULIP=y\|CONFIG_TULIP=m'"
    if (-not $sts){
        $msg = "Warning: Tulip driver is not configured! Test skipped"
        Write-Output $msg | Tee-Object -Append -file $summaryLog
        return $Skipped   
    }
}

"Info : Executing bash script"
[int]$hostBuildNumber = (Get-WmiObject -class Win32_OperatingSystem -ComputerName $hvServer).BuildNumber
if ($hostBuildNumber -le 9200) {
	$sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "sed -i 's/NICS=7/NICS=2/g' constants.sh"
}

$sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix NET_MAX_NIC.sh 2>/dev/null"
$sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod 755 NET_MAX_NIC.sh 2>/dev/null"
$sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "./NET_MAX_NIC.sh 2>/dev/null"
if (-not $?)
{
    $msg = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "tail -n 1 summary.log"
    $vm_log = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "tail -n+2 summary.log" | %{$_.Split("`n")}
    $vm_log = $vm_log -join "`n"
    "${vm_log}"
    Write-Output $msg | Tee-Object -Append -file $summaryLog
    return $False
}


#
# Check if KVP IP values match the ones present in the VM
#
"Info: Checking KVP values for each NIC"
# Wait for KVP to get updated
Start-Sleep -s 30
$kvp_ip = GetIPv4List $vmName $hvServer | select -uniq
$vm_ip = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "ip -4 -o addr show scope global | awk '{print `$4}'" | %{$_.Split('\n')} | %{ $_.Split('/')[0]; }



if ($kvp_ip.length -ne $vm_ip.length)
{
    $msg = "IP values sent through KVP are not the same as the ones from the VM"
    "Error : ${msg}"
    "		 KVP values : ${kvp_ip}"
    "		 VM values : ${vm_ip}"
    Write-Output $msg | Tee-Object -Append -file $summaryLog
    return $False
}

foreach ($ip in $vm_ip)
{
    if (-not $kvp_ip -contains $ip)
    {
        $msg = "IP values sent through KVP are not the same as the ones from the VM"
        "Error : ${msg}"
        "		 KVP values : $kvp_ip"
        "		 VM values : $vm_ip"
        Write-Output $msg | Tee-Object -Append -file $summaryLog
        return $False
    }
}

#
# If we made it here, everything worked
#
"Info : Test completed successfully"
Write-Output "Test completed successfully" | Tee-Object -Append -file $summaryLog
return $True
