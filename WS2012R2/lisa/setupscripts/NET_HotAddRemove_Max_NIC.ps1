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
    Run the Hot Add Remove Max NIC test case.

.Description
    This test script will hot add 7 synthetic NICs to a running Gen 2 VM.

    The logic of the script is:
        Process the test parameters.
        Ensure required test parameters were provided.
        Ensure the target VM exists and is a Gen 2 VM
        Ensure the VM has a single NIC
        Hot add 7 NICs
				Run the NET_MAX_NIC.sh on the VM.  The script checks if all 8 NICs
					are visible on the VM and tests each one for connection
				Remove NICs and run the NET_VerifyHotAddMultiNIC.sh on the VM
					to check if there is only on NIC left visible
        Check VM log for errors

    A sample LISA test case definition would look similar to the following:

    <test>
        <testName>HotAddRemoveMaxNIC</name>
        <setupScript>
            <file>setupscripts\RevertSnapshot.ps1</file>
        </setupScript>
        <testScript>setupscripts\NET_HotAddRemove_Max_NIC.ps1</testScript>
        <files>remote-scripts\ica\NET_MAX_NIC.sh, remote-scripts/ica/NET_VerifyHotAddMultiNIC.sh,
				remote-scripts/ica/utils.sh</files>
        <onError>Continue</onError>
        <timeout>1800</timeout>
        <testParams>
            <param>TC_Covered=NET-23</param>
            <param>TEST_TYPE=synthetic</param>
						<param>Switch_Nane=external</param>
        </testParams>
    </test>
#>

param( [String] $vmName, [String] $hvServer, [String] $testParams )

function GetIPv4List( [String] $vmName, [String] $server )
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


function AddRemoveMaxNIC ( [String] $vmName, [String] $hvServer, [String] $network_type, [String] $actionType, [int] $nicsAmount )
{
	for ($i=1; $i -le $nicsAmount; $i++)
	{
		$nicName = "External" + $i

		if ($actionType -eq "add")
		{
			"Info : Ensure the VM does not have a Synthetic NIC with the name '${nicName}'"
			$nics = Get-VMNetworkAdapter -vmName $vmName -Name "${nicName}" -ComputerName $hvServer -ErrorAction SilentlyContinue
			if ($?)
			{
				Throw "Error: VM '${vmName}' already has a NIC named '${nicName}'"
			}
		}

		"Info : Hot '${actionType}' a synthetic NIC with name of '${nicName}' using switch '${switchName}'"
		"Info : Hot '${actionType}' '${network_type}' to '${vmName}'"
		if ($actionType -eq "add")
		{
			Add-VMNetworkAdapter -VMName $vmName -SwitchName $network_type -ComputerName $hvServer -Name ${nicName} #-ErrorAction SilentlyContinue
		}
		else
		{
			Remove-VMNetworkAdapter -VMName $vmName -Name "${nicName}" -ComputerName $hvServer -ErrorAction SilentlyContinue
		}
		if (-not $?)
		{
			Throw "Error: Unable to Hot '${actionType}' NIC to VM '${vmName}' on server '${hvServer}'"
		}
	}
}


