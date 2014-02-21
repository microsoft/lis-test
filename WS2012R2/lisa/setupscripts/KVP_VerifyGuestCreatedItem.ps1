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
    Linux VM creates a KVP item, then verify from the host.

.Description
    A Linux VM will create a non-intrinsic KVP item.  Then
    verify the host can see the KVP item.

    A typical XML definition for this test case would look similar
    to the following:
        <test>
            <testName>KVP_Push_Key_Values</testName>
            <testScript>setupscripts\KVP_VerifyGuestCreatedItem.ps1</testScript>
            <files>tools/KVP/kvp_client</files>
            <timeout>600</timeout>
            <onError>Abort</onError>
            <noReboot>True</noReboot>
            <testparams>
                <param>Key=BBB</param>
                <param>Value=111</param>
                <param>sshKey=rhel5_id_rsa.ppk</param>
                <param>rootDir=D:\lisa\trunk\lisablue</param>
            </testparams>
        </test>

.Parameter vmName
    Name of the VM to read intrinsic data from.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\KVP_VerifyGuestCreatedItem.ps1 -vmName "myVm" -hvServer "localhost -TestParams "key=AAA;value=111;sshKey=rhel5_id_rsa.ppk"

.Link
    None.
#>


param( [String] $vmName, [String] $hvServer, [String] $testParams )


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
#
# Main script body
#
#######################################################################

#
# Make sure the required arguments were passed
#
if (-not $vmName)
{
    "Error: no VMName was specified"
    return $False
}

if (-not $hvServer)
{
    "Error: No hvServer was specified"
    return $False
}

if (-not $testParams)
{
    "Error: No test parameters specified"
    return $False
}

#
# For loggine purposes, display the testParams
#
"Info : TestParams : '${testParams}'"

#
# Parse the test parameters
#
$key = $null
$value = $null
$sshKey = $null
$rootDir = $null
$tcCovered = $null

"Info : Parsing test params"

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    if ($fields.count -ne 2)
    {
        continue
    }
    $rValue = $fields[1].Trim()

    switch ($fields[0].Trim())
    {      
    "key"        { $key       = $rValue }
    "value"      { $value     = $rValue }
    "sshKey"     { $sshKey    = $rValue }
    "rootdir"    { $rootDir   = $rValue }
    "tc_covered" { $tcCovered = $rValue }
    default      {}       
    }
}

#
# Ensure all required test parameters were provided
#
"Info : Checking the required test parameters"
if (-not $key)
{
    "Error: The 'key' test parameter was not provided"
    return $False
}

if (-not $value)
{
    "Error: The 'value' test parameter was not provided"
    return $False
}

if (-not $sshKey)
{
    "Error: The 'sshKey' test parameter was not provided"
    return $False
}

if (-not $tcCovers)
{
    "Warn : the TC_COVERED test parameter was not provided"
}

if (-not $rootDir)
{
    "Warn : no rootdir was specified"
}
else
{
    cd $rootDir
}

$summaryLog  = "${vmName}_summary.log"
Del $summaryLog -ErrorAction SilentlyContinue
echo "Covers : ${tcCovered}" >> $summaryLog

#
# Source the TCUtils.ps1 file so we have access to the 
# functions it provides.
#
. .\setupScripts\TCUtils.ps1 | out-null

#
# Verify the Data Exchange Service is enabled for the test VM
#
"Info : Creating Integrated Service object"

$des = Get-VMIntegrationService -vmname $vmName -ComputerName $hvServer
if (-not $des)
{
    "Error: Unable to retrieve Integration Service status from VM '${vmName}'"
    return $False
}

foreach ($svc in $des)
{
    if ($svc.Name -eq "Key-Value Pair Exchange")
    {
        if (-not $svc.Enabled)
        {
            "Error: The Data Exchange Service is not enabled for VM '${vmName}'"
            return $False
        }
        break
    }
}

#
# Determine the test VMs IP address
#
"Info : Determining the VMs IPv4 address"

$ipv4 = GetIPv4 $vmName $hvServer
if (-not $ipv4)
{
    "Error: Unable to determine IPv4 address of VM '${vmName}'"
    return $False
}

#
# The kvp_client file should be listed in the <files> tab of
# the test case definition, which tells the stateEngine to
# copy the file to the test VM.  Set the x bit on the kvp_client
# image, then run kvp_client to add a non-intrinsic kvp item 
#
"Info : chmod 755 kvp_client"
$cmd = "chmod 755 ./kvp_client"
if (-not (SendCommandToVM $ipv4 $sshKey "${cmd}" ))
{
    "Error: Unable to set the x bit on kvp_client"
    return $False
}

"Info : kvp_client append 1 ${key} ${value}"
$cmd = "./kvp_client append 1 ${key} ${value}"
if (-not (SendCommandToVM $ipv4 $sshKey "${cmd}"))
{
    "Error: Unable to run kvp_client on VM '${vmName}'"
    return $False
}

#
# Create a data exchange object and collect non-intrinsic KVP data from the VM
#
"Info : Collecting nonintrinsic KVP data from guest"
$Vm = Get-WmiObject -Namespace root\virtualization\v2 -Query "Select * From Msvm_ComputerSystem Where ElementName=`'$VMName`'"
if (-not $Vm)
{
    "Error: Unable to the VM '${VMName}' on the local host"
    return $False
}

$Kvp = Get-WmiObject -Namespace root\virtualization\v2 -Query "Associators of {$Vm} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent"
if (-not $Kvp)
{
    "Error: Unable to retrieve KVP Exchange object for VM '${vmName}'"
    return $False
}

$kvpData = $Kvp.GuestExchangeItems
if (-not $kvpData)
{
    "Error: KVP NonIntrinsic data is null"
    return $False
}

$dict = KvpToDict $kvpData

#
# For logging purposed, display all kvp data
#
"Info : Non-Intrinsic data"
foreach ($key in $dict.Keys)
{
    $value = $dict[$key]
    Write-Output ("       {0,-27} : {1}" -f $key, $value)
}

#
# Check to make sure the guest created KVP item is returned
#
if (-not $dict.ContainsKey($key))
{
    "Error: The key '${key}' does not exist in the non-intrinsic data"
    return $False
}

$data = $dict[ $key ]
if ( $data -ne $value)
{
    "Error: The KVP item has an incorrect value:  ${key} = ${value}"
    return $False
}

#
# If we made it here, everything worked
#
"Info : test passed"
return $True
