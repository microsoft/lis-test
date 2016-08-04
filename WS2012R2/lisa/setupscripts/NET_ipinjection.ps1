#####################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
#####################################################################
<#
.Synopsis
 Description: This script tests ip injection from host to guest functionality

.Parameter vmName
    Name of the VM to test.

.Parameter hvServer
    Name of the Hyper-v server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.

.Example
    .\InjectIP.ps1 "testVM" "localhost" "rootDir=D:\Lisa;IPv4Address=192.168.1.100; IPv4Subnet=255.255.255.0; IPv4Gateway=192.168.1.1; DnsServer=192.168.1.2;DHCPEnabled=False;ProtocolIFType=4096"
#>

param ([String] $vmName, [String] $hvServer, [String] $testParams, [String] $IPv4Address)

$NamespaceV2 = "root\virtualization\v2"

function ReportError($Message)
{
    Write-Host $Message -ForegroundColor Red
}

#
# Print VM Info related to replication
#
function PrintVMInfo()
{
    [System.Management.ManagementObject[]]$vmobjects = Get-WmiObject -Namespace $NamespaceV2 -Query "Select * From Msvm_ComputerSystem where Caption='Virtual Machine'"  -computername $hvServer
    CheckNullAndExit $vmobjects "Failed to find VM objects"
    Write-Host "Available Virtual Machines" -BackgroundColor Yellow -ForegroundColor Black
    foreach ($objItem in $vmobjects) {
        Write-Host "Name:             " $objItem.ElementName
        Write-Host "InstaceId:        " $objItem.Name
        Write-Host "InstallDate:      " $objItem.InstallDate
        Write-Host "ReplicationState: " @(PrintReplicationState($objItem.ReplicationState))
        Write-Host "ReplicationHealth: " @(PrintReplicationHealth($objItem.ReplicationHealth))
        Write-Host "LastReplicationTime: " @(ConvertStringToDateTime($objItem.LastReplicationTime))
        Write-Host "LastReplicationType: " @(PrintReplicationType($objItem.LastReplicationType))
        Write-Host
    }

    return $objects
}
#
# Monitors Msvm_ConcreteJob.
#
function MonitorJob($opresult)
{
    if ($opresult.ReturnValue -eq 0)
    {
        Write-Host("$TestName success.")
        return
    }
    elseif ($opresult.ReturnValue -ne 4096)
    {
        Write-Host "$TestName failed. Error code " @(PrintJobErrorCode($opresult.ReturnValue)) -ForegroundColor Red
        return
    }
    else
    {
        # Find the job to monitor status
        $jobid = $opresult.Job.Split('=')[1]
        $concreteJob = Get-WmiObject -Query "select * from CIM_ConcreteJob where InstanceId=$jobid"  -namespace $NamespaceV2 -ComputerName $hvServer

		$top = [Console]::CursorTop
		$left = [Console]::CursorLeft

	# This line returns an error, requires further data type parsing correction
    # PrintJobInformation $concreteJob

        #Loop till job not complete
        if ($concreteJob -ne $null -AND
            ($concreteJob.PercentComplete -ne 100) -AND
            ($concreteJob.ErrorCode -eq 0)
            )
        {
            Start-Sleep -Milliseconds 500

            # Following is to show progress on same position for powershell cmdline host
			if (!(get-variable  -erroraction silentlycontinue "psISE"))
			{
				[Console]::SetCursorPosition($left, $top)
			}

            MonitorJob $opresult
        }
    }
}

function CheckNullAndExit([System.Object[]] $object, [string] $message)
{
    if ($object -eq $null)
    {
        ReportError($message)
        exit 99
    }
    return
}

function CheckSingleObject([System.Object[]] $objects, [string] $message)
{
    if ($objects.Length -gt 1)
    {
        ReportError($message)
        exit 99
    }
    return
}

#
# Get VM object
#
function GetVirtualMachine([string] $vmName)
{
    $objects = Get-WmiObject -Namespace $NamespaceV2 -Query "Select * From Msvm_ComputerSystem Where ElementName = '$vmName' OR Name = '$vmName'"  -computername $hvServer
    if ($objects -eq $null)
    {
     Write-Host "Virtual Machines Not Found , Please check the VM name"
     PrintVMInfo
    }

    CheckNullAndExit $objects "Failed to find VM object for $vmName"

    if ($objects.Length -gt 1)
    {
        foreach ($objItem in $objects) {
            Write-Host "ElementName: " $objItem.ElementName
            Write-Host "Name:        " $objItem.Name
            }
        CheckSingleObject $objects "Multiple VM objects found for name $vmName. This script doesn't support this. Use Name GUID as VmName parameter."
    }

    return [System.Management.ManagementObject] $objects
}

