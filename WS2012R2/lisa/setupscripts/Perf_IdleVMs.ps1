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
    Check CPU utilization of idle VMs.

.Description
    Create a number of Linux VMs.  Do not start a workload on the
    VMs.  Let them sit idle for TEST_DELAY seconds and then check
    the CPU utilization on each VM.

    The XML test case definition for this script would look similar
    to the following:

        <test>
            <testName>Perf_Idle_VMs</testName>
            <testScript>SetupScripts\Perf_IdleVMs.ps1</testScript>
            <timeout>600</timeout>
            <onError>Continue</onError>
            <noReboot>True</noReboot>
            <testparams>
                <param>rootDir=D:\lisa\trunk\lisablue</param>
                <param>TC_COVERED=PERF-99</param>
                <param>VM_PREFIX=IDLE_</param>
                <param>SWITCH_NAME=External</param>
                <param>TEST_DELAY=600</param>
                <param>IDLE_VM_COUNT=30</param>
                <param>parentVHD=D:\HyperV\ParentVHDs\sles11sp3x64.vhd</param>
            </testparams>
        </test>

    Test parameters
        TestDelay
            Default is 0.  This parameter is optional.
            Specifies a time in seconds, to sleep before
            checking the VMs CPU utilization.

        TC_COVERED
            Required.
            Identifies the test case this test covers.

        RootDir
            Required.
            PowerShell test scripts are run as a PowerShell job.
            When a PowerShell job runs, the current directory
            will not be correct.  This specifies the directory
            that should be the current directory for the test.

.Parameter vmName
    Name of the VM to test.

.Parameter  hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter  testParams
    A string with test parameters.

.Example
    .\Perf_IdleVMs.ps1 -vmName "myVM" -hvServer "myServer" -testParams "sshKey=lisa_id_rsa.ppk;rootDir=D:\lisa\trunk\lisablue"
#>



param ([String] $vmName, [String] $hvServer, [String] $testParams)


#######################################################################
#
# StopAndDeleteDensityVMs()
#
# Description:
#     This VM will stop all density VMs, then delete them.
#
#######################################################################
function StopAndDeleteDensityVMs([String] $vmPrefix, [String] $hvServer)
{
    $VMs = Get-VM -Name ($vmPrefix + "*") -ComputerName $hvServer -ErrorAction SilentlyContinue

    foreach ($vm in $VMs)
    {
        if ($vm.State -ne "Off")
        {
            Stop-VM -Name $vm.Name -TurnOff -Force -ComputerName $hvServer -ErrorAction SilentlyContinue
        }

        $vmDir = $vm.Path
        $sts = Remove-VM -Name $vm.Name -Force -ComputerName $hvServer -ErrorAction SilentlyContinue

        #
        # To do - Add support for a directory on a remote server
        #
        $sts = Remove-Item $vm.Path -Recurse -Force -ErrorAction SilentlyContinue
        if (-not $?)
        {
            Write-Error -Message "Unable to delete directory $($vm.Path)" -Category InvalidArgument -ErrorAction SilentlyContinue
            return $False
        }
    }

    return $True
}