########################################################################
#
# Main script body
#
########################################################################
try
{
    #
    # Make sure all command line arguments were provided
    #
    if (-not $vmName)
    {
        Throw "Error: vmName argument is null"
    }

    if (-not $hvServer)
    {
        Throw "Error: hvServer argument is null"
    }

    if (-not $testParams)
    {
        Throw "Error: testParams argument is null"
    }

    #
    # Parse the testParams string
    #
    "Info : Parsing test parameters"
    $sshKey     = $null
    $ipv4       = $null
    $rootDir    = $null
    $tcCovered  = "NET-??"
    $switchName = "External"
    $testLogDir = $null
	$nicsAmount = 7

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
        "Switch_Name"   { $switchName  = $val }
		"SYNTHETIC_NICS"{ $nicsAmount  = $val -as [int] }
        default         { continue }
        }
    }

    #
    # Display the test parameters in the log file
    #
    "Info : Test parameters"
    "         sshKey     = ${sshKey}"
    "         ipv4       = ${ipv4}"
    "         rootDir    = ${rootDir}"
    "         tcCovered  = ${tcCovered}"
    "         testLogDir = ${testLogDir}"
    "         SwitchName = ${switchName}"
    "         nicsAmount = ${nicsAmount}"

    #
    # Change the working directory to where we should be
    #
    if (-not $rootDir)
    {
        Throw "Error: The roodDir parameter was not provided by LISA"
    }

    if (-not (Test-Path $rootDir))
    {
        Throw "Error: The directory `"${rootDir}`" does not exist"
    }

    "Info : Changing directory to '${rootDir}'"
    cd $rootDir

    #
    # Make sure the required testParams were found
    #
    "Info : Verify required test parameters were provided"
    if (-not $sshKey)
    {
        Throw "Error: testParams is missing the sshKey parameter"
    }

    if (-not (Test-Path ssh\${sshKey}))
    {
        Throw "Error: The SSH key 'ssh\${sshKey}' does not exist"
    }

    if (-not $ipv4)
    {
        Throw "Error: The ipv4 parameter was not provided by LISA"
    }

    #
    # Delete any summary.log from a previous test run, then create a new file
    #
    $summaryLog = "${vmName}_summary.log"
    del $summaryLog -ErrorAction SilentlyContinue
    "Info : Covers ${tcCovered}" >> $summaryLog

    #
    # Source the utility functions so we have access to them
    #
    #. .\setupscripts\TCUtils.ps1

    #
    # Eat any Putty prompts asking to save the server key
    #
    echo y | bin\plink.exe -i ssh\${sshKey} root@${ipv4} exit

    #
    # Verify the target VM exists, and that it is a Gen2 VM
    #
    "Info : Verify the SUT VM exists"
    $vm = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $?)
    {
        Throw "Error: Unable to find VM '${vmName}' on server '${hvServer}'"
    }

    if ($vm.Generation -ne 2)
    {
        Throw "Error: This test requires a Gen 2 VM. VM '${vmName}' is not a Gen2 VM"
    }

    #
    # Verify Windows Server version
    #
    $osInfo = GWMI Win32_OperatingSystem -ComputerName $hvServer
    if (-not $osInfo)
    {
        Throw "Error: Unable to collect Operating System information"
    }
    if ($osInfo.BuildNumber -le 10000)
    {
        Throw "Error: This test requires Windows Server 2016 or higher"
    }

		#
		#	Hot Add maximum number of synthetic NICs
		#
		AddRemoveMaxNIC $vmName $hvServer $switchName "add" $nicsAmount

    #
    # Run the NET_MAX_NIC.sh on the SUT VM to verify the VM detected the hot add
    #
    "Info : Verify the OS on the SUT detected the NIC"
    $sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix NET_MAX_NIC.sh 2>&1"
    $sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod 755 NET_MAX_NIC.sh 2>&1"
    $sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "./NET_MAX_NIC.sh added 2>&1"
    if (-not $?)
    {
		$msg = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "tail -n 1 summary.log"
		$vm_log = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "tail -n+2 summary.log" | %{$_.Split('\n')}
		$vm_log = $vm_log -join "`n"
		"${vm_log}"
        Throw "${msg}"
    }

    #
    # Display the output from NET_MAX_NIC.sh so it is captured in the log file
    #
    "Info : Output from NET_MAX_NIC.sh"
    $sts
	#
	# Check if KVP IP values match the ones present in the VM
	#
	"Info : Checking KVP values for each NIC"
	# Wait for KVP to get updated
	Start-Sleep -s 30
	$kvp_ip = GetIPv4List $vmName $hvServer | select -uniq
	$vm_ip = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "ip -4 -o addr show scope global | awk '{print `$4}'" | %{$_.Split('\n')} | %{ $_.Split('/')[0]; }



	if ($kvp_ip.length -ne $vm_ip.length)
	{
		$msg = "Error : IP values sent through KVP are not the same as the ones from the VM"
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
    # Now Hot Remove the NIC
    #
    AddRemoveMaxNIC $vmName $hvServer $switchName "remove" $nicsAmount

    #
    # Run the NET_VerifyHotAddSyntheticNIC.sh on the SUT VM to verify the VM detected the hot remove
    #
    "Info : Verify the OS on the SUT detected the NIC was hot removed"
	$sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix NET_VerifyHotAddMultiNIC.sh removed 2>&1"
	$sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod 755 NET_VerifyHotAddMultiNIC.sh removed 2>&1"
    $sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "./NET_VerifyHotAddMultiNIC.sh removed 2>&1"
    if (-not $?)
    {
        "${sts}"
        Throw "Error: Unable to verify NIC was removed within the SUT VM '${vmName}'"
    }

    #
    # Display the output from NET_VerifyHotAddMultiNIC.sh so it is captured in the log file
    #
    "Info : Output from NET_VerifyHotAddMultiNIC.sh"
    $sts

    if ($sts -match "netvsc throwed errors"){
        Throw "Error: VM '${vmName}' reported that netvsc throwed errors"
    }
}
catch
{
    $msg = $_.Exception.Message
    "Error: ${msg}"
    "${msg}" >> $summaryLog
    return $False
}

#
# If we made it here, everything worked
#
"Info : Test completed successfully"

return $True
