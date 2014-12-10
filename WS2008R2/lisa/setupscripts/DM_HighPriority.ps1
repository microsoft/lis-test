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
       Test that two VMs under stress, the VM with the higher priority
   receives more assigned memory.  The test case definition lists
   the following steps:
       Create 2 VMs, one high priority (VM1), on low priority (VM2).
       Configure VMs MAX and Startup memory of 30% of system free memory.
       Start both VMs
       Apply same pressure to both VMs
       Let demand and dynamic memory settle
       Start a third VM to exhaust memory
       Run under 0 Balancer memory for a bit
   Expected results:
       Higher priority VM should have more assigned memory.

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
            return $false
        }

        if ($vm.MemoryDemand -and $vm.MemoryDemand -gt 0)
        {
            return $True
        }

        $waitTimeOut -= 5  # Note - Test Port will sleep for 5 seconds
        Start-Sleep -s 5
    }

    return $retVal
}


#######################################################################
#
# CopyScriptToVM()
#
# Description:
#    Copy a script to a VM.  Then run dos2unix to convert the EOL
#    characters and set the execute bit.
#
#######################################################################
function CopyScriptToVM([String] $ipv4, [String] $sshKey, [String] $localName, [String] $remoteName)
{
    echo y | .\bin\plink -i ssh\${sshKey} root@${ipv4} "exit"

    .\bin\pscp.exe -i ssh\${sshKey} $localName root@${ipv4}:${remoteName}
    if (-not $?)
    {
        "Error: Unable to copy script ${localName} to ${ipv4}"
        return $False
    }

    .\bin\plink -i ssh\${sshKey} root@${ipv4} "dos2unix ${remoteName}  2> /dev/null"
    if (-not $?)
    {
        "Error: Unable to run dos2unix on script ${remoteName}"
        return $False
    }

    .\bin\plink -i ssh\${sshKey} root@${ipv4} "chmod 755 ${remoteName}  2> /dev/null"
    if (-not $?)
    {
        "Error: Unable to chmod 755 ${remoteName}"
        return $False
    }

    return $True
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
function RunStressAppTestOnVM([String] $vmName, [String] $ipv4, [String] $sshKey, [String] $server, [string] $gbToAllocate, [int] $seconds = 60)
{
    echo y | .\bin\plink -i ssh\${sshKey} root@${ipv4} "exit"

    #
    # Create the startstress.sh script and copy it to the VM
    #    growDemand.sh gbToAllocate timeout
    #
    "~/growDemand.sh ${gbToAllocate} ${seconds}" | out-file -encoding ASCII -filepath startstress.sh
    .\bin\pscp -i ssh\${sshKey} .\startstress.sh root@${ipv4}:
    if (-not $?)
    {
        "Error: Unable to copy staratstress.sh to the VM"
        del startstress.sh -ErrorAction SilentlyContinue
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

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "at -f startstress.sh now 2> /dev/null"
    if (-not $?)
    {
        "Error: Unable to submit startstress to atd"
        return $False
    }

    return $True
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

#
# display the test params in the log
#
"Test Params: ${testParams}"

$sshKey  = $null
$ipv4    = $null
$vm2Name = $null
$vm2ipv4 = $null
$vm3Name = $null

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    switch ($fields[0].Trim())
    {
    "vm2Name" { $vm2Name = $fields[1].Trim() }
    "SshKey"  { $sshKey  = $fields[1].Trim() }
    "ipv4"    { $ipv4    = $fields[1].Trim() }
    "vm3"     { $vm3Name = $fields[1].Trim() }
	"rootdir" { $rootDir = $fields[1].Trim() }
    default   {}  # unknown param - just ignore it
    }
}

#
# Make sure all required test parameters were found
#
if (-not $vm2Name)
{
    "Error: test parameter vm2Name was not specified"
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

if (-not $vm3Name)
{
    "Error: test parameter vm3Name was not specified"
    return $False
}

#
# display the parsed test params in the log
#
"sshKey   = ${sshKey}"
"ipv4     = ${ipv4}"
"vm1 Name = ${vmName}"
"vm2 Name = ${vm2Name}"
"vm2 ipv4 = ${vm2ipv4}"
"vm3 Name = ${vm3Name}"

#
# Change the working directory to where we need to be
#
if ($rootDir)
{
    if (-not (Test-Path $rootDir))
    {
        "Error: The directory `"${rootDir}`" does not exist"
        return $False
    }

    cd $rootDir
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

echo "Verifies DM 2.3.7 High Priority" > ./${vmName}_summary.log

#
# Wait for hv_balloon to start reporting memory demand
#
#"Info : Waiting for VM ${vmName} to start reporting memory demand"
#$timeout = 180
#if (-not (WaitForVMToReportDemand $vmName $hvServer $timeout))
#{
#    "Error: VM ${vmName} never reported memorydemand"
#    return $False
#}

#
# ICA started VM1, so start VM2
#
"Info : Starting vm ${vm2name}"
Start-VM -Name $vm2Name -ComputerName $hvServer
if (-not $?)
{
    "Error: Unable to start VM ${vm2Name}"
    return $False
}

$timeout = 120    # in seconds
"Info : Waiting for VM ${vm2name} to report memory demand"
if (-not (WaitForVMToReportDemand $vm2Name $hvServer $timeout))
{
    "Error: VM ${vm2Name} never started KVP"
    Stop-VM -Name $vm2Name -ComputerName $hvServer -Force -TurnOff
    return $False
}

$vm2ipv4 = GetIpv4ViaKVP $vm2Name $hvServer
if (-not $vm2ipv4)
{
    "Error: Unable to get IPv4 for VM ${vm2Name}"
    Stop-VM -Name $vm2Name -ComputerName $hvServer -Force -TurnOff
    return $False
}

#
# Make sure the growDemand.sh script is on VM2
#
$scriptName = "remote-scripts\ica\growDemand.sh"
$remoteName = "growDemand.sh"
if (-not (CopyScriptToVM $vm2ipv4 $sshKey $scriptName $remoteName))
{
    "Error: Unable to copy ${scriptName} to VM ${vm2Name}"
    Stop-VM -Name $vm2Name -ComputerName $hvServer -Force -TurnOff
    return $False
}

#
# Make sure the script is also on VM1
#
if (-not (CopyScriptToVM $ipv4 $sshKey $scriptName $remoteName))
{
    "Error: Unable to copy ${scriptName} to VM ${vm2Name}"
    Stop-VM -Name $vm2Name -ComputerName $hvServer -Force -TurnOff
    return $False
}

#
# Sleep a bit to let the Dynamic memory system settle
#
$timeout = 60
Start-Sleep -S $timeout

#
# Start a stress tool on both VM1 and VM2
#
$demandInGB = 4
$stresstime = 300
"Info : RunStressAppTestOnVM $vmName $ipv4 $sshkey $hvserver $demandInGB $stressTime"
if (-not (RunStressAppTestOnVM $vmName $ipv4 $sshKey $hvServer $demandInGB $stressTime))
{
    "Error: Unable to start the stress tool on ${vmname}"
    return $False
}

"Info : RunStressAppTestOnVM $vm2Name $vm2ipv4 $sshkey $hvserver $demandInGB $stressTime"
if (-not (RunStressAppTestOnVM $vm2Name $vm2ipv4 $sshKey $hvServer $demandInGB $stressTime))
{
    "Error: Unable to start the stress tool on ${vm2name}"
    return $False
}

#
# Wait a bit for things to settle out, then see if VM1 has more assigned
# memory than VM2
#
"Info : Sleeping a bit to let the system settle out"
$timeout = 60
Start-Sleep -S $timeout

#
# Configure VM3 to exhaust memory
#
$balancerMem = (Get-Counter -Counter "\hyper-V Dynamic Memory Balancer(*)\Available Memory" -ComputerName $hvServer).CounterSamples.CookedValue
if ($balancerMem % 2 -ne 0)
{
    #
    # 2MB align memory
    #
    $balancerMem += 1
}
$memorySize = $balancerMem * 1024 * 1024

"Balancer memory = ${balancerMem}"
"MemorySize      = ${memorySize}"

Set-VMMemory -VMName $vm3Name -MaximumBytes $memorySize -StartupBytes $memorySize -Priority 0 -ComputerName $hvServer

"Info : Starting vm ${vm3name} to exhaust memory"
Start-VM -Name $vm3Name -ComputerName $hvServer
if (-not $?)
{
    "Error: Unable to start VM ${vm3Name}"
    Stop-VM -Name $vm3Name -ComputerName $hvServer -Force -TurnOff
    Stop-VM -Name $vm2Name -ComputerName $hvServer -Force -TurnOff
    return $False
}

#
# Let things settle out a bit...
#
$timeout = 30
Start-Sleep -S $timeout

#
# Collect VM info
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

#
# Stop VM3
#
Stop-VM -Name $vm3Name -ComputerName $hvServer -Force -TurnOff

#
# Display the metrics
#
$vm1Assigned = $vm1.MemoryAssigned
$vm2Assigned = $vm2.MemoryAssigned
$difference  = $vm1Assigned - $vm2Assigned

"High priority VM should have more memory assigned"
"VM1 assigned memory = {0,14}" -f $vm1Assigned
"VM2 assigned memory = {0,14}" -f $vm2Assigned
"Difference          = {0,14}" -f $difference

$retVal = $False
$msg = "Test Failed"

if ($vm1Assigned -ge $vm2Assigned)
{
    $retVal = $True
    $msg = "Test Passed"
}

#
# Log a message about our test results
#
$msg

#
# Turn off VM2 since ICA does not know about it.
# Due to bug in Linux kernel, use init 0 for now.
#
.\bin\plink -i ssh\${sshKey} root@${vm2ipv4} "init 0"
if (-not $?)
{
    "Error: Unable to init 0 ${vm2Name}"
    Stop-VM -Name $vm2Name -ComputerName $hvServer -Force -TurnOff
}

return $retVal