#
# Get VM Service object
#
function GetVmServiceObject()
{
    $objects = Get-WmiObject -Namespace $NamespaceV2  -Query "Select * From Msvm_VirtualSystemManagementService"  -computername $hvServer
    CheckNullAndExit $objects "Failed to find VM service object"
    CheckSingleObject $objects "Multiple VM Service objects found"

    return $objects
}

#
# Find first Msvm_GuestNetworkAdapterConfiguration instance.
#
function GetGuestNetworkAdapterConfiguration($VMName)
{
    $VM = gwmi -Namespace root\virtualization\v2 -class Msvm_ComputerSystem -ComputerName $hvServer | where {$_.ElementName -like $VMName}
    CheckNullAndExit $VM "Failed to find VM instance"

    # Get active settings
    $vmSettings = $vm.GetRelated( "Msvm_VirtualSystemSettingData", "Msvm_SettingsDefineState",$null,$null, "SettingData", "ManagedElement", $false, $null)

    # Get all network adapters
    $nwAdapters = $vmSettings.GetRelated("Msvm_SyntheticEthernetPortSettingData")

	# Find associated guest configuration data
    $nwconfig = ($nwadapters.GetRelated("Msvm_GuestNetworkAdapterConfiguration", "Msvm_SettingDataComponent", $null, $null, "PartComponent", "GroupComponent", $false, $null) | % {$_})

    if ($nwconfig -eq $null)
    {
        Write-Host "Failed to find Msvm_GuestNetworkAdapterConfiguration instance. Creating new instance."
    }

    return $nwconfig;
}

#
# Print Msvm_FailoverNetworkAdapterSettingData
#
function PrintNetworkAdapterSettingData($nasd)
{
    foreach ($objItem in $nasd)
    {
        New-Object PSObject -Property @{
        "InstanceID: " = $objItem.InstanceID ;
        "ProtocolIFType: " = $objItem.ProtocolIFType ;
        "DHCPEnabled: " = $objItem.DHCPEnabled ;
        "IPAddresses: " = $objItem.IPAddresses ;
        "Subnets: " = $objItem.Subnets ;
        "DefaultGateways: " = $objItem.DefaultGateways ;
        "DNSServers: " = $objItem.DNSServers ;}

    }
}

function injectIpOnVm($IPv4Address)
{
    $colItems = get-wmiobject -class "Win32_NetworkAdapterConfiguration"  -namespace "root\CIMV2" -computername localhost

    foreach ($objItem in $colItems) {
        if ($objItem.DNSHostName -ne $NULL) {
            $netAdp = get-wmiobject -class "Win32_NetworkAdapter"  -Filter "GUID=`'$($objItem.SettingID)`'" -namespace "root\CIMV2" -computername localhost
            if ($netAdp.NetConnectionID -like '*External*'){
                $IPv4subnet = $objItem.IPSubnet[0]
                $IPv4Gateway = $objItem.DefaultIPGateway[0]
                $DnsServer = $objItem.DNSServerSearchOrder[0]
            }
        }
    }

    #
    # Get the VMs IP addresses before injecting, then make sure the
    # address we are to inject is not already assigned to the VM.
    #
    $vmNICs = Get-VMNetworkAdapter -vmName $vmName -ComputerName $hvServer
    $ipAddrs = @()
    foreach( $nic in $vmNICS)
    {
        foreach ($addr in $nic.IPAddresses)
        {
            $ipaddrs += $addr
        }
    }

    if ($ipAddrs -contains $IPv4Address) {
        "Error: The VM is already assigned address '${IPv4Address}'"
        exit 1
    }

   "$IPv4Address will be injected in place of $testIPv4Address"
    #
    # Collect WMI objects for the virtual machine we are interested in
    # so we can inject some IP setting into the VM.
    #
    [System.Management.ManagementObject] $vm = GetVirtualMachine($VmName)
    [System.Management.ManagementObject] $vmservice = @(GetVmServiceObject)[0]
    [System.Management.ManagementObject] $nwconfig = @(GetGuestNetworkAdapterConfiguration($VmName))[0];

    #
    # Fill in the IP address data we want to inject
    #
    $nwconfig.DHCPEnabled = $DHCPEnabled
    $nwconfig.IPAddresses = @($IPv4Address)
    $nwconfig.Subnets = @($IPv4Subnet)
    $nwconfig.DefaultGateways = @($IPv4Gateway)
    $nwconfig.DNSServers = @($DnsServer)

    # Note: Address family values for settings IPv4 , IPv6 Or Boths
    #   For IPv4:    ProtocolIFType = 4096;
    #   For IPv6:    ProtocolIFType = 4097;
    #   For IPv4/V6: ProtocolIFType = 4098;
    $nwconfig.ProtocolIFType = $ProtocolIFType

    #
    # Inject the IP data into the VM
    #
    $opresult = $vmservice.SetGuestNetworkAdapterConfiguration($vm.Path, @($nwconfig.GetText(1)))
    MonitorJob($opresult)
}