#######################################################################
#
# CreateVMs
#
# Description:
#    Loop creating VMs.
#######################################################################
function CreateVMs([String] $vmPrefix, [String] $parentVHD, [String] $switchName, [String] $hvServer, [int] $vmCount)
{
    $hostInfo = Get-VMHost -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $hostInfo)
    {
        $msg = $error[0].Exception.Message
        Write-Error "Unable to collect VM Host information : ${msg}" -Category InvalidData -ErrorAction SilentlyContinue
        return $False
    }

    $vmPath = $hostInfo.VirtualMachinePath
    if (-not ($vmPath.EndsWith("\")))
    {
        $vmPath += "\"
    }

    $numVMs = $vmCount
    for ($i = 0; $i -lt $numVMs; $i++)
    {
        $vmName = "${vmPrefix}_{0:000}" -f $i

        $newVM = New-VM -Name $vmName -path $vmPath -ComputerName $hvServer -ErrorAction SilentlyContinue
        if (-not $newVM)
        {
            $msg = $error[0].Exception.Message
            Write-Error -Message "Unable to create VM ${vmName} : ${msg}" -Category InvalidArgument -ErrorAction SilentlyContinue
            return $False
        }

        #
        # Create a differencing disk to boot the VM and add it to the VM
        #
        $vhdxPath = $vmPath + $vmName + "\${vmName}.vhd"
        $newVhdx = New-VHD -Path $vhdxPath -ParentPath $parentVHD -Differencing -ComputerName $hvServer -ErrorAction SilentlyContinue
        if (-not $newVhdx)
        {
            $msg = $error[0].Exception.Message
            Write-Error -Message "Unable to create VHDX for ${vmName} : ${msg}" -Category InvalidArgument -ErrorAction SilentlyContinue
            return $False
        }

        Add-VMHardDiskDrive -VMName $vmName -ControllerType IDE -ControllerNumber 0 -ControllerLocation 0 -Path $vhdxpath -ComputerName $hvServer -ErrorAction SilentlyContinue
        if (-not $?)
        {
            $msg = $error[0].Exception.Message
            Write-Error -Message "Unable to add VHDX to VM ${vmName} : ${msg}" -Category InvalidArgument -ErrorAction SilentlyContinue
            return $False
        }

        #
        # Add a NIC and connect it to the network
        #
        Connect-VMNetworkAdapter -VMName $vmName -SwitchName $switchName -ComputerName $hvServer -ErrorAction SilentlyContinue
        if (-not $?)
        {
            $msg = $error[0].Exception.Message
            Write-Error -Message "Unable to connect NIC on VM ${vmName} : ${msg}" -Category InvalidArgument -ErrorAction SilentlyContinue
            return $False
        }

        #
        # Set the VMs memory to 2GB for the test
        #
        Set-VMMemory -vmName $vmName -StartupBytes 2GB -ComputerName $hvServer

        #
        # Start the VM
        #
        Start-VM -Name $vmName -ComputerName $hvServer
    }

    #
    # If we made it here, everything worked
    #
    return $True
}


#####################################################################
#
# Main script body
#
#####################################################################

$retVal = $False

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

"timesync.ps1"
"  vmName    = ${vmName}"
"  hvServer  = ${hvServer}"
"  testParams= ${testParams}"

#
# Parse the testParams string
#
"Parsing test parameters"
$sshKey = $null
$ipv4 = $null
$rootDir = $null
$tcCovered = "unknown"
$testDelay = "300"
$idleVmCount = 3
$switchName  = "ExternalNet"
$vmPrefix    = "IDLE_"
$parentVhd  = "SLES11Sp3x64.vhd"

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
    "Test_Delay"    { $testDelay   = $val }
    "Idle_VM_Count" { $idleVmCount = $val }
    "switch_name"   { $switchName  = $val }
    "VM_Prefix"     { $vmPrefix    = $val }
    "parentVhd"     { $parentVhd   = $val }
    default         { continue }
    }
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

#
# Change the working directory to where we should be
#
if (-not $rootDir){
    "Error: The roodDir test parameter was not provided"
    return $False
}

if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

"Info : Changing directory to ${rootDir}"
cd $rootDir

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
"Covers ${tcCovered}" >> $summaryLog

#
# Source the utility functions so we have access to them
#
. .\setupscripts\TCUtils.ps1

#
# Make sure the switch exists
#
"Info : Checking if the switch '${switchName}' exists"
if (-not (Get-VMSwitch -Name $switchName -ComputerName $hvServer))
{
    "Error: The network switch '${switchName}' does not exist"
    return $False
}

#
# Delete any Idle VMs left behind from a previous test run
#
"Info : Stopping and deleting any existing ${vmPrefix}_* VMs"
if (-not (StopAndDeleteDensityVMs $vmPrefix $hvServer))
{
    "Error : Unable to stop/delete all VMs"
    $error[0].Exception.Message
    return $False
}

#
# Create the Idle VMs required for this test run
#
"Info : Creating VMs"
$sts = CreateVMs -VMPrefix $vmPrefix -Parent $parentVHD -switchName $switchName -HVserver $hvServer -vmCount $idleVmCount
if (-not $sts)
{
    "Error: Unable to create VMs"
    $error[0].Exception.Message
    return $False
}

#
# Collect the IP address for all Idle VMs
#
$vmIPAddrs = @{}

$VMs = Get-VM -name "${vmPrefix}*" -ComputerName $hvServer
foreach ($vm in $VMs)
{
    if ($vm.State -ne "Off")
    {
        $timeout = 300

        while ($timeout -gt 0)
        {
            $ipv4 = GetIPv4 $vm.name $hvServer
            if ($ipv4)
            {
                $vmIpaddrs[$vm.Name] = $ipv4
                break
            }

            Start-Sleep -s 5
            $timeout -= 5
        }

        if ($timeout -le 0)
        {
            "Error: Unable to collect IP address for VM '$($vm.Name)'"
            StopAndDeleteDensityVMs $vmPrefix $hvServer
            return $False
        }
    }
}

"Info : Collected IP addresses"
$vmIPAddrs

#
# If the test delay was specified, sleep for a bit
#
if ($testDelay -and $testDelay -gt 0)
{
    "Sleeping for ${testDelay} seconds"
    Start-Sleep -S $testDelay
}

#
# Collect required metrics
#
$sum  = 0
$low  = 1GB
$high = 0
$avg  = 0

#
# Create an array of VM names and their CPU usage from Top
#
$topArray   = @{}
foreach ($key in $vmIpaddrs.Keys)
{
    $ipAddr = $vmIpaddrs[ $key ]

    #
    # If this is the first time we connected to the VM via SSH, we will be
    # prompted to accept the server key.  Pipe a Y response into ssh.
    #
    echo y | bin\plink -i ssh\${sshKey} root@${ipAddr} exit
    Start-Sleep -S 15   # let the spike form the above cmd settle down

    $upTime = bin\plink.exe -i .\ssh\${sshKey} root@${ipAddr} "uptime"
    if (-not $upTime)
    {
        "Error: unable to collect top data for vm '${key}'"
        return $False
    }

    $topArray[ $key ] = $upTime.Split(":")[-1].Split(",")[0].Trim()
}

"Info : Uptime data for VMs"
$topArray

$usageArray = @{}

$suts = Get-VM -name "${vmPrefix}*" -ComputerName $hvServer
foreach ($vm in $suts)
{
    $name = $vm.Name
    $cpuUsage = $vm.cpuUsage

    $usageArray[$name] = $cpuUsage
    "       {0} : {1}" -f $name, $cpuUsage

    $sum += $cpuUsage
    if ($cpuUsage -le $low)
    {
        $low = $cpuUsage
    }

    if ($cpuUsage -gt $high)
    {
        $high = $cpuUsage
    }
}

$avg = ($sum * 1.0)/$usageArray.Count

"Info : Test VMs CPU Usage"
$usageArray

"Info : Low cpu usage : ${low}"
"       High cpu usage: ${high}"
"       Avg cpu usage : ${avg}"

$retVal = $True
if ($high -gt 2)
{
    "Error: Idle test failed.  High cpuUsage = ${high}"
    $retVal = $False
}

if ($low -lt 0)
{
    "Error: Idle test failed.  Low cpuUsage less than 0 (${low})"
    $retVal =  $False
}

#
# Delete the test VMs
#
StopAndDeleteDensityVMs $vmPrefix $hvServer

return $True
