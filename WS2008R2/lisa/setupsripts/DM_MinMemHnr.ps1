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
        This is a PowerShell test case script that runs on the on
    the ICA host rather than the VM.

    DN_HonorMinMem  will check to see if VM's Assigned memory of VM does not get decrease beyond Mim memory assigned
    even though high priority vm on same host is under pressure.
    The ICA scripts will always pass the vmName, hvServer, and a
    string of testParams to the PowerShell test case script. For
    example, if the <testParams> section was written as:
          <testParams>  
                <param>vm1Name=OpenSuse-DM-VM1</param>
               <param>vm1MinMem=256MB</param>
               <param>vm1MaxMem=9000MB</param>
               <param>vm1StartMem=9000MB</param>
               <param>vm1MemWeight=100</param>      
           </testParams>   

    The string passed in the testParams variable to the PowerShell
    test case script script would be:

        "HeartBeatTimeout=60;TestCaseTimeout=300"

    Thes PowerShell test case cripts need to parse the testParam
    string to find any parameters it needs.

    All setup and cleanup scripts must return a boolean ($true or $false)
    to indicate if the script completed successfully or not.

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)





#######################################################################
function WaitForVMToStart([String] $vmName)
{
    Start-Sleep -s 30  # To Do - replace this with another check

    return $True
}



#######################################################################
#
# Main script body
#
#######################################################################

$retVal = $false

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

$vm2Name = $null

$params = $testParams.Split(";")

foreach ($p in $params)
{
    $fields = $p.Split("=")
    
  switch ($fields[0].Trim())
    {
    "sshKey" { $sshKey  = $fields[1].Trim() }
    "ipv4"   { $ipv4    = $fields[1].Trim() }
    "vm2Name"{ $vm2Name = $fields[1].Trim() }
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


if ($null -eq $vm2Name)
{
    "Error: Test parameter VM2 was not specified"
    return $retVal
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

$vm1Name = $vmName

#
# Verify both VMs exist
#
$vm1 = Get-VM -Name $vm1Name -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm1)
{
    "Error: VM ${vm1Name} does not exist"
    return $False
}

$vm2 = Get-VM -Name $vm2Name -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm2)
{
    "Error: VM ${vm2Name} does not exist"
    return $False
}



# Get free physical Memory

#$mem = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $hvServer
#$freememory= $mem.FreePhysicalMemory

#
# Collect metrics for VM1 again now that VM2 is up and running
#
$vm2 = Get-VM -Name $vm2Name -ComputerName $hvServer 

$beforeMemory  = $vm2.MemoryAssigned
$beforeMinimum = $vm2.MemoryMinimum
$beforeMaximum = $vm2.MemoryMaximum 
$beforeDemand  = $vm2.MemoryDemand

Start-VM -Name $vm2Name -ComputerName $hvServer 
if (-not (WaitForVMToStart))
{
    "Error: ${vm1Name} failed to start"
    return $False
}
else
{
    "Info : Starting VM ${vm2Name}"
}

# to DO add check for start vm


#
# Create a script to run the stress tooe.
# Copy the script to the Linux VM
# convery eol to the Linux format
# start the the pressure tool on the VM
#
"stressapptest -s 60 -i 1" | out-file -encoding ASCII -filepath startstress.sh
.\bin\pscp -i ssh\${sshKey} .\startstress.sh root@${ipv4}:
if (-not $?)
{
    "Error: Unable to copy startstress.sh to the VM"
    return $False
}
del startstress.sh

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
# memor demand from the VM.  Then collect new memory metrics.
#
Start-Sleep -s 30

$vm2 = Get-VM -Name $vm2Name -ComputerName $hvServer 
$afterDemand = $vm2.MemoryDemand
$afterMaxmem = $vm2.MemoryMaximum 
$afterMemory  = $vm2.MemoryAssigned
$afterMinimum = $vm2.MemoryMinimum



"Info : Before memory demand of VM ${vm2Name} is : ${beforeDemand}"
"Info : After memory demand of VM ${vm2Name} is : ${afterDemand}"
"Info : Memory Maximum Before Demand of VM ${vm2Name} is : ${beforeMaximum}"
"Info : Memory Maximum After Demand of VM ${vm2Name} is : ${afterMaxmem}"
"Info : Memory Minimum Before Demand of VM ${vm2Name} is : ${beforeMinimum}"
"Info : Memory Minimum After Demand of VM ${vm2Name} is : ${afterMinimum}"

#
# If Minimum RAM does not go below Minimum RAM after ballooning down test pass.
#
$results = "Failed"
$retVal = $False

if ($afterMinimum -lt $beforeMinimum)
{
    "Error: Memory Minimum had dereased under pressure"
}
else
{
    $results = "Passed"
    $retVal = $True
   
}

#
#
#
"Info : Test ${results}"

## shutdown VM2 to do add  check for stop.

Stop-VM -Name $vm2Name -ComputerName $hvServer 

return $retVal

