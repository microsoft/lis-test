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
    Verif a VM that has had its Assigned Memory modified can
    be saved and restored.

    The ICA scripts will always pass the vmName, hvServer, and a
    string of testParams to the PowerShell test case script. For
    example, if the <testParams> section was written as:

        <testParams>
            <param>VM1Name=SuSE-DM-VM1</param>
            <param>VM2Name=SuSE-DM-VM2</param>
        </testParams>

    The string passed in the testParams variable to the PowerShell
    test case script script would be:

        "VM1Name=SuSE-DM-VM1;VM2Name=SuSE-DM-VM2"

    Thes PowerShell test case cripts need to parse the testParam
    string to find any parameters it needs.

    All setup and cleanup scripts must return a boolean ($True or $False)
    to indicate if the script completed successfully or not.
    

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)



#######################################################################
#
# Main script body
#
#######################################################################

$retVal = $false

#
# Check input arguments
#
if (-not $vmName)
{
    "Error: VM name is null"
    return $retVal
}

if (-not $hvServer)
{
    "Error: hvServer is null"
    return $retVal
}

$sshKey = $null
$ipv4 = $null

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    switch ($fields[0].Trim())
    {
    "sshKey" { $sshKey  = $fields[1].Trim() }
    "ipv4"   { $ipv4    = $fields[1].Trim() }
	"rootdir" { $rootDir = $fields[1].Trim() }
    default  {}       
    }
}

if ($null -eq $sshKey)
{
    "Error: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4)
{
    "Error: Test parameter ipv4 was not specified"
    return $False
}

#
# Change the working directory to where we need to be
#
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

cd $rootDir

#
# Get the initial memory demand
#
$vm = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm)
{
    "Error: VM ${vmName} does not exist"
    return $False
}

$beforeDemand = $vm.MemoryDemand

#
# Create a script to run the stress tooe.
# Copy the script to the Linux VM
# convery eol to the Linux format
# start the the pressure tool on the VM
#

#
# Handle any prompt for server key
#
echo y | bin\plink -i ssh\${sshKey} root@${ipv4} exit

"stressapptest -s 60 -i 1 -M 512" | out-file -encoding ASCII -filepath startstress.sh
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

#
# Wait a few seconds to give Hyper-V some time to detect the new
# memory demand from the VM.  Then collect new memory metrics.
#
Start-Sleep -s 20

$vm = Get-VM -Name $vmName -ComputerName $hvServer 
$afterDemand = $vm.MemoryDemand

$demandDelta = $afterDemand - $beforeDemand
"Info : Before memory demand: ${beforeDemand}"
"Info : After memory demand : ${afterDemand}"
"Info : Memory Demand change by ${demandDelta}"

#
# If demand grew, test passed
#
$results = "Failed"
$retVal = $False

if ($demandDelta -gt 0)
{
    $results = "Passed"
    $retVal = $True
}
else
{
    "Error: Memory demand did not change"
}

#
#
#
"Info : Test ${results}"

return $retVal