##############################################################################
#
# Main script body
#
##############################################################################

#
# Parse the testParams
#
$tcCovered = "Unknown"
$rootDir = $null
$DHCPEnabled = $False
$ProtocolIFType = 4096

$params = $testParams.TrimEnd(";").Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    $value = $fields[1].Trim()

    switch ($fields[0].Trim())
    {
    "dhcpenabled"    { $DHCPEnabled    = $fields[1].Trim() }
    "ipv4address"    { $IPv4Address    = $fields[1].Trim() }
    "ipv4subnet"     { $IPv4subnet     = $fields[1].Trim() }
    "dnsserver"      { $DnsServer      = $fields[1].Trim() }
    "ipv4Gateway"    { $IPv4Gateway    = $fields[1].Trim() }
    "protocoliftype" { $ProtocolIFType = $fields[1].Trim() }
    "rootdir"        { $rootDir   = $fields[1].Trim() }
    "TC_COVERED"     { $tcCovered = $fields[1].Trim() }
    default          {}  # unknown param - just ignore it
    }
}

#
# Change the working directory to where LISA is located
#
if (-not $rootDir)
{
    "Warn : no rootDir test parameter was specified"
}

cd $rootDir

$summaryLog  = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
echo "Covers : ${tcCovered}" > $summarylog


# change working directory to root dir
$testParams -match "RootDir=([^;]+)"
if (-not $?)
{
    "Mandatory param RootDir=Path; not found!"
    return $false
}
$rootDir = $Matches[1]

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
}
else
{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}

# Source NET_UTILS.ps1 for network functions
if (Test-Path ".\setupScripts\NET_UTILS.ps1")
{
    . .\setupScripts\NET_UTILS.ps1
}
else
{
    "Error: Could not find setupScripts\NET_Utils.ps1"
    return $false
}

#
# Check input arguments
#
if ($vmName -eq $null)
{
    "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null)
{
    "Error: hvServer is null"
    return $retVal
}

if ($testParams -eq $null -or $testParams.Length -lt 3)
{
    "The script $MyInvocation.InvocationName requires the VCPU test parameter"
    return $retVal
}

$oldIpAddress = $null
$isPassed= $false


$testIPv4Address = GetIPv4 $vmName $hvServer


for ($i=0; $i -le 2; $i++)
{
  if ($IPv4Address -eq $null -or $IPv4Address -eq "" )
  {
     $IPv4Address = GenerateIpv4 $testIPv4Address $oldIpAddress
  }
    injectIpOnVm $IPv4Address
    #
    # Now collect the IP addresses assigned to the VM and make
    # sure the injected address is in the list.
    #
    Start-Sleep 20
    $vmNICs = Get-VMNetworkAdapter -vmName $vmName -ComputerName $hvServer
    $ipAddrs = @()
    foreach( $nic in $vmNICS)
    {
        foreach ($addr in $nic.IPAddresses)
        {
            $ipaddrs += $addr
        }
    }

    if ($ipAddrs -notcontains $IPv4Address) {
        "Info: The address '${IPv4Address}' was not injected into the VM. `n"
        $oldIpAddress = $IPv4Address
    }
    else{
        "Info: The address '${IPv4Address}' was successfully injected into the VM. `n"
        $isPassed = $true
        break
    }
}

if ($isPassed -eq $false){
    "Error: All attempts failed"
    exit 1
}

"Info : IP Injection test passed"
return $True
